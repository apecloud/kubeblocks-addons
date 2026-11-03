package exporter

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/prometheus/client_golang/prometheus"
)

const (
	cacheMetricPrefix = "org.apache.hugegraph.backend.cache.Cache."
	taskMetricPrefix  = "org.apache.hugegraph.task.TaskManager."
)

var (
	allowedMethods = map[string]struct{}{
		"DELETE": {}, "GET": {}, "HEAD": {}, "OPTIONS": {},
		"PATCH": {}, "POST": {}, "PUT": {},
	}
	boundedLabelPattern = regexp.MustCompile(`^[A-Za-z0-9_./:{}-]{1,160}$`)
	transactionResults  = map[string]string{
		"commit-succeed": "succeed",
		"illegal-arg":    "illegal_arg",
		"expected-error": "expected_error",
		"unknown-error":  "unknown_error",
	}
)

type payload struct {
	Gauges     map[string]json.RawMessage
	Counters   map[string]json.RawMessage
	Histograms map[string]json.RawMessage
	Meters     map[string]json.RawMessage
	Timers     map[string]json.RawMessage
}

type parseError struct {
	stage string
}

func parsePayload(body []byte, maxRoutes, maxCaches int) ([]metricSample, *parseError) {
	var envelope map[string]json.RawMessage
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.UseNumber()
	if err := decoder.Decode(&envelope); err != nil {
		return nil, &parseError{stage: "decode"}
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return nil, &parseError{stage: "decode"}
	}

	required := []string{"gauges", "counters", "histograms", "meters", "timers"}
	for _, key := range required {
		if _, ok := envelope[key]; !ok {
			return nil, &parseError{stage: "schema"}
		}
	}

	parsed := payload{}
	if err := decodeMetricMap(envelope["gauges"], &parsed.Gauges); err != nil {
		return nil, &parseError{stage: "schema"}
	}
	if err := decodeMetricMap(envelope["counters"], &parsed.Counters); err != nil {
		return nil, &parseError{stage: "schema"}
	}
	if err := decodeMetricMap(envelope["histograms"], &parsed.Histograms); err != nil {
		return nil, &parseError{stage: "schema"}
	}
	if err := decodeMetricMap(envelope["meters"], &parsed.Meters); err != nil {
		return nil, &parseError{stage: "schema"}
	}
	if err := decodeMetricMap(envelope["timers"], &parsed.Timers); err != nil {
		return nil, &parseError{stage: "schema"}
	}

	return parsed.samples(maxRoutes, maxCaches)
}

func decodeMetricMap(raw json.RawMessage, target *map[string]json.RawMessage) error {
	if err := json.Unmarshal(raw, target); err != nil || *target == nil {
		return fmt.Errorf("invalid metric map")
	}
	return nil
}

