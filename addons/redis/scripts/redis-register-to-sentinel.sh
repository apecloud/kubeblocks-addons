#!/bin/sh
set -ex

# Based on the Component Definition API, Redis deployed independently, this script is used to register Redis to Sentinel.

# usage: register_to_sentinel <sentinel_host> <master_name> <redis_primary_host> <redis_primary_port>
# redis sentinel configuration refer: https://redis.io/docs/management/sentinel/#configuring-sentinel
register_to_sentinel() {
  local sentinel_host=$1
  local master_name=$2
  local sentinel_port=26379

  local redis_primary_host=$3
  local redis_primary_port=$4

  if [ ! -z "$SENTINEL_SERVICE_PORT" ]; then
    sentinel_port=$SENTINEL_SERVICE_PORT
  fi

  redis-cli -h $sentinel_host -p $sentinel_port -a $SENTINEL_PASSWORD SENTINEL monitor $master_name $redis_primary_host $redis_primary_port 2
  redis-cli -h $sentinel_host -p $sentinel_port -a $SENTINEL_PASSWORD SENTINEL set $master_name down-after-milliseconds 5000
  redis-cli -h $sentinel_host -p $sentinel_port -a $SENTINEL_PASSWORD SENTINEL set $master_name failover-timeout 60000
  redis-cli -h $sentinel_host -p $sentinel_port -a $SENTINEL_PASSWORD SENTINEL set $master_name parallel-syncs 60000
  redis-cli -h $sentinel_host -p $sentinel_port -a $SENTINEL_PASSWORD SENTINEL set $master_name auth-user $REDIS_SENTINEL_USER 60000
  redis-cli -h $sentinel_host -p $sentinel_port -a $SENTINEL_PASSWORD SENTINEL set $master_name auth-pass $REDIS_SENTINEL_PASSWORD 60000

  if [ $? -eq 0 ]; then
    echo "redis $redis_primary_host register to sentinel $sentinel_host successfully."
  else
    echo "redis $redis_primary_host register to sentinel $sentinel_host failed."
    exit 1
  fi
}

# TODO: replace the following code with built-in env and ComponentDefinition.Spec.Vars API
{{- $kb_cluster_comp_name := getEnvByName ( index $.podSpec.containers 0 ) "KB_CLUSTER_COMP_NAME" }}
{{- $redis_service_port := getEnvByName ( index $.podSpec.containers 0 ) "SERVICE_PORT" }}
{{- $defaultSentinelComponentName := "redis-sentinel" }}
{{- $envSentinelComponentName := getEnvByName ( index $.podSpec.containers 0 ) "SENTINEL_COMPONENT_DEFINITION_NAME" }}
{{- $sentinelComponentName := coalesce $envSentinelComponentName $defaultSentinelComponentName }}
{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- /* find redis component */}}
{{- $redis_sentinel_component_spec := fromJson "{}" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if index $e "componentDefRef" }}
    {{- if eq $e.componentDefRef $sentinelComponentName }}
      {{- $redis_sentinel_component_spec = $e }}
    {{- end }}
  {{- end }}
  {{- if index $e "componentDef" }}
    {{- if eq $e.componentDef $sentinelComponentName }}
      {{- $redis_sentinel_component_spec = $e }}
    {{- end }}
  {{- end }}
{{- end }}
{{- $redis_sentinel_replicas := $redis_sentinel_component_spec.replicas | int }}
{{- $servers := "" }}
{{- range $i, $e := until $redis_sentinel_replicas }}
  {{- $sentinel_pod_fqdn := printf "%s-%s-%d.%s-%s-headless.%s.svc.%s" $clusterName $redis_sentinel_component_spec.name $i $clusterName $redis_sentinel_component_spec.name $namespace $.clusterDomain }}
  {{- $redis_primary_host := printf "%s-0" $kb_cluster_comp_name }}
  {{- $redis_primary_port := printf "%s" $redis_service_port }}
  register_to_sentinel $sentinel_pod_fqdn $kb_cluster_comp_name  $redis_primary_host $redis_primary_port
{{- end }}



