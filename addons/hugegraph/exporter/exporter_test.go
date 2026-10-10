package exporter

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/prometheus/common/expfmt"
)

const (
	testUsername = "metrics-reader"
	testPassword = "do-not-disclose-password"
)

func TestDefaultConfigLocksCollectionBudget(t *testing.T) {
	config := DefaultConfig()
	if config.Endpoint != "http://127.0.0.1:8080/metrics?type=json" {
		t.Fatalf("unexpected endpoint: %q", config.Endpoint)
	}
	if config.CollectionInterval != 60*time.Second {
		t.Fatalf("unexpected collection interval: %s", config.CollectionInterval)
	}
	if config.RequestTimeout != 5*time.Second {
		t.Fatalf("unexpected request timeout: %s", config.RequestTimeout)
	}
	if config.MaxBodyBytes != 1<<20 {
		t.Fatalf("unexpected body limit: %d", config.MaxBodyBytes)
	}
}

func TestRefreshUsesBasicAuthAndExportsAllowlistedMetrics(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		username, password, ok := request.BasicAuth()
		if !ok || username != testUsername || password != testPassword {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		_, _ = w.Write([]byte(fullFixture(11)))
	}))
	t.Cleanup(server.Close)

	exporter := newTestExporter(t, server.URL)
	if err := exporter.Refresh(context.Background()); err != nil {
		t.Fatalf("refresh failed: %v", err)
	}

	expected := `
# HELP hugegraph_http_requests_total HugeGraph HTTP requests observed by the engine.
# TYPE hugegraph_http_requests_total counter
hugegraph_http_requests_total{method="GET",result="total",route="/graphspaces/DEFAULT/graphs/graph/vertices"} 11
# HELP hugegraph_http_response_time_ms HugeGraph HTTP response time snapshot in milliseconds.
# TYPE hugegraph_http_response_time_ms gauge
hugegraph_http_response_time_ms{method="GET",route="/graphspaces/DEFAULT/graphs/graph/vertices",stat="max"} 30
hugegraph_http_response_time_ms{method="GET",route="/graphspaces/DEFAULT/graphs/graph/vertices",stat="mean"} 12.5
hugegraph_http_response_time_ms{method="GET",route="/graphspaces/DEFAULT/graphs/graph/vertices",stat="p95"} 20
hugegraph_http_response_time_ms{method="GET",route="/graphspaces/DEFAULT/graphs/graph/vertices",stat="p99"} 28
# HELP hugegraph_transaction_commits_total HugeGraph transaction commit outcomes.
# TYPE hugegraph_transaction_commits_total counter
hugegraph_transaction_commits_total{result="succeed"} 9
# HELP hugegraph_gremlin_errors_total HugeGraph Gremlin server errors.
# TYPE hugegraph_gremlin_errors_total counter
hugegraph_gremlin_errors_total 2
# HELP hugegraph_tasks_pending HugeGraph pending tasks.
# TYPE hugegraph_tasks_pending gauge
hugegraph_tasks_pending{pool="task"} 3
# HELP hugegraph_task_workers HugeGraph task workers.
# TYPE hugegraph_task_workers gauge
hugegraph_task_workers{pool="task",state="configured"} 4
# HELP hugegraph_cache_events_total HugeGraph cache events.
# TYPE hugegraph_cache_events_total counter
hugegraph_cache_events_total{cache="vertices",event="hit",graph="DEFAULT/hugegraph"} 7
# HELP hugegraph_cache_entries HugeGraph cache entries and capacity.
# TYPE hugegraph_cache_entries gauge
hugegraph_cache_entries{cache="vertices",graph="DEFAULT/hugegraph",state="capacity"} 100
`
	if err := testutil.CollectAndCompare(
		exporter,
		strings.NewReader(expected),
		"hugegraph_http_requests_total",
		"hugegraph_http_response_time_ms",
		"hugegraph_transaction_commits_total",
		"hugegraph_gremlin_errors_total",
		"hugegraph_tasks_pending",
		"hugegraph_task_workers",
		"hugegraph_cache_events_total",
		"hugegraph_cache_entries",
	); err != nil {
		t.Fatal(err)
	}

	metrics := collectText(t, exporter)
	if strings.Contains(metrics, `route="/metrics`) {
		t.Fatalf("self traffic leaked into business metrics:\n%s", metrics)
	}
}