func (payload payload) samples(maxRoutes, maxCaches int) ([]metricSample, *parseError) {
	var samples []metricSample
	routes := make(map[string]struct{})
	seenSeries := make(map[string]struct{})

	for _, key := range sortedKeys(payload.Counters) {
		route, method, result, matched := parseHTTPKey(key, map[string]string{
			"TOTAL_COUNTER":   "total",
			"SUCCESS_COUNTER": "success",
			"FAILED_COUNTER":  "failed",
		})
		if !matched || isMetricsRoute(route) {
			continue
		}
		if !boundedLabel(route) {
			return nil, &parseError{stage: "cardinality"}
		}
		routes[route] = struct{}{}
		if len(routes) > maxRoutes {
			return nil, &parseError{stage: "cardinality"}
		}
		value, ok := metricNumber(payload.Counters[key], "count", "value")
		if !ok || value < 0 {
			return nil, &parseError{stage: "schema"}
		}
		seriesKey := "http-counter\x00" + route + "\x00" + method + "\x00" + result
		if !addSeries(seenSeries, seriesKey) {
			return nil, &parseError{stage: "schema"}
		}
		samples = append(samples, metricSample{
			desc: httpRequestsDesc, valueType: prometheus.CounterValue,
			value: value, labels: []string{route, method, result},
		})
	}

	for _, key := range sortedKeys(payload.Histograms) {
		route, method, _, matched := parseHTTPKey(key, map[string]string{
			"RESPONSE_TIME_HISTOGRAM": "latency",
		})
		if !matched || isMetricsRoute(route) {
			continue
		}
		if !boundedLabel(route) {
			return nil, &parseError{stage: "cardinality"}
		}
		routes[route] = struct{}{}
		if len(routes) > maxRoutes {
			return nil, &parseError{stage: "cardinality"}
		}
		stats := []struct {
			name    string
			aliases []string
		}{
			{name: "mean", aliases: []string{"mean"}},
			{name: "p95", aliases: []string{"p95", "95thPercentile"}},
			{name: "p99", aliases: []string{"p99", "99thPercentile"}},
			{name: "max", aliases: []string{"max"}},
		}
		for _, stat := range stats {
			value, ok := metricNumber(payload.Histograms[key], stat.aliases...)
			if !ok || value < 0 {
				return nil, &parseError{stage: "schema"}
			}
			seriesKey := "http-latency\x00" + route + "\x00" + method + "\x00" + stat.name
			if !addSeries(seenSeries, seriesKey) {
				return nil, &parseError{stage: "schema"}
			}
			samples = append(samples, metricSample{
				desc: httpResponseTimeDesc, valueType: prometheus.GaugeValue,
				value: value, labels: []string{route, method, stat.name},
			})
		}
	}

	samples, err := payload.appendMeters(samples, seenSeries)
	if err != nil {
		return nil, err
	}
	samples, err = payload.appendGauges(samples, seenSeries, maxCaches)
	if err != nil {
		return nil, err
	}
	return samples, nil
}

func (payload payload) appendMeters(samples []metricSample, seenSeries map[string]struct{}) ([]metricSample, *parseError) {
	var gremlinErrors float64
	var hasGremlinErrors bool
	for _, key := range sortedKeys(payload.Meters) {
		value, ok := metricNumber(payload.Meters[key], "count", "value")
		if !ok || value < 0 {
			continue
		}
		for suffix, result := range transactionResults {
			if strings.HasSuffix(key, "."+suffix) {
				seriesKey := "transaction\x00" + result
				if !addSeries(seenSeries, seriesKey) {
					return nil, &parseError{stage: "schema"}
				}
				samples = append(samples, metricSample{
					desc: transactionCommitsDesc, valueType: prometheus.CounterValue,
					value: value, labels: []string{result},
				})
			}
		}
		lowerKey := strings.ToLower(key)
		if strings.Contains(lowerKey, "gremlin") && strings.HasSuffix(lowerKey, ".errors") {
			gremlinErrors += value
			hasGremlinErrors = true
		}
	}
	if hasGremlinErrors {
		samples = append(samples, metricSample{
			desc: gremlinErrorsDesc, valueType: prometheus.CounterValue,
			value: gremlinErrors,
		})
	}
	return samples, nil
}

