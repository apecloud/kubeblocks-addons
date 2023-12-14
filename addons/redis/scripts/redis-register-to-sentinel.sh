#!/bin/sh
set -ex

# Based on the Component Definition API, Redis deployed independently, this script is used to register Redis to Sentinel.

# usage: register_to_sentinel <sentinel_host> <master_name> <redis_primary_host> <redis_primary_port>
# redis sentinel configuration refer: https://redis.io/docs/management/sentinel/#configuring-sentinel
register_to_sentinel() {
  local sentinel_host=$1
  local master_name=$2
  local sentinel_port=${SENTINEL_SERVICE_PORT:-26379}
  local redis_primary_host=$3
  local redis_primary_port=$4
  local timeout=600
  local start_time=$(date +%s)
  local current_time

  # check sentinel host and redis primary host connectivity
  wait_for_connectivity() {
    local host=$1
    local port=$2
    local password=$3
    echo "Checking connectivity to $host on port $port using redis-cli..."
    while true; do
      current_time=$(date +%s)
      if [ $((current_time - start_time)) -gt $timeout ]; then
        echo "Timeout waiting for $host to become available."
        exit 1
      fi

      # Send PING and check for PONG response
      if redis-cli -h "$host" -p "$port" -a "$password" PING | grep -q "PONG"; then
        echo "$host is reachable on port $port."
        break
      fi

      sleep 5
    done
  }

  # function to execute and log redis-cli command
  execute_redis_cli() {
    echo "Executing: redis-cli -h $sentinel_host -p $sentinel_port -a $SENTINEL_PASSWORD $*"
    local output
    output=$(redis-cli -h "$sentinel_host" -p "$sentinel_port" -a "$SENTINEL_PASSWORD" "$@")
    local status=$?
    echo "$output" # Print command output

    if [ $status -ne 0 ] || [[ "$output" != "OK" ]]; then
      echo "Command failed with status $status or output not OK."
      exit 1
    else
      echo "Command executed successfully."
    fi
  }

  # Check connectivity to sentinel host
  wait_for_connectivity "$sentinel_host" "$sentinel_port" "$SENTINEL_PASSWORD"
  # Check connectivity to Redis primary host
  wait_for_connectivity "$redis_primary_host" "$redis_primary_port" "$REDIS_DEFAULT_PASSWORD"

  # Register and configure the Redis primary with Sentinel
  execute_redis_cli SENTINEL monitor "$master_name" "$redis_primary_host" "$redis_primary_port" 2
  execute_redis_cli SENTINEL set "$master_name" down-after-milliseconds 5000
  execute_redis_cli SENTINEL set "$master_name" failover-timeout 60000
  execute_redis_cli SENTINEL set "$master_name" parallel-syncs 1
  execute_redis_cli SENTINEL set "$master_name" auth-user "$REDIS_SENTINEL_USER"
  execute_redis_cli SENTINEL set "$master_name" auth-pass "$REDIS_SENTINEL_PASSWORD"

  echo "redis sentinel register to $sentinel_host succeeded!"
}

# TODO: replace the following code with built-in env and ComponentDefinition.Spec.Vars API
{{- $kb_cluster_comp_name := getEnvByName ( index $.podSpec.containers 0 ) "KB_CLUSTER_COMP_NAME" }}
{{- $redis_service_port := 6379 }}
{{- $redis_service_node_port := getEnvByName ( index $.podSpec.containers 0 ) "SERVICE_NODE_PORT" }}
{{- $redis_port := coalesce $redis_service_node_port $redis_service_port }}
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
{{- /* TODO: build redis primary host endpoint, use index=0 as default primary, which needs to be refactored */}}
{{- $redis_primary_host := printf "%s-0.%s-headless.%s.svc.%s" $kb_cluster_comp_name $kb_cluster_comp_name $namespace $.clusterDomain }}
{{- $redis_primary_port := printf "%d" $redis_port }}
register_to_sentinel {{ $sentinel_pod_fqdn }} {{ $kb_cluster_comp_name }} {{ $redis_primary_host }} {{ $redis_primary_port }}
{{- end }}



