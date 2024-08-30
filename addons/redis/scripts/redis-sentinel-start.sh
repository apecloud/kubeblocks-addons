#!/bin/sh
set -ex

# Based on the ClusterDefinition API, redis sentinel deployed with redis together, it will be deprecated in the future.

{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- /* find redis component */}}
{{- $redis_component := fromJson "{}" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if index $e "componentDefRef" }}
    {{- if eq $e.componentDefRef "redis-7" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDefRef "redis-5" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDefRef "redis" }}
      {{- $redis_component = $e }}
    {{- end }}
  {{- end }}
  {{- if index $e "componentDef" }}
    {{- if eq $e.componentDef "redis-7" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDef "redis-5" }}
      {{- $redis_component = $e }}
    {{- else if eq $e.componentDef "redis" }}
      {{- $redis_component = $e }}
    {{- end }}
  {{- end }}
{{- end }}
{{- /* build redis engine service */}}
{{- $primary_svc := printf "%s-%s.%s.svc" $clusterName $redis_component.name $namespace }}
echo "Waiting for redis service {{ $primary_svc }} to be ready..."
set +x
if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
  timeout 300 sh -c 'until redis-cli -h {{ $primary_svc }} -p 6379 -a $REDIS_DEFAULT_PASSWORD ping; do sleep 2; done'
else
  timeout 300 sh -c 'until redis-cli -h {{ $primary_svc }} -p 6379 ping; do sleep 1; done'
fi
if [ $? -ne 0 ]; then
  echo "Redis service is not ready, exiting..."
  exit 1
fi
set -x
echo "Redis service ready, Starting sentinel..."
kb_pod_fqdn="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
echo "sentinel announce-ip $kb_pod_fqdn" >> /etc/sentinel/redis-sentinel.conf
exec redis-server /etc/sentinel/redis-sentinel.conf --sentinel
echo "Start sentinel succeeded!"