#!/bin/bash

# shellcheck disable=SC2153
# shellcheck disable=SC2207
# shellcheck disable=SC2034

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
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

primary=""
primary_port="6379"
redis_template_conf="/etc/conf/redis.conf"
redis_real_conf="/etc/redis/redis.conf"
redis_acl_file="/data/users.acl"
redis_acl_file_bak="/data/users.acl.bak"
redis_start_initialized_file="${REDIS_START_INITIALIZED_FILE:-/data/.kb_redis_start_initialized}"
retry_times=3
retry_delay_second=2
service_port=${SERVICE_PORT:-6379}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

load_redis_template_conf() {
  echo "include $redis_template_conf" >> $redis_real_conf
}

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

build_redis_default_accounts() {
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$REDIS_REPL_PASSWORD"; then
    echo "masteruser $REDIS_REPL_USER" >> $redis_real_conf
    echo "masterauth $REDIS_REPL_PASSWORD" >> $redis_real_conf
    redis_repl_password_sha256=$(echo -n "$REDIS_REPL_PASSWORD" | sha256sum | cut -d' ' -f1)
    echo "user $REDIS_REPL_USER on +psync +replconf +ping #$redis_repl_password_sha256" >> $redis_acl_file
  fi
  if ! is_empty "$REDIS_SENTINEL_PASSWORD"; then
    redis_sentinel_password_sha256=$(echo -n "$REDIS_SENTINEL_PASSWORD" | sha256sum | cut -d' ' -f1)
    echo "user $REDIS_SENTINEL_USER on allchannels +multi +slaveof +ping +exec +subscribe +config|rewrite +role +publish +info +client|setname +client|kill +script|kill #$redis_sentinel_password_sha256" >> $redis_acl_file
  fi
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    echo "protected-mode yes" >> $redis_real_conf
    redis_password_sha256=$(echo -n "$REDIS_DEFAULT_PASSWORD" | sha256sum | cut -d' ' -f1)
    echo "user default on #$redis_password_sha256 ~* &* +@all " >> $redis_acl_file
  else
    echo "protected-mode no" >> $redis_real_conf
  fi
  set_xtrace_when_ut_mode_false
  echo "aclfile /data/users.acl" >> $redis_real_conf
  echo "build default accounts succeeded!"
}

build_announce_ip_and_port() {
  # build announce ip and port according to whether the announce addr is exist
  if ! is_empty "$redis_announce_host_value" && ! is_empty "$redis_announce_port_value"; then
    echo "redis use nodeport $redis_announce_host_value:$redis_announce_port_value to announce"
    {
      echo "replica-announce-port $redis_announce_port_value"
      echo "replica-announce-ip $redis_announce_host_value"
    } >> $redis_real_conf
  elif [ "$FIXED_POD_IP_ENABLED" == "true" ]; then
      echo "" > /data/.fixed_pod_ip_enabled
      echo "redis use immutable pod ip $CURRENT_POD_IP to announce"
      echo "replica-announce-ip $CURRENT_POD_IP" >> /etc/redis/redis.conf
  else
    current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$REDIS_POD_FQDN_LIST" "$CURRENT_POD_NAME")
    if is_empty "$current_pod_fqdn"; then
      echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from redis pod fqdn list: $REDIS_POD_FQDN_LIST. Exiting."
      exit 1
    fi
    echo "redis use kb pod fqdn $current_pod_fqdn to announce"
    echo "replica-announce-ip $current_pod_fqdn" >> $redis_real_conf
  fi
}

build_redis_service_port() {
  if [ "$TLS_ENABLED" == "true" ]; then
    echo "tls-port $service_port" >> $redis_real_conf
  else
    echo "port $service_port" >> $redis_real_conf
  fi
}

build_redis_tls_config() {
  if [ "$TLS_ENABLED" == "true" ]; then
    TLS_MOUNT_PATH=${TLS_MOUNT_PATH:-/etc/pki/tls}
    {
      echo "tls-cert-file $TLS_MOUNT_PATH/tls.crt"
      echo "tls-key-file $TLS_MOUNT_PATH/tls.key"
      echo "tls-ca-cert-file $TLS_MOUNT_PATH/ca.crt"
      echo "tls-auth-clients no"
      echo "tls-replication yes"
      echo "port 0"
    } >> $redis_real_conf
  fi
}

