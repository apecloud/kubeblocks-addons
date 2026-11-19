package exporter

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	defaultEndpoint           = "http://127.0.0.1:8080/metrics?type=json"
	defaultCollectionInterval = 60 * time.Second
	defaultRequestTimeout     = 5 * time.Second
	defaultMaxBodyBytes       = int64(1 << 20)
	defaultMaxRoutes          = 128
	defaultMaxCaches          = 64
)

type Config struct {
	Endpoint           string
	Username           string
	Password           string
	CollectionInterval time.Duration
	RequestTimeout     time.Duration
	MaxBodyBytes       int64
	MaxRoutes          int
	MaxCaches          int
	Now                func() time.Time
}

func DefaultConfig() Config {
	return Config{
		Endpoint:           defaultEndpoint,
		CollectionInterval: defaultCollectionInterval,
		RequestTimeout:     defaultRequestTimeout,
		MaxBodyBytes:       defaultMaxBodyBytes,
		MaxRoutes:          defaultMaxRoutes,
		MaxCaches:          defaultMaxCaches,
		Now:                time.Now,
	}
}

type metricSample struct {
	desc      *prometheus.Desc
	valueType prometheus.ValueType
	value     float64
	labels    []string
}

type collectionState struct {
	samples     []metricSample
	up          float64
	stale       float64
	lastSuccess float64
	errors      map[string]uint64
}

type Exporter struct {
	config Config
	client *http.Client
	logger *log.Logger

	stateMu sync.RWMutex
	state   collectionState

	flightMu sync.Mutex
	inflight chan struct{}
	lastErr  error
}

func New(config Config, logger *log.Logger) (*Exporter, error) {
	if err := normalizeConfig(&config); err != nil {
		return nil, err
	}
	if logger == nil {
		logger = log.New(io.Discard, "", 0)
	}
	return &Exporter{
		config: config,
		client: &http.Client{Timeout: config.RequestTimeout},
		logger: logger,
		state: collectionState{
			errors: make(map[string]uint64),
		},
	}, nil
}

func normalizeConfig(config *Config) error {
	if config.Endpoint == "" {
		config.Endpoint = defaultEndpoint
	}
	parsed, err := url.Parse(config.Endpoint)
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return errors.New("invalid metrics endpoint")
	}
	if parsed.User != nil {
		return errors.New("metrics endpoint must not contain user information")
	}
	if config.Username == "" || config.Password == "" {
		return errors.New("metrics credentials are required")
	}
	if config.CollectionInterval <= 0 {
		config.CollectionInterval = defaultCollectionInterval
	}
	if config.RequestTimeout <= 0 {
		config.RequestTimeout = defaultRequestTimeout
	}
	if config.MaxBodyBytes <= 0 {
		config.MaxBodyBytes = defaultMaxBodyBytes
	}
	if config.MaxRoutes <= 0 {
		config.MaxRoutes = defaultMaxRoutes
	}
	if config.MaxCaches <= 0 {
		config.MaxCaches = defaultMaxCaches
	}
	if config.Now == nil {
		config.Now = time.Now
	}
	return nil
}

func (exporter *Exporter) Refresh(ctx context.Context) error {
	exporter.flightMu.Lock()
	if exporter.inflight != nil {
		inflight := exporter.inflight
		exporter.flightMu.Unlock()
		select {
		case <-inflight:
			exporter.flightMu.Lock()
			err := exporter.lastErr
			exporter.flightMu.Unlock()
			return err
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	exporter.inflight = make(chan struct{})
	inflight := exporter.inflight
	exporter.flightMu.Unlock()

	err := exporter.refreshOnce(ctx)

	exporter.flightMu.Lock()
	exporter.lastErr = err
	close(inflight)
	exporter.inflight = nil
	exporter.flightMu.Unlock()
	return err
}

func (exporter *Exporter) refreshOnce(ctx context.Context) error {
	requestContext, cancel := context.WithTimeout(ctx, exporter.config.RequestTimeout)
	defer cancel()

	request, err := http.NewRequestWithContext(requestContext, http.MethodGet, exporter.config.Endpoint, nil)
	if err != nil {
		return exporter.recordFailure("request")
	}
	request.SetBasicAuth(exporter.config.Username, exporter.config.Password)
	response, err := exporter.client.Do(request)
	if err != nil {
		if errors.Is(requestContext.Err(), context.DeadlineExceeded) {
			return exporter.recordFailure("timeout")
		}
		return exporter.recordFailure("connect")
	}
	defer response.Body.Close()

	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return exporter.recordFailure("auth")
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return exporter.recordFailure("status")
	}

	body, err := io.ReadAll(io.LimitReader(response.Body, exporter.config.MaxBodyBytes+1))
	if err != nil {
		return exporter.recordFailure("read")
	}
	if int64(len(body)) > exporter.config.MaxBodyBytes {
		return exporter.recordFailure("body_size")
	}

	samples, parseErr := parsePayload(body, exporter.config.MaxRoutes, exporter.config.MaxCaches)
	if parseErr != nil {
		return exporter.recordFailure(parseErr.stage)
	}

	exporter.stateMu.Lock()
	exporter.state.samples = samples
	exporter.state.up = 1
	exporter.state.stale = 0
	exporter.state.lastSuccess = float64(exporter.config.Now().Unix())
	exporter.stateMu.Unlock()
	return nil
}

func (exporter *Exporter) recordFailure(stage string) error {
	exporter.stateMu.Lock()
	exporter.state.up = 0
	if len(exporter.state.samples) > 0 {
		exporter.state.stale = 1
	}
	exporter.state.errors[stage]++
	exporter.stateMu.Unlock()
	exporter.logger.Printf("collection failed at stage %s", stage)
	return fmt.Errorf("collection failed at stage %s", stage)
}

func (exporter *Exporter) Run(ctx context.Context) {
	_ = exporter.Refresh(ctx)
	ticker := time.NewTicker(exporter.config.CollectionInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			_ = exporter.Refresh(ctx)
		}
	}
}

