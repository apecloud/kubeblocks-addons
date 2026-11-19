#!/bin/bash

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
#
# you should set ut_mode="true" when you want to run the script in shellspec file.
#
# shellcheck disable=SC2034
# shellcheck disable=SC2153
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

declare -A ORIGINAL_PRIORITIES
declare -A ANNOUNCE_TUPLE_OWNERS
ANNOUNCE_IDENTITY_ERROR=""
redis_service_port=${SERVICE_PORT:-6379}
readonly redis_cli_timeout_seconds=5
readonly switchover_action_timeout_seconds=420
readonly switchover_cleanup_grace_seconds=60
readonly sentinel_priority_wait_seconds=30
readonly priority_recovery_attempts=2
readonly priority_recovery_retry_interval_seconds=1
priorities_mutated=false

normalize_fqdn() {
  local fqdn="${1%.}"
  printf '%s\n' "${fqdn,,}"
}

same_fqdn() {
  [[ "$(normalize_fqdn "$1")" == "$(normalize_fqdn "$2")" ]]
}

fqdn_in_csv() {
  local target_fqdn="$1"
  local csv="$2"
  local -a fqdns
  local fqdn
  IFS=',' read -ra fqdns <<< "$csv"
  for fqdn in "${fqdns[@]}"; do
    same_fqdn "$fqdn" "$target_fqdn" && return 0
  done
  return 1
}

run_redis_cli() {
  local -a tls_args=()
  if [[ -n "${REDIS_CLI_TLS_CMD:-}" ]]; then
    read -ra tls_args <<< "$REDIS_CLI_TLS_CMD"
  fi
  if [[ "$ut_mode" == "true" ]]; then
    redis-cli "${tls_args[@]}" "$@"
  else
    timeout -k 2 "$redis_cli_timeout_seconds" redis-cli "${tls_args[@]}" "$@"
  fi
}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

check_environment_exist() {
  local required_vars=(
    "SENTINEL_POD_FQDN_LIST"
    "REDIS_POD_FQDN_LIST"
    "REDIS_COMPONENT_NAME"
  )

  if [[ ${COMPONENT_REPLICAS} -lt 2 ]]; then
    exit 0
  fi

  for var in "${required_vars[@]}"; do
    if is_empty "${!var}"; then
      echo "Error: Required environment variable $var is not set." >&2
      return 1
    fi
  done

  if [ "$KB_SWITCHOVER_ROLE" != "primary" ]; then
    echo "switchover not triggered for primary, nothing to do, exit 0."
    exit 0
  fi
}

check_redis_role() {
  local host=$1
  local port=$2
  unset_xtrace_when_ut_mode_false
  local role_info
  if [[ -z "$REDIS_DEFAULT_PASSWORD" ]]; then
    role_info=$(run_redis_cli -h "$host" -p "$port" info replication)
  else
    role_info=$(run_redis_cli -h "$host" -p "$port" -a "$REDIS_DEFAULT_PASSWORD" info replication)
  fi
  status=$?
  set_xtrace_when_ut_mode_false

  if [[ $status -ne 0 ]]; then
    echo "Failed to get role info from $host" >&2
    return 1
  fi

  if echo "$role_info" | grep -q "^role:master"; then
    echo "primary"
  elif echo "$role_info" | grep -q "^role:slave"; then
    echo "secondary"
  else
    echo "unknown"
    return 1
  fi
}

check_redis_kernel_status() {
  local role
  local current_master=""
  local -a redis_pod_fqdn_list
  IFS=',' read -ra redis_pod_fqdn_list <<< "${REDIS_POD_FQDN_LIST}"
  for redis_pod_fqdn in "${redis_pod_fqdn_list[@]}"; do
    role=$(check_redis_role "$redis_pod_fqdn" "$redis_service_port") || continue
    if [[ "$role" == "primary" ]]; then
      if [[ -n "$current_master" ]]; then
        echo "Error: Multiple primaries detected" >&2
        return 1
      fi
      current_master="$redis_pod_fqdn"
    fi
  done

  if [[ -z "$current_master" ]]; then
    echo "Error: No primary found" >&2
    return 1
  fi

  echo "$current_master"
  return 0
}