build_replicaof_config() {
  init_or_get_primary_from_redis_sentinel
  if check_current_pod_is_primary; then
    return
  else
    echo "replicaof $primary $primary_port" >> $redis_real_conf
  fi
}

rebuild_redis_acl_file() {
  if [ -f $redis_acl_file ]; then
    sed "/user default on/d" $redis_acl_file > $redis_acl_file_bak && mv $redis_acl_file_bak $redis_acl_file
    sed "/user $REDIS_REPL_USER on/d" $redis_acl_file > $redis_acl_file_bak && mv $redis_acl_file_bak $redis_acl_file
    sed "/user $REDIS_SENTINEL_USER on/d" $redis_acl_file > $redis_acl_file_bak && mv $redis_acl_file_bak $redis_acl_file
  else
    touch $redis_acl_file
  fi
}

init_or_get_primary_from_redis_sentinel() {
  # check redis sentinel component env
  if ! env_exist SENTINEL_COMPONENT_NAME; then
    # In syncer-managed replication, there is no external Sentinel component.
    # Avoid lexicographic bootstrap as primary for multi-replica clusters because
    # it can emit a transient primary role before syncer has aligned with DCS.
    init_or_get_primary_from_syncer
    return
  fi

  # parse redis sentinel pod fqdn list from $SENTINEL_POD_FQDN_LIST env
  if ! env_exist SENTINEL_POD_FQDN_LIST; then
    echo "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set."
    exit 1
  fi

  declare -A master_count_map
  local first_redis_primary_host=""
  local first_redis_primary_port=""
  sentinel_pod_fqdn_list=($(split "$SENTINEL_POD_FQDN_LIST" ","))
  for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
    # get primary info from sentinel
    if retry_get_master_addr_by_name_from_sentinel $retry_times $retry_delay_second "$sentinel_pod_fqdn"; then
      echo "sentinel:$sentinel_pod_fqdn has master info: ${REDIS_SENTINEL_PRIMARY_INFO[*]}"
      if [ "${#REDIS_SENTINEL_PRIMARY_INFO[@]}" -ne 2 ] || [ -z "${REDIS_SENTINEL_PRIMARY_INFO[0]}" ] || [ -z "${REDIS_SENTINEL_PRIMARY_INFO[1]}" ]; then
        echo "Empty primary info retrieved from sentinel: $sentinel_pod_fqdn. Skipping this sentinel."
        continue
      fi

      # increment the count of this master in the map
      host_port_key="${REDIS_SENTINEL_PRIMARY_INFO[0]}:${REDIS_SENTINEL_PRIMARY_INFO[1]}"
      master_count_map[$host_port_key]=$((${master_count_map[$host_port_key]} + 1))

      # track the primary host and port from the first sentinel
      if is_empty "$first_redis_primary_host" && is_empty "$first_redis_primary_port"; then
        first_redis_primary_host=${REDIS_SENTINEL_PRIMARY_INFO[0]}
        first_redis_primary_port=${REDIS_SENTINEL_PRIMARY_INFO[1]}
      fi

      # log if sentinel has different primary node info
      if ! equals "$first_redis_primary_host" "${REDIS_SENTINEL_PRIMARY_INFO[0]}" || ! equals "$first_redis_primary_port" "${REDIS_SENTINEL_PRIMARY_INFO[1]}"; then
        echo "The sentinel:$sentinel_pod_fqdn has different primary node info. First: $first_redis_primary_host:$first_redis_primary_port, Current: ${REDIS_SENTINEL_PRIMARY_INFO[0]}:${REDIS_SENTINEL_PRIMARY_INFO[1]}"
      fi
    else
      echo "Failed to retrieve primary info from sentinel: $sentinel_pod_fqdn. Skipping this sentinel."
    fi
  done

  # if there is no primary node found, use the default primary node
  echo "get all primary info from redis sentinel master_count_map: ${master_count_map[*]}"
  if [ ${#master_count_map[@]} -eq 0 ]; then
    echo "no primary node found from all redis sentinels, use default primary node."
    get_default_initialize_primary_node
    return
  fi

  # get the primary node with the most counts
  max_count=0
  for host_port in "${!master_count_map[@]}"; do
    if (( ${master_count_map[$host_port]} > max_count )); then
      max_count=${master_count_map[$host_port]}
      primary=$(echo $host_port | cut -d: -f1)
      primary_port=$(echo $host_port | cut -d: -f2)
    fi
  done
}

build_sentinel_get_master_addr_by_name_command() {
  local sentinel_pod_fqdn="$1"
  local timeout_value=5
  # TODO: replace $SENTINEL_SERVICE_PORT with each sentinel pod's port when sentinel service port is not the same, for example in HostNetwork mode
  sentinel_service_port=${SENTINEL_SERVICE_PORT:-26379}
  if is_empty "$SENTINEL_PASSWORD"; then
    echo "timeout $timeout_value redis-cli $REDIS_CLI_TLS_CMD -h $sentinel_pod_fqdn -p $sentinel_service_port sentinel get-master-addr-by-name $REDIS_COMPONENT_NAME"
  else
    echo "timeout $timeout_value redis-cli $REDIS_CLI_TLS_CMD -h $sentinel_pod_fqdn -p $sentinel_service_port -a $SENTINEL_PASSWORD sentinel get-master-addr-by-name $REDIS_COMPONENT_NAME"
  fi
}

get_master_addr_by_name_from_sentinel() {
  local master_addr_by_name_command
  local sentinel_pod_fqdn="$1"
  unset_xtrace_when_ut_mode_false
  master_addr_by_name_command=$(build_sentinel_get_master_addr_by_name_command "$sentinel_pod_fqdn")
  logging_mask_password_command="${master_addr_by_name_command/$SENTINEL_PASSWORD/********}"
  echo "execute get-master-addr-by-name command: $logging_mask_password_command"
  output=$(eval "$master_addr_by_name_command")
  exit_code=$?
  set_xtrace_when_ut_mode_false

  if [ $exit_code -eq 0 ]; then
    read -r -d '' -a REDIS_SENTINEL_PRIMARY_INFO <<< "$output"
    if [ "${#REDIS_SENTINEL_PRIMARY_INFO[@]}" -eq 2 ] && [ -n "${REDIS_SENTINEL_PRIMARY_INFO[0]}" ] && [ -n "${REDIS_SENTINEL_PRIMARY_INFO[1]}" ]; then
      echo "Successfully retrieved primary info from sentinel"
      return 0
    else
      echo "Empty primary info retrieved from sentinel"
      return 1
    fi
  else
    if [ $exit_code -eq 124 ]; then
      echo "Timeout occurred while retrieving primary info from sentinel. Retrying..."
    else
      echo "Error occurred while retrieving primary info from sentinel. Retrying..."
    fi
    return 1
  fi
}

retry_get_master_addr_by_name_from_sentinel() {
  local max_retry="$1"
  local retry_delay="$2"
  local sentinel_pod_fqdn="$3"
  if call_func_with_retry "$max_retry" "$retry_delay" get_master_addr_by_name_from_sentinel "$sentinel_pod_fqdn"; then
    return 0
  else
    echo "Failed to retrieve primary info from sentinel: $sentinel_pod_fqdn after $max_retry retries."
    return 1
  fi
}

init_or_get_primary_from_syncer() {
  local component_replicas="${COMPONENT_REPLICAS:-1}"
  if ! [[ "$component_replicas" =~ ^[0-9]+$ ]]; then
    component_replicas=1
  fi

  if [ "$component_replicas" -le 1 ]; then
    echo "SENTINEL_COMPONENT_NAME env is not set and component has one replica, use default primary node."
    get_default_initialize_primary_node
    return
  fi

  echo "SENTINEL_COMPONENT_NAME env is not set, try to get primary from syncer Fake Sentinel."
  local syncer_retry_times="${SYNCER_SENTINEL_RETRY_TIMES:-6}"
  local syncer_retry_delay_second="${SYNCER_SENTINEL_RETRY_DELAY_SECOND:-2}"
  if retry_get_master_addr_by_name_from_syncer "$syncer_retry_times" "$syncer_retry_delay_second"; then
    primary="${REDIS_SENTINEL_PRIMARY_INFO[0]}"
    primary_port="${REDIS_SENTINEL_PRIMARY_INFO[1]}"
    echo "syncer Fake Sentinel has master info: $primary $primary_port"
    return
  fi

  echo "syncer Fake Sentinel has no stable master info, start as conservative replica until syncer promotes or follows."
  if syncer_initial_bootstrap_default_primary_allowed; then
    echo "syncer has no master info and current pod is allowed to use default primary for initial bootstrap."
    get_default_initialize_primary_node
    return
  fi
  set_conservative_replicaof_target
}

build_syncer_get_master_addr_by_name_command() {
  local timeout_value="${SYNCER_SENTINEL_QUERY_TIMEOUT:-2}"
  local syncer_sentinel_host="${SYNCER_SENTINEL_HOST:-127.0.0.1}"
  local syncer_sentinel_port="${SYNCER_SENTINEL_PORT:-26379}"
  echo "timeout $timeout_value redis-cli -h $syncer_sentinel_host -p $syncer_sentinel_port sentinel get-master-addr-by-name $REDIS_COMPONENT_NAME"
}

get_master_addr_by_name_from_syncer() {
  local master_addr_by_name_command
  unset_xtrace_when_ut_mode_false
  master_addr_by_name_command=$(build_syncer_get_master_addr_by_name_command)
  echo "execute syncer get-master-addr-by-name command: $master_addr_by_name_command"
  output=$(eval "$master_addr_by_name_command")
  exit_code=$?
  set_xtrace_when_ut_mode_false

  if [ $exit_code -eq 0 ]; then
    read -r -d '' -a REDIS_SENTINEL_PRIMARY_INFO <<< "$output"
    if [ "${#REDIS_SENTINEL_PRIMARY_INFO[@]}" -eq 2 ] && [ -n "${REDIS_SENTINEL_PRIMARY_INFO[0]}" ] && [ -n "${REDIS_SENTINEL_PRIMARY_INFO[1]}" ]; then
      echo "Successfully retrieved primary info from syncer Fake Sentinel"
      return 0
    fi
    echo "Empty primary info retrieved from syncer Fake Sentinel"
    return 1
  fi

  if [ $exit_code -eq 124 ]; then
    echo "Timeout occurred while retrieving primary info from syncer Fake Sentinel. Retrying..."
  else
    echo "Error occurred while retrieving primary info from syncer Fake Sentinel. Retrying..."
  fi
  return 1
}

retry_get_master_addr_by_name_from_syncer() {
  local max_retry="$1"
  local retry_delay="$2"
  if call_func_with_retry "$max_retry" "$retry_delay" get_master_addr_by_name_from_syncer; then
    return 0
  fi
  echo "Failed to retrieve primary info from syncer Fake Sentinel after $max_retry retries."
  return 1
}

set_conservative_replicaof_target() {
  primary="${SYNCER_CONSERVATIVE_REPLICAOF_HOST:-127.0.0.1}"
  primary_port="${SYNCER_CONSERVATIVE_REPLICAOF_PORT:-1}"
  echo "use conservative replicaof target: $primary $primary_port"
}

is_redis_start_initialized() {
  [ -f "$redis_start_initialized_file" ]
}

mark_redis_start_initialized() {
  mkdir -p "$(dirname "$redis_start_initialized_file")" 2>/dev/null || true
  date +%s > "$redis_start_initialized_file" 2>/dev/null || true
}

syncer_initial_bootstrap_default_primary_allowed() {
  local dcs_leader_status
  syncer_dcs_leader_status
  dcs_leader_status=$?

  if [ "$dcs_leader_status" -eq 0 ]; then
    echo "syncer DCS leader already exists, skip default bootstrap primary."
    return 1
  fi

  if [ "$dcs_leader_status" -ne 1 ]; then
    echo "syncer DCS leader status is unknown, skip default bootstrap primary."
    return 1
  fi

  if is_redis_start_initialized; then
    echo "redis start marker exists but syncer DCS leader is confirmed not found: $redis_start_initialized_file"
  fi

  local min_lex_pod
  min_lex_pod=$(min_lexicographical_order_pod "$REDIS_POD_NAME_LIST")
  if equals "$CURRENT_POD_NAME" "$min_lex_pod"; then
    echo "current pod $CURRENT_POD_NAME is default bootstrap primary and syncer DCS leader is not found."
    return 0
  fi

  echo "current pod $CURRENT_POD_NAME is not default bootstrap primary: $min_lex_pod"
  return 1
}

syncer_dcs_leader_status() {
  local leader_configmap_name="${SYNCER_DCS_LEADER_CONFIGMAP_NAME:-${REDIS_COMPONENT_NAME}-leader}"
  local query_timeout="${SYNCER_DCS_QUERY_TIMEOUT:-2}"
  if command -v syncerctl >/dev/null 2>&1; then
    syncerctl_dcs_leader_status "$leader_configmap_name" "$query_timeout"
    return $?
  fi

  echo "syncerctl is not available, fallback to python3 for syncer DCS leader status."
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is not available, syncer DCS leader status is unknown."
    return 2
  fi

  timeout "$query_timeout" python3 - "$leader_configmap_name" <<'PY'
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

name = sys.argv[1]
host = os.environ.get("KUBERNETES_SERVICE_HOST")
port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")
token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
ca_path = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
namespace_path = "/var/run/secrets/kubernetes.io/serviceaccount/namespace"
namespace = os.environ.get("CLUSTER_NAMESPACE")
try:
    if not namespace:
        with open(namespace_path, encoding="utf-8") as f:
            namespace = f.read().strip()
    with open(token_path, encoding="utf-8") as f:
        token = f.read().strip()
    if not host or not namespace or not token:
        raise RuntimeError("missing kubernetes service account context")

    url = f"https://{host}:{port}/api/v1/namespaces/{namespace}/configmaps/{name}"
    context = ssl.create_default_context(cafile=ca_path)
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, context=context, timeout=2) as response:
        obj = json.loads(response.read().decode("utf-8"))
    leader = obj.get("metadata", {}).get("annotations", {}).get("leader", "")
    if leader:
        print(f"syncer DCS leader configmap {name} exists with leader {leader}.")
        sys.exit(0)
    print(f"syncer DCS leader configmap {name} exists but leader is empty.")
    sys.exit(1)
except urllib.error.HTTPError as e:
    if e.code == 404:
        print(f"syncer DCS leader configmap {name} is not found.")
        sys.exit(1)
    print(f"failed to query syncer DCS leader configmap {name}: HTTP {e.code}")
    sys.exit(2)
except Exception as e:
    print(f"failed to query syncer DCS leader configmap {name}: {e}")
    sys.exit(2)
PY
  local exit_code=$?
  if [ "$exit_code" -eq 124 ]; then
    echo "query syncer DCS leader configmap $leader_configmap_name timed out, status is unknown."
    return 2
  fi
  if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ]; then
    return "$exit_code"
  fi
  return 2
}