func TestRefreshPreservesLastSuccessAndMarksStale(t *testing.T) {
	var fail atomic.Bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if fail.Load() {
			http.Error(w, "sensitive response body", http.StatusInternalServerError)
			return
		}
		_, _ = w.Write([]byte(fullFixture(17)))
	}))
	t.Cleanup(server.Close)

	var logs bytes.Buffer
	exporter := newTestExporterWithLogger(t, server.URL, log.New(&logs, "", 0))
	if err := exporter.Refresh(context.Background()); err != nil {
		t.Fatalf("initial refresh failed: %v", err)
	}
	fail.Store(true)
	if err := exporter.Refresh(context.Background()); err == nil {
		t.Fatal("expected failed refresh")
	}

	metrics := collectText(t, exporter)
	for _, expected := range []string{
		"hugegraph_collection_up 0",
		"hugegraph_collection_stale 1",
		"hugegraph_collection_last_success_unixtime_seconds 1.7e+09",
		`hugegraph_collection_errors_total{stage="status"} 1`,
		`hugegraph_http_requests_total{method="GET",result="total",route="/graphspaces/DEFAULT/graphs/graph/vertices"} 17`,
	} {
		if !strings.Contains(metrics, expected) {
			t.Fatalf("missing %q in metrics:\n%s", expected, metrics)
		}
	}
	for _, secret := range []string{testUsername, testPassword, "sensitive response body", "Basic ", "Authorization"} {
		if strings.Contains(logs.String(), secret) {
			t.Fatalf("log disclosed %q: %s", secret, logs.String())
		}
	}
}

func TestRefreshIsSingleFlight(t *testing.T) {
	var requests atomic.Int32
	entered := make(chan struct{})
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if requests.Add(1) == 1 {
			close(entered)
		}
		<-release
		_, _ = w.Write([]byte(fullFixture(1)))
	}))
	t.Cleanup(server.Close)

	exporter := newTestExporter(t, server.URL)
	const callers = 16
	var waitGroup sync.WaitGroup
	waitGroup.Add(callers)
	for range callers {
		go func() {
			defer waitGroup.Done()
			if err := exporter.Refresh(context.Background()); err != nil {
				t.Errorf("refresh failed: %v", err)
			}
		}()
	}
	<-entered
	time.Sleep(20 * time.Millisecond)
	close(release)
	waitGroup.Wait()
	if got := requests.Load(); got != 1 {
		t.Fatalf("expected one upstream request, got %d", got)
	}
}

func TestMetricsScrapesUseCacheAndProduceValidPrometheusText(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		_, _ = w.Write([]byte(fullFixture(8)))
	}))
	t.Cleanup(server.Close)

	exporter := newTestExporter(t, server.URL)
	if err := exporter.Refresh(context.Background()); err != nil {
		t.Fatalf("refresh failed: %v", err)
	}
	handler := exporter.MetricsHandler()
	for range 10 {
		request := httptest.NewRequest(http.MethodGet, "/metrics", nil)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != http.StatusOK {
			t.Fatalf("unexpected scrape status: %d", response.Code)
		}
		parser := expfmt.TextParser{}
		if _, err := parser.TextToMetricFamilies(response.Body); err != nil {
			t.Fatalf("invalid Prometheus text: %v", err)
		}
	}
	if got := requests.Load(); got != 1 {
		t.Fatalf("scrapes triggered %d upstream requests, want 1", got)
	}
}

