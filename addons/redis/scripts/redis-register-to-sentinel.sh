#!/bin/bash
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

    if [ $status -ne 0 ] || [ "$output" != "OK" ]; then
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

# usage: parse_host_ip_from_built_in_envs <pod_name>
# $KB_CLUSTER_COMPONENT_POD_NAME_LIST and $KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are built-in envs in KubeBlocks postProvision lifecycle action.
parse_host_ip_from_built_in_envs() {
  local given_pod_name="$1"

  if [ -z "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" ] || [ -z "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST" ]; then
    echo "Error: Required environment variables KB_CLUSTER_COMPONENT_POD_NAME_LIST or KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are not set."
    exit 1
  fi

  old_ifs="$IFS"
  IFS=','
  set -f
  pod_name_list="$KB_CLUSTER_COMPONENT_POD_NAME_LIST"
  pod_ip_list="$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST"
  set +f
  IFS="$old_ifs"

  while [ -n "$pod_name_list" ]; do
    pod_name="${pod_name_list%%,*}"
    host_ip="${pod_ip_list%%,*}"

    if [ "$pod_name" = "$given_pod_name" ]; then
      echo "$host_ip"
      return 0
    fi

    if [ "$pod_name_list" = "$pod_name" ]; then
      pod_name_list=''
      pod_ip_list=''
    else
      pod_name_list="${pod_name_list#*,}"
      pod_ip_list="${pod_ip_list#*,}"
    fi
  done

  echo "parse_host_ip_from_built_in_envs the given pod name $given_pod_name not found."
  exit 1
}

extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

parse_redis_advertised_svc_if_exist() {
  local pod_name="$1"

  if [[ -z "${REDIS_ADVERTISED_PORT}" ]]; then
    echo "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    return 0
  fi

  # the value format of REDIS_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  IFS=',' read -ra advertised_ports <<< "${REDIS_ADVERTISED_PORT}"

  local found=false
  pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
  for advertised_port in "${advertised_ports[@]}"; do
    IFS=':' read -ra parts <<< "$advertised_port"
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_ordinal_from_object_name "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      redis_advertised_svc_port_value="$port"
      redis_advertised_svc_host_value="$KB_HOST_IP"
      found=true
      break
    fi
  done

  if [[ "$found" == false ]]; then
    echo "Error: No matching svcName and port found for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. Exiting."
    exit 1
  fi
}

# TODO: replace the following code with built-in env and ComponentDefinition.Spec.Vars API
# TODO: build redis primary host endpoint, use index=0 as default primary, which needs to be refactored
{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $kb_cluster_comp_name := getEnvByName ( index $.podSpec.containers 0 ) "KB_CLUSTER_COMP_NAME" }}

# use the first pod as the default primary
redis_pod_index_0="{{ $kb_cluster_comp_name }}-0"
parse_redis_advertised_svc_if_exist $redis_pod_index_0

{{- $redis_default_primary_host := printf "%s-0.%s-headless.%s.svc.%s" $kb_cluster_comp_name $kb_cluster_comp_name $namespace $.clusterDomain }}
{{- $redis_default_service_port := printf "%d" 6379 }}
{{- $defaultSentinelComponentName := "redis-sentinel" }}
{{- $envSentinelComponentName := getEnvByName ( index $.podSpec.containers 0 ) "SENTINEL_COMPONENT_DEFINITION_NAME" }}
{{- $sentinelComponentName := coalesce $envSentinelComponentName $defaultSentinelComponentName }}
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

{{- if index $redis_sentinel_component_spec "replicas" }}
  echo "redis sentinel component replicas found, register to sentinel."
  {{- $redis_sentinel_replicas := $redis_sentinel_component_spec.replicas | int }}
  {{- $servers := "" }}
  {{- range $i, $e := until $redis_sentinel_replicas }}
  {{- $sentinel_pod_fqdn := printf "%s-%s-%d.%s-%s-headless.%s.svc.%s" $clusterName $redis_sentinel_component_spec.name $i $clusterName $redis_sentinel_component_spec.name $namespace $.clusterDomain }}
  {{- /* TODO: build redis primary host endpoint, use index=0 as default primary, which needs to be refactored */}}

  if [ -n "$redis_advertised_svc_host_value" ] && [ -n "$redis_advertised_svc_port_value" ]; then
    echo "register to sentinel with NodePort service: redis_advertised_svc_host_value=$redis_advertised_svc_host_value, redis_advertised_svc_port_value=$redis_advertised_svc_port_value"
    register_to_sentinel {{ $sentinel_pod_fqdn }} {{ $kb_cluster_comp_name }} $redis_advertised_svc_host_value $redis_advertised_svc_port_value
  else
    echo "register to sentinel with ClusterIP service: redis_default_primary_host=$redis_default_primary_host, redis_default_service_port=$redis_default_service_port"
    register_to_sentinel {{ $sentinel_pod_fqdn }} {{ $kb_cluster_comp_name }} {{ $redis_default_primary_host }} {{ $redis_default_service_port }}
  fi

  {{- end }}
{{- else }}
  echo "redis sentinel component replicas not found, skip register to sentinel."
  exit 0
{{- end }}