syncerctl_dcs_leader_status() {
  local leader_configmap_name="$1"
  local query_timeout="$2"
  local namespace="${CLUSTER_NAMESPACE:-${KB_NAMESPACE:-${POD_NAMESPACE:-}}}"
  local output
  local exit_code
  local args=(dcs-leader-status --configmap "$leader_configmap_name")
  if [ -n "$namespace" ]; then
    args+=(--namespace "$namespace")
  fi

  if output=$(timeout "$query_timeout" syncerctl "${args[@]}" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi
  echo "$output"

  if [ "$exit_code" -eq 124 ]; then
    echo "query syncer DCS leader configmap $leader_configmap_name by syncerctl timed out, status is unknown."
    return 2
  fi
  if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 1 ]; then
    return "$exit_code"
  fi
  echo "syncerctl failed to query syncer DCS leader configmap $leader_configmap_name, status is unknown."
  return 2
}

get_default_initialize_primary_node() {
  # TODO: if has advertise svc and port, we should use it as default primary node info instead of the fqdn
  min_lex_pod=$(min_lexicographical_order_pod "$REDIS_POD_NAME_LIST")
  min_lex_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$REDIS_POD_FQDN_LIST" "$min_lex_pod")
  if is_empty "$min_lex_pod_fqdn"; then
    echo "Error: Failed to get min lexicographical order pod: $CURRENT_POD_NAME fqdn from redis pod fqdn list: $REDIS_POD_FQDN_LIST. Exiting."
    exit 1
  fi
  echo "get the minimum lexicographical order pod name: $min_lex_pod_fqdn as default primary node"
  primary="$min_lex_pod_fqdn"
  primary_port=$service_port
}