func (payload payload) appendGauges(samples []metricSample, seenSeries map[string]struct{}, maxCaches int) ([]metricSample, *parseError) {
	caches := make(map[string]struct{})
	for _, key := range sortedKeys(payload.Gauges) {
		value, ok := metricNumber(payload.Gauges[key], "value", "count")
		if !ok || value < 0 {
			continue
		}
		switch key {
		case taskMetricPrefix + "pending-tasks":
			samples = append(samples, metricSample{
				desc: tasksPendingDesc, valueType: prometheus.GaugeValue,
				value: value, labels: []string{"task"},
			})
		case taskMetricPrefix + "workers":
			samples = append(samples, metricSample{
				desc: taskWorkersDesc, valueType: prometheus.GaugeValue,
				value: value, labels: []string{"task", "configured"},
			})
		}

		if !strings.HasPrefix(key, cacheMetricPrefix) {
			continue
		}
		identity, rawState, ok := splitCacheMetric(strings.TrimPrefix(key, cacheMetricPrefix))
		if !ok {
			continue
		}
		cache, graph, ok := splitCacheIdentity(identity)
		if !ok || !boundedLabel(cache) || !boundedLabel(graph) {
			return nil, &parseError{stage: "cardinality"}
		}
		cacheKey := graph + "\x00" + cache
		caches[cacheKey] = struct{}{}
		if len(caches) > maxCaches {
			return nil, &parseError{stage: "cardinality"}
		}

		switch rawState {
		case "hits", "miss", "expire":
			event := strings.TrimSuffix(rawState, "s")
			seriesKey := "cache-event\x00" + cacheKey + "\x00" + event
			if !addSeries(seenSeries, seriesKey) {
				return nil, &parseError{stage: "schema"}
			}
			samples = append(samples, metricSample{
				desc: cacheEventsDesc, valueType: prometheus.CounterValue,
				value: value, labels: []string{graph, cache, event},
			})
		case "size", "capacity":
			seriesKey := "cache-entry\x00" + cacheKey + "\x00" + rawState
			if !addSeries(seenSeries, seriesKey) {
				return nil, &parseError{stage: "schema"}
			}
			samples = append(samples, metricSample{
				desc: cacheEntriesDesc, valueType: prometheus.GaugeValue,
				value: value, labels: []string{graph, cache, rawState},
			})
		}
	}
	return samples, nil
}

func parseHTTPKey(key string, suffixes map[string]string) (string, string, string, bool) {
	parts := strings.Split(key, "/")
	if len(parts) < 3 {
		return "", "", "", false
	}
	result, ok := suffixes[parts[len(parts)-1]]
	if !ok {
		return "", "", "", false
	}
	method := strings.ToUpper(parts[len(parts)-2])
	if _, ok := allowedMethods[method]; !ok {
		return "", "", "", false
	}
	route := "/" + strings.TrimPrefix(strings.Join(parts[:len(parts)-2], "/"), "/")
	return route, method, result, true
}

func isMetricsRoute(route string) bool {
	return route == "/metrics" || strings.HasPrefix(route, "/metrics/")
}

func splitCacheMetric(metric string) (string, string, bool) {
	index := strings.LastIndexByte(metric, '.')
	if index <= 0 || index == len(metric)-1 {
		return "", "", false
	}
	return metric[:index], metric[index+1:], true
}

func splitCacheIdentity(identity string) (string, string, bool) {
	index := strings.IndexByte(identity, '-')
	if index <= 0 || index == len(identity)-1 {
		return "", "", false
	}
	return identity[:index], identity[index+1:], true
}

func metricNumber(raw json.RawMessage, fields ...string) (float64, bool) {
	var value any
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	if err := decoder.Decode(&value); err != nil {
		return 0, false
	}
	if number, ok := numericValue(value); ok {
		return number, true
	}
	object, ok := value.(map[string]any)
	if !ok {
		return 0, false
	}
	if number, ok := numberFromMap(object, fields...); ok {
		return number, true
	}
	for _, nestedKey := range []string{"snapshot", "value"} {
		if nested, ok := object[nestedKey].(map[string]any); ok {
			if number, ok := numberFromMap(nested, fields...); ok {
				return number, true
			}
		}
	}
	return 0, false
}

func numberFromMap(object map[string]any, fields ...string) (float64, bool) {
	for _, field := range fields {
		for key, value := range object {
			if strings.EqualFold(key, field) {
				return numericValue(value)
			}
		}
	}
	return 0, false
}

func numericValue(value any) (float64, bool) {
	var number float64
	switch typed := value.(type) {
	case json.Number:
		parsed, err := strconv.ParseFloat(string(typed), 64)
		if err != nil {
			return 0, false
		}
		number = parsed
	case float64:
		number = typed
	case int:
		number = float64(typed)
	default:
		return 0, false
	}
	return number, !math.IsNaN(number) && !math.IsInf(number, 0)
}

func boundedLabel(value string) bool {
	return boundedLabelPattern.MatchString(value)
}

func addSeries(seen map[string]struct{}, key string) bool {
	if _, ok := seen[key]; ok {
		return false
	}
	seen[key] = struct{}{}
	return true
}

func sortedKeys[V any](values map[string]V) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
