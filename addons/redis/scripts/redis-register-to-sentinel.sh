#!/bin/bash
set -ex

# Based on the Component Definition API, Redis deployed independently, this script is used to register Redis to Sentinel.
# And the script will only be executed once during the initialization of the Redis cluster.

declare -g default_initialize_pod_ordinal
declare -g redis_announce_host_value
declare -g redis_announce_port_value
declare -g headless_postfix="headless"
declare -g redis_default_service_port=6379

init_redis_service_port() {
  if [ -n "$SERVICE_PORT" ]; then
    redis_default_service_port=$SERVICE_PORT
  fi
}

get_minimum_initialize_pod_ordinal() {
  if [ -z "$KB_POD_LIST" ]; then
    echo "KB_POD_LIST is empty, use default initialize pod_ordinal:0 as primary node."
    default_initialize_pod_ordinal=0
    return
  fi

  # parse minimum ordinal from env $KB_POD_LIST, the value format is "pod1,pod2,..."
  IFS=',' read -ra pod_list <<< "$KB_POD_LIST"
  for pod in "${pod_list[@]}"; do
    if [ -z "$default_initialize_pod_ordinal" ]; then
      default_initialize_pod_ordinal=$(extract_ordinal_from_object_name "$pod")
      continue
    fi
    pod_ordinal=$(extract_ordinal_from_object_name "$pod")
    if [ "$pod_ordinal" -lt "$default_initialize_pod_ordinal" ]; then
      default_initialize_pod_ordinal="$pod_ordinal"
    fi
  done
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

parse_redis_primary_announce_addr() {
  local pod_name="$1"
  local pod_fqdn="$2"

  # if redis primary is in host network mode, use the host ip and port as the announce ip and port first
  if [[ -n "${REDIS_HOST_NETWORK_PORT}" ]]; then
    redis_announce_port_value="$REDIS_HOST_NETWORK_PORT"
    # when in host network mode, the pod ip is the host ip
    pod_host_ip=$(get_default_primary_pod_ip "$pod_fqdn")
    redis_announce_host_value="$pod_host_ip"
    echo "redis is in host network mode, use the host ip:$pod_host_ip and port:$REDIS_HOST_NETWORK_PORT as the announce ip and port."
    return 0
  fi

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
      redis_announce_port_value="$port"
      # TODO: currently, kb doesn't support reference another component pod's HOST_IP, so we need to ensure the script is executed on the same node as the redis primary pod.
      redis_announce_host_value="$KB_HOST_IP"
      found=true
      break
    fi
  done

  if [[ "$found" == false ]]; then
    echo "Error: No matching svcName and port found for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. Exiting."
    exit 1
  fi
}

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

  set +x
  # Check connectivity to sentinel host
  wait_for_connectivity "$sentinel_host" "$sentinel_port" "$SENTINEL_PASSWORD"
  # Check connectivity to Redis primary host
  wait_for_connectivity "$redis_primary_host" "$redis_primary_port" "$REDIS_DEFAULT_PASSWORD"

  # Check if Sentinel is already monitoring the Redis primary
  master_addr=$(redis-cli -h "$sentinel_host" -p "$sentinel_port" -a "$SENTINEL_PASSWORD" SENTINEL get-master-addr-by-name "$master_name")

  if [ -z "$master_addr" ]; then
    echo "Sentinel is not monitoring $master_name. Registering it..."
    # Register the Redis primary with Sentinel
    execute_redis_cli SENTINEL monitor "$master_name" "$redis_primary_host" "$redis_primary_port" 2
  else
    echo "Sentinel is already monitoring $master_name at $master_addr. Skipping monitor registration."
  fi
  #configure the Redis primary with Sentinel
  execute_redis_cli SENTINEL set "$master_name" down-after-milliseconds 5000
  execute_redis_cli SENTINEL set "$master_name" failover-timeout 60000
  execute_redis_cli SENTINEL set "$master_name" parallel-syncs 1
  execute_redis_cli SENTINEL set "$master_name" auth-user "$REDIS_SENTINEL_USER"
  execute_redis_cli SENTINEL set "$master_name" auth-pass "$REDIS_SENTINEL_PASSWORD"
  set -x

  echo "redis sentinel register to $sentinel_host succeeded!"
}

