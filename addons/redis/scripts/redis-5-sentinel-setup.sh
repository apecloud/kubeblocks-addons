#!/bin/sh
set -e

# Based on the ClusterDefinition API, redis sentinel deployed with redis together, it will be deprecated in the future.

# shellcheck disable=SC1054
{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- /* find redis-sentinel component */}}
{{- $sentinel_component := fromJson "{}" }}
{{- $redis_component := fromJson "{}" }}
{{- $candidate_instance_index := 0 }}
{{- $primary_pod := "" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if index $e "componentDefRef" }}
    {{- /* xxxx-7 suffix just for compatible config render do not panic, this script has been deprecated in KubeBlock v0.10 */}}
    {{- if eq $e.componentDefRef "redis-sentinel-7" }}
      {{- $sentinel_component = $e }}
    {{- else if eq $e.componentDefRef "redis-sentinel-5" }}
      {{- $sentinel_component = $e }}
    {{- else if eq $e.componentDefRef "redis-sentinel" }}
      {{- $sentinel_component = $e }}
    {{- else if eq $e.componentDefRef "redis-7" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDefRef "redis-5" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDefRef "redis" }}
      {{- $redis_component = $e }}
    {{- end }}
  {{- end }}
  {{- if index $e "componentDef" }}
    {{- if eq $e.componentDef "redis-sentinel-7" }}
      {{- $sentinel_component = $e }}
    {{- else if eq $e.componentDef "redis-sentinel-5" }}
      {{- $sentinel_component = $e }}
    {{- else if eq $e.componentDef "redis-sentinel" }}
      {{- $sentinel_component = $e }}
    {{- else if eq $e.componentDef "redis-7" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDef "redis-5" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDef "redis" }}
      {{- $redis_component = $e }}
    {{- end }}
  {{- end }}
{{- end }}
{{- /* build primary pod message, because currently does not support cross-component acquisition of environment variables, the service of the redis master node is assembled here through specific rules  */}}
{{- $primary_pod = printf "%s-%s-%d.%s-%s-headless.%s.svc" $clusterName $redis_component.name $candidate_instance_index $clusterName $redis_component.name $namespace }}
{{- $sentinel_monitor := printf "%s-%s %s" $clusterName $redis_component.name $primary_pod }}
{{- /* build sentinel config */}}
echo "port 26379" > /etc/sentinel/redis-sentinel.conf
echo "sentinel monitor {{ $sentinel_monitor }} 6379 2" >> /etc/sentinel/redis-sentinel.conf
echo "sentinel down-after-milliseconds {{ $clusterName }}-{{ $redis_component.name }} 5000" >> /etc/sentinel/redis-sentinel.conf
echo "sentinel failover-timeout {{ $clusterName }}-{{ $redis_component.name }} 60000" >> /etc/sentinel/redis-sentinel.conf
echo "sentinel parallel-syncs {{ $clusterName }}-{{ $redis_component.name }} 1" >> /etc/sentinel/redis-sentinel.conf
if [ ! -z "$REDIS_SENTINEL_PASSWORD" ]; then
  echo "sentinel auth-pass {{ $clusterName }}-{{ $redis_component.name }} $REDIS_SENTINEL_PASSWORD" >> /etc/sentinel/redis-sentinel.conf
fi
if [ ! -z "$SENTINEL_PASSWORD" ]; then
  echo "sentinel requirepass $SENTINEL_PASSWORD" >> /etc/sentinel/redis-sentinel.conf
fi
{{- /* $primary_svc := printf "%s-%s.%s.svc" $clusterName $redis_component.name $namespace */}}