check_current_pod_is_primary() {
  current_pod_fqdn_prefix="$CURRENT_POD_NAME.$REDIS_COMPONENT_NAME"
  if contains "$primary" "$current_pod_fqdn_prefix"; then
    echo "current pod is primary with name mapping, primary node: $primary, pod fqdn prefix:$current_pod_fqdn_prefix"
    return 0
  fi

  if ! is_empty "$redis_announce_host_value" && ! is_empty "$redis_announce_port_value"; then
    if equals "$primary" "$redis_announce_host_value" && equals "$primary_port" "$redis_announce_port_value"; then
      echo "current pod is primary with advertised svc mapping, primary: $primary, primary port: $primary_port, advertised ip:$redis_announce_host_value, advertised port:$redis_announce_port_value"
      return 0
    fi
    echo "redis advertised svc host and port exist but not match, primary: $primary, primary port: $primary_port, advertised ip:$redis_announce_host_value, advertised port:$redis_announce_port_value"
  fi

  if equals "$primary" "$CURRENT_POD_IP" && equals "$primary_port" "$service_port"; then
    echo "current pod is primary with pod ip mapping, primary node: $primary, pod ip:$CURRENT_POD_IP, service port:$service_port"
    return 0
  fi
  return 1
}

start_redis_server() {
    module_path="/opt/redis-stack/lib"
    if [[ "$IS_REDIS8" == "true" ]]; then
       module_path="/usr/local/lib/redis/modules"
    fi
    exec_cmd="exec redis-server /etc/redis/redis.conf"
    if [ -f ${module_path}/redisearch.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/redisearch.so ${REDISEARCH_ARGS}"
    fi
    if [ -f ${module_path}/redistimeseries.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/redistimeseries.so ${REDISTIMESERIES_ARGS}"
    fi
    if [ -f ${module_path}/rejson.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/rejson.so ${REDISJSON_ARGS}"
    fi
    if [ -f ${module_path}/redisbloom.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/redisbloom.so ${REDISBLOOM_ARGS}"
    fi
    if [ -f ${module_path}/redisgraph.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/redisgraph.so ${REDISGRAPH_ARGS}"
    fi
    if [ -f ${module_path}/rediscompat.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/rediscompat.so"
    fi
    # NOTE: in replication mode, load this module will lead a memory leak for slave instance.
    #if [ -f ${module_path}/redisgears.so ]; then
    #    exec_cmd="$exec_cmd --loadmodule ${module_path}/redisgears.so v8-plugin-path ${module_path}/libredisgears_v8_plugin.so ${REDISGEARS_ARGS}"
    #fi
    echo "Starting redis server cmd: $exec_cmd"
    eval "$exec_cmd"
}

# TODO: if instanceTemplate is specified, the pod service could not be parsed from the pod ordinal.
parse_redis_announce_addr() {
  if is_empty "$REDIS_ADVERTISED_PORT"; then
     REDIS_ADVERTISED_PORT="$REDIS_LB_ADVERTISED_PORT"
  fi
  # try to get the announce ip and port from REDIS_ADVERTISED_PORT(support NodePort currently) first
  if is_empty "${REDIS_ADVERTISED_PORT}"; then
    echo "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    # if redis is in host network mode, use the host ip and port as the announce ip and port
    if ! is_empty "${REDIS_HOST_NETWORK_PORT}"; then
      echo "redis is in host network mode, use the host ip:$CURRENT_POD_HOST_IP and port:$REDIS_HOST_NETWORK_PORT as the announce ip and port."
      redis_announce_port_value="$REDIS_HOST_NETWORK_PORT"
      redis_announce_host_value="$CURRENT_POD_HOST_IP"
    fi
    return 0
  fi

  local pod_name="$1"
  local found=false
  pod_name_ordinal=$(extract_obj_ordinal "$pod_name")
  # the value format of REDIS_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  advertised_ports=($(split "$REDIS_ADVERTISED_PORT" ","))
  for advertised_port in "${advertised_ports[@]}"; do
    parts=($(split "$advertised_port" ":"))
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_obj_ordinal "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      redis_announce_port_value="$port"
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
    echo "Error: No matching svcName and port found for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. Exiting."
    exit 1
  fi
}

# build redis.conf
build_redis_conf() {
  # Truncate before building to guarantee a clean slate on every container start.
  # /etc/redis/ is an emptyDir that survives container restarts (but not pod
  # deletion). Without this truncation, CONFIG REWRITE (triggered by Sentinel)
  # writes 'loadmodule' back into redis.conf; on the next container restart the
  # accumulated 'loadmodule' line stays in the file, and start_redis_server()
  # also passes --loadmodule via CLI, causing the module to load twice.
  # Redis exits on the second load attempt → CrashLoopBackOff.
  # See: https://github.com/apecloud/kubeblocks-addons/issues/2686
  > "$redis_real_conf"
  load_redis_template_conf
  build_announce_ip_and_port
  build_redis_service_port
  build_redis_tls_config
  build_replicaof_config
  rebuild_redis_acl_file
  build_redis_default_accounts
  mark_redis_start_initialized
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
parse_redis_announce_addr "$CURRENT_POD_NAME"
build_redis_conf
start_redis_server