check_switchover_result() {
  local expected_master="$1"
  local initial_master="$2"
  local max_wait=300
  local wait_interval=5
  local deadline=$((SECONDS + max_wait))

  while [[ $SECONDS -lt $deadline ]]; do
    local current_master
    if current_master=$(check_redis_kernel_status); then
      # if expected_master is specified, check if it is achieved
      if ! is_empty "$expected_master"; then
        if same_fqdn "$current_master" "$expected_master"; then
          echo "Switchover successful: $expected_master is now master"
          return 0
        fi
      # if initial_master is specified, check if it is switched to a different node
      elif ! is_empty "$initial_master"; then
        if [[ "$current_master" != "$initial_master" ]]; then
          echo "Switchover successful: new master is $current_master"
          return 0
        fi
      else
        echo "Error: Neither expected_master nor initial_master specified" >&2
        return 1
      fi
    fi
    sleep_when_ut_mode_false $wait_interval
  done

  if ! is_empty "$expected_master"; then
    echo "Switchover verification failed: expected master $expected_master not achieved" >&2
  else
    echo "Switchover verification failed: could not confirm new master" >&2
  fi
  return 1
}

check_connectivity() {
  local host=$1
  local port=$2
  local password=$3
  echo "Checking connectivity to $host on port $port using redis-cli..."
  local result
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$password"; then
    result=$(run_redis_cli -h "$host" -p "$port" -a "$password" PING)
  else
    result=$(run_redis_cli -h "$host" -p "$port" PING)
  fi
  set_xtrace_when_ut_mode_false
  if [[ "$result" == "PONG" ]]; then
    echo "$host is reachable on port $port."
    return 0
  else
    echo "$host is not reachable on port $port." >&2
    return 1
  fi
}

execute_sub_command() {
  local host=$1
  local port=$2
  local password=$3
  local command=$4
  local -a command_args
  read -ra command_args <<< "$command"

  local output
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$password"; then
    output=$(run_redis_cli -h "$host" -p "$port" -a "$password" "${command_args[@]}")
  else
    output=$(run_redis_cli -h "$host" -p "$port" "${command_args[@]}")
  fi
  local status=$?
  set_xtrace_when_ut_mode_false

  echo "execute_sub_command output: $output"
  if [[ $status -ne 0 ]] || [[ "$output" != "OK" ]]; then
    echo "Command failed with status $status or output not OK." >&2
    return 1
  fi
  echo "Command executed successfully."
  return 0
}

redis_config_get() {
  local host=$1
  local port=$2
  local password=$3
  local command=$4
  local -a command_args
  read -ra command_args <<< "$command"

  local output
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$password"; then
    output=$(run_redis_cli -h "$host" -p "$port" -a "$password" "${command_args[@]}")
  else
    output=$(run_redis_cli -h "$host" -p "$port" "${command_args[@]}")
  fi
  local status=$?
  set_xtrace_when_ut_mode_false

  if [[ $status -ne 0 ]]; then
    echo "Command failed with status $status." >&2
    return 1
  fi

  if [[ -z "$output" ]]; then
    echo "Command returned no output." >&2
    return 1
  fi

  echo "$output"
  return 0
}

resolve_host_addresses() {
  local host="$1"
  command -v getent >/dev/null 2>&1 || return 0
  if [[ "$ut_mode" == "true" ]]; then
    getent hosts "$host"
  else
    timeout -k 2 "$redis_cli_timeout_seconds" getent hosts "$host"
  fi
}

execute_sentinel_failover() {
  local master_name=$1
  local success=false

  if [[ -z "$master_name" ]]; then
    master_name=$REDIS_COMPONENT_NAME
  fi

  local -a sentinel_pod_fqdn_list
  IFS=',' read -ra sentinel_pod_fqdn_list <<< "${SENTINEL_POD_FQDN_LIST}"
  unset_xtrace_when_ut_mode_false
  for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
    if call_func_with_retry 3 5 execute_sub_command "$sentinel_pod_fqdn" "$SENTINEL_SERVICE_PORT" "$SENTINEL_PASSWORD" "SENTINEL FAILOVER $master_name"; then
      echo "Sentinel failover started with $sentinel_pod_fqdn"
      success=true
      break
    fi
  done
  set_xtrace_when_ut_mode_false

  if [[ "$success" == false ]]; then
    echo "All Sentinel failover attempts failed." >&2
    return 1
  fi
  return 0
}