func (exporter *Exporter) MetricsHandler() http.Handler {
	registry := prometheus.NewRegistry()
	registry.MustRegister(exporter)
	return promhttp.HandlerFor(registry, promhttp.HandlerOpts{})
}

func (exporter *Exporter) Describe(channel chan<- *prometheus.Desc) {
	for _, desc := range allDescs {
		channel <- desc
	}
}

func (exporter *Exporter) Collect(channel chan<- prometheus.Metric) {
	exporter.stateMu.RLock()
	state := collectionState{
		samples:     append([]metricSample(nil), exporter.state.samples...),
		up:          exporter.state.up,
		stale:       exporter.state.stale,
		lastSuccess: exporter.state.lastSuccess,
		errors:      make(map[string]uint64, len(exporter.state.errors)),
	}
	for stage, count := range exporter.state.errors {
		state.errors[stage] = count
	}
	exporter.stateMu.RUnlock()

	channel <- prometheus.MustNewConstMetric(collectionUpDesc, prometheus.GaugeValue, state.up)
	channel <- prometheus.MustNewConstMetric(collectionStaleDesc, prometheus.GaugeValue, state.stale)
	channel <- prometheus.MustNewConstMetric(lastSuccessDesc, prometheus.GaugeValue, state.lastSuccess)
	for stage, count := range state.errors {
		channel <- prometheus.MustNewConstMetric(collectionErrorsDesc, prometheus.CounterValue, float64(count), stage)
	}
	for _, sample := range state.samples {
		channel <- prometheus.MustNewConstMetric(sample.desc, sample.valueType, sample.value, sample.labels...)
	}
}

var (
	collectionUpDesc = prometheus.NewDesc(
		"hugegraph_collection_up",
		"Whether the latest HugeGraph JSON collection succeeded.",
		nil, nil,
	)
	collectionStaleDesc = prometheus.NewDesc(
		"hugegraph_collection_stale",
		"Whether the exporter is serving the last successful snapshot after a collection failure.",
		nil, nil,
	)
	lastSuccessDesc = prometheus.NewDesc(
		"hugegraph_collection_last_success_unixtime_seconds",
		"Unix time of the last successful HugeGraph JSON collection.",
		nil, nil,
	)
	collectionErrorsDesc = prometheus.NewDesc(
		"hugegraph_collection_errors_total",
		"HugeGraph JSON collection failures by bounded stage.",
		[]string{"stage"}, nil,
	)
	httpRequestsDesc = prometheus.NewDesc(
		"hugegraph_http_requests_total",
		"HugeGraph HTTP requests observed by the engine.",
		[]string{"route", "method", "result"}, nil,
	)
	httpResponseTimeDesc = prometheus.NewDesc(
		"hugegraph_http_response_time_ms",
		"HugeGraph HTTP response time snapshot in milliseconds.",
		[]string{"route", "method", "stat"}, nil,
	)
	transactionCommitsDesc = prometheus.NewDesc(
		"hugegraph_transaction_commits_total",
		"HugeGraph transaction commit outcomes.",
		[]string{"result"}, nil,
	)
	gremlinErrorsDesc = prometheus.NewDesc(
		"hugegraph_gremlin_errors_total",
		"HugeGraph Gremlin server errors.",
		nil, nil,
	)
	cacheEventsDesc = prometheus.NewDesc(
		"hugegraph_cache_events_total",
		"HugeGraph cache events.",
		[]string{"graph", "cache", "event"}, nil,
	)
	cacheEntriesDesc = prometheus.NewDesc(
		"hugegraph_cache_entries",
		"HugeGraph cache entries and capacity.",
		[]string{"graph", "cache", "state"}, nil,
	)
	tasksPendingDesc = prometheus.NewDesc(
		"hugegraph_tasks_pending",
		"HugeGraph pending tasks.",
		[]string{"pool"}, nil,
	)
	taskWorkersDesc = prometheus.NewDesc(
		"hugegraph_task_workers",
		"HugeGraph task workers.",
		[]string{"pool", "state"}, nil,
	)
	allDescs = []*prometheus.Desc{
		collectionUpDesc,
		collectionStaleDesc,
		lastSuccessDesc,
		collectionErrorsDesc,
		httpRequestsDesc,
		httpResponseTimeDesc,
		transactionCommitsDesc,
		gremlinErrorsDesc,
		cacheEventsDesc,
		cacheEntriesDesc,
		tasksPendingDesc,
		taskWorkersDesc,
	}
)
