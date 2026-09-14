#!/bin/bash

# shellcheck disable=SC2207

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
#
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -ex;
}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

redis_announce_host_value=""
redis_announce_port_value=""


extract_lb_host_by_svc_name() {
  local svc_name="$1"
  for lb_composed_name in $(echo "$REDIS_LB_ADVERTISED_HOST" | tr ',' '\n' ); do
    if [[ ${lb_composed_name} == *":"* ]]; then
       if [[ ${lb_composed_name%:*} == "$svc_name" ]]; then
         echo "${lb_composed_name#*:}"
         break
       fi
    else
       break
    fi
  done
}

# TODO: if instanceTemplate is specified, the pod service could not be parsed from the pod ordinal.
parse_redis_primary_announce_addr() {
  if is_empty "$REDIS_ADVERTISED_PORT"; then
     REDIS_ADVERTISED_PORT="$REDIS_LB_ADVERTISED_PORT"
  fi
  if is_empty "$REDIS_ADVERTISED_PORT"; then
    echo "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    return 0
  fi

  local pod_name="$1"
  local found=false
  pod_name_ordinal=$(extract_obj_ordinal "$pod_name")
  # the value format of REDIS_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  # shellcheck disable=SC2207
  advertised_ports=($(split "$REDIS_ADVERTISED_PORT" ","))
  for advertised_port in "${advertised_ports[@]}"; do
    # shellcheck disable=SC2207
    parts=($(split "$advertised_port" ":"))
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_obj_ordinal "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      redis_announce_port_value="$port"
      # TODO: get the host ip from env defined in the action context.
      lb_host=$(extract_lb_host_by_svc_name "$svc_name")
      if [ -n "$lb_host" ]; then
        echo "Found load balancer host for svcName '$svc_name', value is '$lb_host'."
        redis_announce_host_value="$lb_host"
        redis_announce_port_value="6379"
      else
        redis_announce_host_value="$CURRENT_POD_HOST_IP"
      fi
      found=true
      break
    fi
  done

  if equals "$found" false; then
    echo "Error: No matching svcName and port found for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. Exiting." >&2
    exit 1
  fi
}

# Register the master to the local sentinel with dynamic commands.
# Sentinel does not reload the configuration file at runtime and CONFIG REWRITE
# would overwrite manual file changes, so the master must be registered via
# SENTINEL MONITOR/SET commands which take effect immediately.
register_master_to_sentinel() {
  local master_name="$1"
  local master_ip="$2"
  local master_port="$3"
  local master_quorum="$4"
  local master_down_after_milliseconds="$5"
  local master_failover_timeout="$6"
  local master_parallel_syncs="$7"

  local redis_cli_cmd="redis-cli $REDIS_CLI_TLS_CMD -h $KB_JOIN_MEMBER_POD_FQDN -p ${SENTINEL_SERVICE_PORT:-26379}"
  if ! is_empty "$SENTINEL_PASSWORD"; then
    redis_cli_cmd="$redis_cli_cmd -a $SENTINEL_PASSWORD"
  fi

  unset_xtrace_when_ut_mode_false
  local master_addr
  master_addr=$($redis_cli_cmd SENTINEL get-master-addr-by-name "$master_name" 2>/dev/null)
  if is_empty "$master_addr"; then
    if ! $redis_cli_cmd SENTINEL MONITOR "$master_name" "$master_ip" "$master_port" "$master_quorum"; then
      echo "failed to register master $master_name to local sentinel" >&2
      return 1
    fi
  else
    echo "master $master_name is already monitored, skip SENTINEL MONITOR"
  fi
  $redis_cli_cmd SENTINEL SET "$master_name" down-after-milliseconds "$master_down_after_milliseconds" || return 1
  $redis_cli_cmd SENTINEL SET "$master_name" failover-timeout "$master_failover_timeout" || return 1
  $redis_cli_cmd SENTINEL SET "$master_name" parallel-syncs "$master_parallel_syncs" || return 1
  if [[ "$SERVICE_VERSION" != 5.* ]]; then
    $redis_cli_cmd SENTINEL SET "$master_name" auth-user "$REDIS_SENTINEL_USER" || return 1
  fi
  if ! is_empty "$REDIS_SENTINEL_PASSWORD"; then
    $redis_cli_cmd SENTINEL SET "$master_name" auth-pass "$REDIS_SENTINEL_PASSWORD" || return 1
  fi
  set_xtrace_when_ut_mode_false
  echo "register master $master_name to local sentinel succeeded!"
}

recover_registered_redis_servers() {
  # check required environment variables, we use REDIS_COMPONENT_NAME as the master name registered to sentinel
  if is_empty "$REDIS_COMPONENT_NAME" || is_empty "$REDIS_POD_NAME_LIST" || is_empty "$REDIS_POD_FQDN_LIST"; then
    echo "Error: Required environment variable REDIS_COMPONENT_NAME, REDIS_POD_NAME_LIST and REDIS_POD_FQDN_LIST is not set." >&2
    return 1
  fi

  # get minimum lexicographical order pod name as default primary node (the same logic as redis-register-to-sentinel.sh)
  local redis_default_primary_pod_name
  redis_default_primary_pod_name=$(min_lexicographical_order_pod "$REDIS_POD_NAME_LIST")
  local redis_default_primary_pod_fqdn
  redis_default_primary_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$REDIS_POD_FQDN_LIST" "$redis_default_primary_pod_name")
  if is_empty "$redis_default_primary_pod_fqdn"; then
    echo "Error: Failed to get the default primary pod fqdn from redis pod fqdn list: $REDIS_POD_FQDN_LIST." >&2
    return 1
  fi

  parse_redis_primary_announce_addr "$redis_default_primary_pod_name"

  local master_name
  if is_empty "$CUSTOM_SENTINEL_MASTER_NAME"; then
    master_name=$REDIS_COMPONENT_NAME
  else
    master_name="$CUSTOM_SENTINEL_MASTER_NAME"
  fi

  local master_ip="$redis_default_primary_pod_fqdn"
  local master_port="${SERVICE_PORT:-6379}"
  if ! is_empty "$redis_announce_host_value" && ! is_empty "$redis_announce_port_value"; then
    master_ip="$redis_announce_host_value"
    master_port="$redis_announce_port_value"
  fi

  if ! register_master_to_sentinel "$master_name" "$master_ip" "$master_port" "2" "20000" "60000" "1"; then
    echo "register master $master_name failed" >&2
    return 1
  fi
}


recover_registered_redis_servers_if_needed() {
  echo "horizontal scaling"
  if ! recover_registered_redis_servers; then
    echo "recover_registered_redis_servers failed"
    exit 1
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library

recover_registered_redis_servers_if_needed