# usage: get_default_primary_pod_ip <pod_fqdn>
get_default_primary_pod_ip() {
  local pod_fqdn="$1"
  local max_retries=30
  local retry_interval=2
  local retry_count=0
  local pod_ip=""

  while [ $retry_count -lt $max_retries ]; do
    pod_ip=$(getent hosts "$pod_fqdn" | awk '{ print $1 }')

    if [ -n "$pod_ip" ]; then
      echo "$pod_ip"
      return 0
    fi

    echo "Warning: Failed to resolve IP for $pod_fqdn, attempt $((retry_count + 1))/$max_retries" >&2
    retry_count=$((retry_count + 1))
    sleep $retry_interval
  done

  echo "Error: Failed to get IP address for $pod_fqdn after $max_retries attempts" >&2
  return 1
}

register_to_sentinel_wrapper() {
  # parse redis sentinel pod list from $SENTINEL_POD_NAME_LIST env
  if [ -z "$SENTINEL_POD_NAME_LIST" ]; then
    echo "Error: Required environment variable SENTINEL_POD_NAME_LIST: $SENTINEL_POD_NAME_LIST is not set."
    exit 1
  fi

  # get redis sentinel headless service name from $SENTINEL_HEADLESS_SERVICE_NAME env
  if [ -z "$SENTINEL_HEADLESS_SERVICE_NAME" ]; then
    echo "Error: Required environment variable SENTINEL_HEADLESS_SERVICE_NAME: $SENTINEL_HEADLESS_SERVICE_NAME is not set."
    exit 1
  fi

  # get minimum ordinal pod name as default primary node (the same logic as redis initialize primary node selection)
  get_minimum_initialize_pod_ordinal
  default_redis_primary_pod_name="$KB_CLUSTER_COMP_NAME-$default_initialize_pod_ordinal"
  redis_default_primary_pod_headless_fqdn="$default_redis_primary_pod_name.$KB_CLUSTER_COMP_NAME-$headless_postfix.$KB_NAMESPACE.svc.cluster.local"
  init_redis_service_port
  parse_redis_primary_announce_addr $default_redis_primary_pod_name $redis_default_primary_pod_headless_fqdn

  old_ifs="$IFS"
  IFS=','
  set -f
  read -ra sentinel_pod_list <<< "${SENTINEL_POD_NAME_LIST}"
  set +f
  IFS="$old_ifs"
  if [[ -z "$CUSTOM_SENTINEL_MASTER_NAME" ]]; then
    master_name=$KB_CLUSTER_COMP_NAME
  else
    master_name="$CUSTOM_SENTINEL_MASTER_NAME"
  fi
  for sentinel_pod in "${sentinel_pod_list[@]}"; do
    sentinel_pod_fqdn="$sentinel_pod.$SENTINEL_HEADLESS_SERVICE_NAME.$KB_NAMESPACE.svc.cluster.local"
    if [ -n "$redis_announce_host_value" ] && [ -n "$redis_announce_port_value" ]; then
      echo "register to sentinel:$sentinel_pod_fqdn with announce addr: redis_announce_host_value=$redis_announce_host_value, redis_announce_port_value=$redis_announce_port_value"
      register_to_sentinel "$sentinel_pod_fqdn" "$master_name" "$redis_announce_host_value" "$redis_announce_port_value"
    else
      if [ -n "$FIXED_POD_IP_ENABLED" ]; then
        default_primary_pod_ip=$(get_default_primary_pod_ip "$redis_default_primary_pod_headless_fqdn")
        echo "register to sentinel:$sentinel_pod_fqdn with fixed primary pod ip: fixed_pod_ip=$default_primary_pod_ip, redis_default_service_port=$redis_default_service_port"
        register_to_sentinel "$sentinel_pod_fqdn" "$master_name" "$default_primary_pod_ip" "$redis_default_service_port"
      else
        echo "register to sentinel:$sentinel_pod_fqdn with ClusterIP service: redis_default_primary_pod_fqdn=$redis_default_primary_pod_headless_fqdn, redis_default_service_port=$redis_default_service_port"
        register_to_sentinel "$sentinel_pod_fqdn" "$master_name" "$redis_default_primary_pod_headless_fqdn" "$redis_default_service_port"
      fi
    fi
  done
}

# shellcheck disable=SC1054,SC1073,SC1036,SC1056,SC1072
# TODO: replace the following code with checking env $SENTINEL_COMPONENT_NAME defined in ComponentDefinition.Spec.Vars API
{{- $defaultSentinelComponentName := "redis-sentinel" }}
{{- $envSentinelComponentName := getEnvByName ( index $.podSpec.containers 0 ) "SENTINEL_COMPONENT_DEFINITION_NAME" }}
{{- $sentinelComponentName := coalesce $envSentinelComponentName $defaultSentinelComponentName }}
{{- /* find redis sentinel component */}}
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
  register_to_sentinel_wrapper
{{- else }}
  echo "redis sentinel component replicas not found, skip register to sentinel."
  exit 0
{{- end }}