func TestRefreshClassifiesAuthDecodeAndSchemaFailures(t *testing.T) {
	tests := []struct {
		name       string
		statusCode int
		body       string
		stage      string
	}{
		{name: "auth", statusCode: http.StatusUnauthorized, body: "do-not-log-auth-body", stage: "auth"},
		{name: "decode", statusCode: http.StatusOK, body: `{not-json}`, stage: "decode"},
		{name: "trailing-json", statusCode: http.StatusOK, body: fullFixture(1) + `{}`, stage: "decode"},
		{name: "schema", statusCode: http.StatusOK, body: `{"gauges":{},"counters":{},"histograms":{},"meters":{}}`, stage: "schema"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(test.statusCode)
				_, _ = io.WriteString(w, test.body)
			}))
			t.Cleanup(server.Close)

			var logs bytes.Buffer
			exporter := newTestExporterWithLogger(t, server.URL, log.New(&logs, "", 0))
			if err := exporter.Refresh(context.Background()); err == nil {
				t.Fatal("expected refresh failure")
			}
			metrics := collectText(t, exporter)
			expected := fmt.Sprintf(`stage="%s"} 1`, test.stage)
			if !strings.Contains(metrics, expected) {
				t.Fatalf("missing %q: %s", expected, metrics)
			}
			if strings.Contains(logs.String(), test.body) {
				t.Fatalf("response body leaked to logs: %s", logs.String())
			}
		})
	}
}

func TestConfigRejectsURLUserInfo(t *testing.T) {
	config := DefaultConfig()
	config.Endpoint = "http://user:password@127.0.0.1:8080/metrics?type=json"
	config.Username = testUsername
	config.Password = testPassword
	if _, err := New(config, log.New(io.Discard, "", 0)); err == nil {
		t.Fatal("expected URL user information to be rejected")
	}
}

func TestCounterResetExportsNewRawValue(t *testing.T) {
	var count atomic.Int64
	count.Store(100)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprint(w, fullFixture(count.Load()))
	}))
	t.Cleanup(server.Close)

	exporter := newTestExporter(t, server.URL)
	if err := exporter.Refresh(context.Background()); err != nil {
		t.Fatalf("first refresh failed: %v", err)
	}
	count.Store(3)
	if err := exporter.Refresh(context.Background()); err != nil {
		t.Fatalf("reset refresh failed: %v", err)
	}
	metrics := collectText(t, exporter)
	expected := `hugegraph_http_requests_total{method="GET",result="total",route="/graphspaces/DEFAULT/graphs/graph/vertices"} 3`
	if !strings.Contains(metrics, expected) {
		t.Fatalf("counter reset was not preserved: %s", metrics)
	}
}

func TestRefreshRejectsOversizedAndSlowResponses(t *testing.T) {
	t.Run("body limit", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write(bytes.Repeat([]byte("x"), 129))
		}))
		t.Cleanup(server.Close)

		config := testConfig(server.URL)
		config.MaxBodyBytes = 128
		exporter, err := New(config, log.New(&bytes.Buffer{}, "", 0))
		if err != nil {
			t.Fatalf("new exporter: %v", err)
		}
		if err := exporter.Refresh(context.Background()); err == nil {
			t.Fatal("expected body-size error")
		}
		if metrics := collectText(t, exporter); !strings.Contains(metrics, `stage="body_size"} 1`) {
			t.Fatalf("body-size error not classified: %s", metrics)
		}
	})

	t.Run("timeout", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			time.Sleep(100 * time.Millisecond)
			_, _ = w.Write([]byte(fullFixture(1)))
		}))
		t.Cleanup(server.Close)

		config := testConfig(server.URL)
		config.RequestTimeout = 10 * time.Millisecond
		exporter, err := New(config, log.New(&bytes.Buffer{}, "", 0))
		if err != nil {
			t.Fatalf("new exporter: %v", err)
		}
		if err := exporter.Refresh(context.Background()); err == nil {
			t.Fatal("expected timeout")
		}
		if metrics := collectText(t, exporter); !strings.Contains(metrics, `stage="timeout"} 1`) {
			t.Fatalf("timeout not classified: %s", metrics)
		}
	})
}