redis_replica_announce_address() {
  local replica_fqdn="$1"
  local output
  local announce_host
  local announce_hosts
  local announce_port

  if ! output=$(redis_config_get \
    "$replica_fqdn" "$redis_service_port" "$REDIS_DEFAULT_PASSWORD" \
    "CONFIG GET replica-announce-*"); then
    echo "Error: Failed to get replica announce address for $replica_fqdn" >&2
    return 1
  fi

  announce_host=$(printf '%s\n' "$output" | awk '
    previous == "replica-announce-ip" { print; exit }
    { previous = $0 }
  ')
  announce_port=$(printf '%s\n' "$output" | awk '
    previous == "replica-announce-port" { print; exit }
    { previous = $0 }
  ')

  if [[ -z "$announce_host" ]]; then
    echo "Error: Empty replica-announce-ip for $replica_fqdn" >&2
    return 1
  fi
  if [[ ! "$announce_port" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid replica-announce-port for $replica_fqdn: $announce_port" >&2
    return 1
  fi
  if [[ "$announce_port" == "0" ]]; then
    announce_port="$redis_service_port"
  fi

  announce_hosts=$(normalize_fqdn "$announce_host")
  local resolution_output
  resolution_output=$(resolve_host_addresses "$announce_host" 2>/dev/null) || true
  local resolved_host
  while read -r resolved_host _; do
    [[ -n "$resolved_host" ]] || continue
    if ! fqdn_in_csv "$resolved_host" "$announce_hosts"; then
      announce_hosts+=",$(normalize_fqdn "$resolved_host")"
    fi
  done <<< "$resolution_output"

  printf '%s\t%s\n' "$announce_hosts" "$announce_port"
}

register_replica_announce_identity() {
  local replica_fqdn="$1"
  local announce_hosts_csv="$2"
  local announce_port="$3"
  local -a announce_hosts
  local announce_host
  local normalized_host
  local identity_key
  local current_owner

  IFS=',' read -ra announce_hosts <<< "$announce_hosts_csv"
  for announce_host in "${announce_hosts[@]}"; do
    normalized_host=$(normalize_fqdn "$announce_host")
    [[ -n "$normalized_host" ]] || continue
    identity_key="${normalized_host}|port=${announce_port}"
    current_owner="${ANNOUNCE_TUPLE_OWNERS[$identity_key]:-}"
    if [[ -n "$current_owner" ]] && ! same_fqdn "$current_owner" "$replica_fqdn"; then
      ANNOUNCE_IDENTITY_ERROR="Replica announce identity ${normalized_host}:${announce_port} is shared by $current_owner and $replica_fqdn"
      echo "Error: $ANNOUNCE_IDENTITY_ERROR" >&2
      return 1
    fi
  done

  for announce_host in "${announce_hosts[@]}"; do
    normalized_host=$(normalize_fqdn "$announce_host")
    [[ -n "$normalized_host" ]] || continue
    identity_key="${normalized_host}|port=${announce_port}"
    ANNOUNCE_TUPLE_OWNERS["$identity_key"]="$replica_fqdn"
  done
}

sentinel_observed_replica_priority() {
  local sentinel_fqdn="$1"
  local replica_announce_hosts="$2"
  local replica_announce_port="$3"
  local master_name="${CUSTOM_SENTINEL_MASTER_NAME:-$REDIS_COMPONENT_NAME}"
  local output

  unset_xtrace_when_ut_mode_false
  if [[ -z "$SENTINEL_PASSWORD" ]]; then
    output=$(run_redis_cli -h "$sentinel_fqdn" -p "$SENTINEL_SERVICE_PORT" \
      SENTINEL REPLICAS "$master_name")
  else
    output=$(run_redis_cli -h "$sentinel_fqdn" -p "$SENTINEL_SERVICE_PORT" \
      -a "$SENTINEL_PASSWORD" SENTINEL REPLICAS "$master_name")
  fi
  local status=$?
  set_xtrace_when_ut_mode_false
  [[ $status -eq 0 ]] || return 1

  printf '%s\n' "$output" \
    | tr -d '"' \
    | sed 's/.*) //' \
    | awk \
      -v candidate_hosts="$replica_announce_hosts" \
      -v candidate_port="$replica_announce_port" '
        BEGIN {
          candidate_count = split(candidate_hosts, host_list, ",")
          for (i = 1; i <= candidate_count; i++) {
            accepted_hosts[host_list[i]] = 1
          }
        }
        previous == "name" {
          replica_host = ""
          replica_port = ""
        }
        previous == "ip" {
          replica_host = tolower($0)
          sub(/\.$/, "", replica_host)
        }
        previous == "port" {
          replica_port = $0
        }
        previous == "slave-priority" {
          if (accepted_hosts[replica_host] && replica_port == candidate_port) {
            print
            exit
          }
        }
        { previous = $0 }
      '
}

wait_sentinel_sees_priority_bias() {
  local candidate_fqdn="$1"
  local current_master="$2"
  local deadline=$((SECONDS + sentinel_priority_wait_seconds))
  local -a sentinel_pod_fqdn_list redis_pod_fqdn_list

  while [[ $SECONDS -lt $deadline ]]; do
    IFS=',' read -ra sentinel_pod_fqdn_list <<< "${SENTINEL_POD_FQDN_LIST}"
    IFS=',' read -ra redis_pod_fqdn_list <<< "${REDIS_POD_FQDN_LIST}"
    local -A announce_hosts=()
    local -A announce_ports=()
    local announce_identity_conflict=false
    ANNOUNCE_TUPLE_OWNERS=()
    ANNOUNCE_IDENTITY_ERROR=""
    local redis_pod_fqdn
    for redis_pod_fqdn in "${redis_pod_fqdn_list[@]}"; do
      same_fqdn "$redis_pod_fqdn" "$current_master" && continue
      local announce_address
      if announce_address=$(redis_replica_announce_address "$redis_pod_fqdn"); then
        IFS=$'\t' read -r \
          announce_hosts["$redis_pod_fqdn"] \
          announce_ports["$redis_pod_fqdn"] <<< "$announce_address"
        if ! register_replica_announce_identity \
          "$redis_pod_fqdn" \
          "${announce_hosts[$redis_pod_fqdn]}" \
          "${announce_ports[$redis_pod_fqdn]}" 2>/dev/null; then
          announce_identity_conflict=true
        fi
      fi
    done

    local total=0
    local confirmed=0
    local sentinel_pod_fqdn

    for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
      for redis_pod_fqdn in "${redis_pod_fqdn_list[@]}"; do
        local expected_priority=100
        local observed_priority

        # Sentinel does not list the current primary as a replica before failover.
        same_fqdn "$redis_pod_fqdn" "$current_master" && continue
        same_fqdn "$redis_pod_fqdn" "$candidate_fqdn" && expected_priority=1
        [[ "${ORIGINAL_PRIORITIES[$redis_pod_fqdn]}" == "0" ]] \
          && ! same_fqdn "$redis_pod_fqdn" "$candidate_fqdn" \
          && expected_priority=0

        total=$((total + 1))
        [[ -n "${announce_hosts[$redis_pod_fqdn]:-}" ]] || continue
        observed_priority=$(sentinel_observed_replica_priority \
          "$sentinel_pod_fqdn" \
          "${announce_hosts[$redis_pod_fqdn]}" \
          "${announce_ports[$redis_pod_fqdn]}") || true
        [[ "$observed_priority" == "$expected_priority" ]] && confirmed=$((confirmed + 1))
      done
    done

    if [[ "$announce_identity_conflict" == "false" \
      && $total -gt 0 \
      && $confirmed -eq $total ]]; then
      echo "All Sentinel replica priority caches confirmed targeted bias for $candidate_fqdn."
      return 0
    fi
    sleep_when_ut_mode_false 1
  done

  [[ -z "$ANNOUNCE_IDENTITY_ERROR" ]] \
    || echo "Error: $ANNOUNCE_IDENTITY_ERROR" >&2
  echo "Error: Sentinel did not confirm targeted priority bias for $candidate_fqdn within ${sentinel_priority_wait_seconds}s" >&2
  return 1
}

# set target candidate highest priority to make sure it will be promoted to master
set_redis_priorities() {
  local candidate_fqdn="$1"

  local -a redis_pod_fqdn_list
  IFS=',' read -ra redis_pod_fqdn_list <<< "${REDIS_POD_FQDN_LIST}"
  for redis_pod_fqdn in "${redis_pod_fqdn_list[@]}"; do
    call_func_with_retry 3 5 check_connectivity "$redis_pod_fqdn" "$redis_service_port" "$REDIS_DEFAULT_PASSWORD" || return 1

    # Get original priority
    local redis_get_cmd="CONFIG GET replica-priority"
    local original_priority_output
    local original_priority
    if ! original_priority_output=$(redis_config_get \
      "$redis_pod_fqdn" "$redis_service_port" "$REDIS_DEFAULT_PASSWORD" "$redis_get_cmd"); then
      echo "Error: Failed to get replica-priority for $redis_pod_fqdn" >&2
      return 1
    fi
    original_priority=$(printf '%s\n' "$original_priority_output" | sed -n '2p')
    if [[ ! "$original_priority" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid replica-priority for $redis_pod_fqdn: $original_priority" >&2
      return 1
    fi

    # Save original priority to global variable
    ORIGINAL_PRIORITIES[$redis_pod_fqdn]=$original_priority

    local redis_set_cmd
    if same_fqdn "$redis_pod_fqdn" "$candidate_fqdn"; then
      redis_set_cmd="CONFIG SET replica-priority 1"
    elif [[ "$original_priority" == "0" ]]; then
      echo "Preserving never-promote replica-priority=0 on $redis_pod_fqdn."
      continue
    else
      redis_set_cmd="CONFIG SET replica-priority 100"
    fi

    # The command can apply server-side before its response is lost or times out.
    priorities_mutated=true
    call_func_with_retry 3 5 execute_sub_command "$redis_pod_fqdn" "$redis_service_port" "$REDIS_DEFAULT_PASSWORD" "$redis_set_cmd" || return 1
  done
  return 0
}

# recover all redis replica-priority
recover_redis_priorities() {
  echo "Recovering all FalkorDB replica-priority..."
  local redis_pod_fqdn
  local failed=0
  local -a restore_pids=()
  for redis_pod_fqdn in "${!ORIGINAL_PRIORITIES[@]}"; do
    local redis_set_recover_cmd="CONFIG SET replica-priority ${ORIGINAL_PRIORITIES[$redis_pod_fqdn]}"
    # Restore members in parallel so topology size does not multiply the TERM
    # grace budget. Each worker is bounded by two (5s + 2s kill-grace) calls
    # and one 1s retry sleep, for a worst-case worker budget below 15s.
    (
      call_func_with_retry "$priority_recovery_attempts" \
        "$priority_recovery_retry_interval_seconds" execute_sub_command \
        "$redis_pod_fqdn" "$redis_service_port" "$REDIS_DEFAULT_PASSWORD" \
        "$redis_set_recover_cmd"
    ) &
    restore_pids+=("$!")
  done
  local restore_pid
  for restore_pid in "${restore_pids[@]}"; do
    wait "$restore_pid" || failed=1
  done
  [[ $failed -eq 0 ]] || return 1
  priorities_mutated=false
  echo "All FalkorDB config set replica-priority recovered."
  return 0
}

cleanup_redis_priorities() {
  if [[ "$priorities_mutated" == "true" ]]; then
    if ! recover_redis_priorities; then
      echo "Error: Failed to restore one or more FalkorDB replica priorities" >&2
      return 1
    fi
  fi
  return 0
}

handle_termination() {
  local signal="$1"
  trap - EXIT TERM INT
  cleanup_redis_priorities
  echo "Error: FalkorDB switchover interrupted by $signal" >&2
  exit 1
}

supervise_switchover_action() {
  local action_timeout="$1"
  local cleanup_grace="$2"
  shift 2
  exec timeout -k "$cleanup_grace" "$action_timeout" "$@"
}

falkordb_switchover_main() {
  if [[ "${1:-}" != "--falkordb-switchover-deadline-child" ]]; then
    if ! command -v timeout >/dev/null 2>&1; then
      echo "Error: timeout command is required for bounded FalkorDB switchover" >&2
      return 1
    fi
    supervise_switchover_action \
      "$switchover_action_timeout_seconds" "$switchover_cleanup_grace_seconds" \
      /bin/bash "$0" --falkordb-switchover-deadline-child "$@"
    return $?
  fi

  shift
  run_switchover_action "$@"
}

switchover_with_candidate() {
  if ! fqdn_in_csv "$KB_SWITCHOVER_CANDIDATE_FQDN" "$REDIS_POD_FQDN_LIST"; then
    echo "Error: Candidate node $KB_SWITCHOVER_CANDIDATE_FQDN is not an exact member of REDIS_POD_FQDN_LIST" >&2
    return 1
  fi

  # check the role of candidate before switchover
  local candidate_role
  candidate_role=$(check_redis_role "$KB_SWITCHOVER_CANDIDATE_FQDN" "$redis_service_port")
  if [[ "$candidate_role" != "secondary" ]]; then
    echo "Error: Candidate node $KB_SWITCHOVER_CANDIDATE_FQDN is not in secondary role" >&2
    return 1
  fi

  # check redis kernel role before switchover
  local initial_master
  initial_master=$(check_redis_kernel_status) || return 1

  # set target candidate highest priority to make sure it will be promoted to master
  unset_xtrace_when_ut_mode_false
  set_redis_priorities "$KB_SWITCHOVER_CANDIDATE_FQDN" || return 1

  # Sentinel caches replica priority independently on each pod. Wait until all
  # Sentinels see the requested bias before asking any one of them to fail over.
  wait_sentinel_sees_priority_bias "$KB_SWITCHOVER_CANDIDATE_FQDN" "$initial_master" || return 1

  # do switchover
  execute_sentinel_failover "$CUSTOM_SENTINEL_MASTER_NAME" || return 1

  # check switchover result
  check_switchover_result "$KB_SWITCHOVER_CANDIDATE_FQDN" "" || return 1

  # recover all redis replica-priority
  echo "Recovering all FalkorDB replica-priority..."
  recover_redis_priorities || return 1

  set_xtrace_when_ut_mode_false
}

switchover_without_candidate() {
  # check redis kernel role before switchover
  local initial_master
  initial_master=$(check_redis_kernel_status) || return 1

  # do switchover
  execute_sentinel_failover "$CUSTOM_SENTINEL_MASTER_NAME" || return 1

  # check switchover result using initial_master
  # if no candidate specified, skip check
  # check_switchover_result "" "$initial_master" || return 1
}

run_switchover_action() {
  load_common_library || return 1
  check_environment_exist || return 1
  trap cleanup_redis_priorities EXIT
  trap 'handle_termination TERM' TERM
  trap 'handle_termination INT' INT

  local action_status=0
  if is_empty "$KB_SWITCHOVER_CANDIDATE_FQDN"; then
    switchover_without_candidate || action_status=$?
  else
    switchover_with_candidate || action_status=$?
  fi

  local cleanup_status=0
  cleanup_redis_priorities || cleanup_status=$?
  trap - EXIT TERM INT

  [[ $action_status -eq 0 ]] || return "$action_status"
  return "$cleanup_status"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# kbagent's positive action timeout is capped at 60s, while Sentinel convergence
# can legitimately exceed that. The child process therefore owns the lifecycle,
# but is still supervised by a hard wall-clock deadline. The kill grace lets its
# TERM/EXIT cleanup restore any temporary replica-priority mutations.
falkordb_switchover_main "$@"
