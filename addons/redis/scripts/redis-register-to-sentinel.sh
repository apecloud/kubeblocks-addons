#!/bin/bash

# Based on the Component Definition API, Redis deployed independently, this script is used to register Redis to Sentinel.
# And the script will only be executed once during the initialization of the Redis cluster.

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
# you should set ut_mode="true" when you want to run the script in shellspec file.
ut_mode="false"
test || __() {
  set -ex;
}

redis_advertised_svc_host_value=""
redis_advertised_svc_port_value=""
headless_postfix="headless"
redis_default_service_port=6379

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

init_redis_service_port() {
  if [ -n "$SERVICE_PORT" ]; then
    redis_default_service_port=$SERVICE_PORT
  fi
}

# usage: parse_host_ip_from_built_in_envs <pod_name>
# $KB_CLUSTER_COMPONENT_POD_NAME_LIST and $KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are built-in envs in KubeBlocks postProvision lifecycle action.
parse_host_ip_from_built_in_envs() {
  local given_pod_name="$1"

  if ! env_exists KB_CLUSTER_COMPONENT_POD_NAME_LIST KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST; then
    echo "Error: Required environment variables KB_CLUSTER_COMPONENT_POD_NAME_LIST or KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are not set."
    exit 1
  fi

  pod_name_list=($(split "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" ","))
  pod_ip_list=($(split "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST" ","))
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

# TODO: if instanceTemplate is specified, the pod service could not be parsed from the pod ordinal.
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

  # Register and configure the Redis primary with Sentinel
  execute_redis_cli SENTINEL monitor "$master_name" "$redis_primary_host" "$redis_primary_port" 2
  execute_redis_cli SENTINEL set "$master_name" down-after-milliseconds 5000
  execute_redis_cli SENTINEL set "$master_name" failover-timeout 60000
  execute_redis_cli SENTINEL set "$master_name" parallel-syncs 1
  execute_redis_cli SENTINEL set "$master_name" auth-user "$REDIS_SENTINEL_USER"
  execute_redis_cli SENTINEL set "$master_name" auth-pass "$REDIS_SENTINEL_PASSWORD"
  set -x

  echo "redis sentinel register to $sentinel_host succeeded!"
}

register_to_sentinel_wrapper() {
  # check required environment variables, we use KB_CLUSTER_COMP_NAME as the master_name registered to sentinel
  if  ! env_exists KB_CLUSTER_COMP_NAME KB_POD_LIST; then
    echo "Error: Required environment variable KB_CLUSTER_COMP_NAME and KB_POD_LIST is not set."
    exit 1
  fi

  # parse redis sentinel pod fqdn list from $SENTINEL_POD_FQDN_LIST env
  if ! env_exist SENTINEL_POD_FQDN_LIST; then
    echo "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set."
    exit 1
  fi

  # get minimum lexicographical order pod name as default primary node (the same logic as redis initialize primary node selection)
  default_redis_primary_pod_name=$(min_lexicographical_order_pod "$KB_POD_LIST")
  redis_default_primary_pod_headless_fqdn="$default_redis_primary_pod_name.$KB_CLUSTER_COMP_NAME-$headless_postfix.$KB_NAMESPACE.svc"
  init_redis_service_port
  parse_redis_advertised_svc_if_exist $default_redis_primary_pod_name

  sentinel_pod_fqdn_list=($(split "$SENTINEL_POD_FQDN_LIST" ","))
  for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
    if [ -n "$redis_advertised_svc_host_value" ] && [ -n "$redis_advertised_svc_port_value" ]; then
      echo "register to sentinel:$sentinel_pod_fqdn with advertised service: redis_advertised_svc_host_value=$redis_advertised_svc_host_value, redis_advertised_svc_port_value=$redis_advertised_svc_port_value"
      register_to_sentinel "$sentinel_pod_fqdn" "$KB_CLUSTER_COMP_NAME" "$redis_advertised_svc_host_value" "$redis_advertised_svc_port_value"
    else
      echo "register to sentinel:$sentinel_pod_fqdn with ClusterIP service: redis_default_primary_pod_fqdn=$redis_default_primary_pod_headless_fqdn, redis_default_service_port=$redis_default_service_port"
      register_to_sentinel "$sentinel_pod_fqdn" "$KB_CLUSTER_COMP_NAME" "$redis_default_primary_pod_headless_fqdn" "$redis_default_service_port"
    fi
  done
}

# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library

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