func TestCardinalityFailurePreservesLastSnapshot(t *testing.T) {
	var payload atomic.Value
	payload.Store(fullFixture(5))
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(payload.Load().(string)))
	}))
	t.Cleanup(server.Close)

	config := testConfig(server.URL)
	config.MaxRoutes = 1
	exporter, err := New(config, log.New(&bytes.Buffer{}, "", 0))
	if err != nil {
		t.Fatalf("new exporter: %v", err)
	}
	if err := exporter.Refresh(context.Background()); err != nil {
		t.Fatalf("initial refresh failed: %v", err)
	}
	payload.Store(twoRouteFixture())
	if err := exporter.Refresh(context.Background()); err == nil {
		t.Fatal("expected cardinality error")
	}
	metrics := collectText(t, exporter)
	for _, expected := range []string{
		`stage="cardinality"} 1`,
		`route="/graphspaces/DEFAULT/graphs/graph/vertices"} 5`,
	} {
		if !strings.Contains(metrics, expected) {
			t.Fatalf("missing %q after cardinality failure: %s", expected, metrics)
		}
	}
}

func newTestExporter(t *testing.T, endpoint string) *Exporter {
	t.Helper()
	return newTestExporterWithLogger(t, endpoint, log.New(&bytes.Buffer{}, "", 0))
}

func newTestExporterWithLogger(t *testing.T, endpoint string, logger *log.Logger) *Exporter {
	t.Helper()
	exporter, err := New(testConfig(endpoint), logger)
	if err != nil {
		t.Fatalf("new exporter: %v", err)
	}
	return exporter
}

func testConfig(endpoint string) Config {
	config := DefaultConfig()
	config.Endpoint = endpoint
	config.Username = testUsername
	config.Password = testPassword
	config.Now = func() time.Time { return time.Unix(1700000000, 0) }
	return config
}

func collectText(t *testing.T, exporter *Exporter) string {
	t.Helper()
	output, err := testutil.CollectAndFormat(exporter, expfmt.TypeTextPlain,
		"hugegraph_collection_up",
		"hugegraph_collection_stale",
		"hugegraph_collection_last_success_unixtime_seconds",
		"hugegraph_collection_errors_total",
		"hugegraph_http_requests_total",
		"hugegraph_http_response_time_ms",
		"hugegraph_transaction_commits_total",
		"hugegraph_gremlin_errors_total",
		"hugegraph_tasks_pending",
		"hugegraph_task_workers",
		"hugegraph_cache_events_total",
		"hugegraph_cache_entries",
	)
	if err != nil {
		t.Fatalf("collect metrics: %v", err)
	}
	return string(output)
}

func fullFixture(requestCount int64) string {
	return fmt.Sprintf(`{
  "gauges": {
    "org.apache.hugegraph.backend.cache.Cache.vertices-DEFAULT/hugegraph.hits": {"value": 7},
    "org.apache.hugegraph.backend.cache.Cache.vertices-DEFAULT/hugegraph.capacity": {"value": 100},
    "org.apache.hugegraph.task.TaskManager.pending-tasks": {"value": 3},
    "org.apache.hugegraph.task.TaskManager.workers": {"value": 4}
  },
  "counters": {
    "graphspaces/DEFAULT/graphs/graph/vertices/GET/TOTAL_COUNTER": {"count": %d},
    "metrics/GET/TOTAL_COUNTER": {"count": 99}
  },
  "histograms": {
    "graphspaces/DEFAULT/graphs/graph/vertices/GET/RESPONSE_TIME_HISTOGRAM": {
      "count": %d,
      "snapshot": {"max": 30, "mean": 12.5, "95thPercentile": 20, "99thPercentile": 28}
    },
    "metrics/GET/RESPONSE_TIME_HISTOGRAM": {
      "count": 1,
      "snapshot": {"max": 2, "mean": 2, "95thPercentile": 2, "99thPercentile": 2}
    }
  },
  "meters": {
    "org.apache.hugegraph.api.API.commit-succeed": {"count": 9},
    "org.apache.tinkerpop.gremlin.server.GremlinServer.errors": {"count": 2}
  },
  "timers": {
    "org.apache.hugegraph.example.ignored-timer": {"count": 1, "snapshot": {"max": 1}}
  }
}`, requestCount, requestCount)
}

func twoRouteFixture() string {
	return `{
  "gauges": {},
  "counters": {
    "graphspaces/DEFAULT/graphs/graph/vertices/GET/TOTAL_COUNTER": {"count": 6},
    "graphspaces/DEFAULT/graphs/graph/edges/GET/TOTAL_COUNTER": {"count": 2}
  },
  "histograms": {},
  "meters": {},
  "timers": {}
}`
}
