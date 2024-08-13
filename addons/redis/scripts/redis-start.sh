#!/bin/bash

# shellcheck disable=SC2153
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
retry_times=3
retry_delay_second=2

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

set_xtrace() {
  if [ "false" == "$ut_mode" ]; then
    set -x
  fi
}

unset_xtrace() {
  if [ "false" == "$ut_mode" ]; then
    set +x
  fi
}

# TODO: it will be removed in the future
extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

load_redis_template_conf() {
  echo "include $redis_template_conf" >> $redis_real_conf
}

build_redis_default_accounts() {
  unset_xtrace
  if env_exist REDIS_REPL_PASSWORD; then
    echo "masteruser $REDIS_REPL_USER" >> $redis_real_conf
    echo "masterauth $REDIS_REPL_PASSWORD" >> $redis_real_conf
    echo "user $REDIS_REPL_USER on +psync +replconf +ping >$REDIS_REPL_PASSWORD" >> $redis_acl_file
  fi
  if env_exist REDIS_SENTINEL_PASSWORD; then
    echo "user $REDIS_SENTINEL_USER on allchannels +multi +slaveof +ping +exec +subscribe +config|rewrite +role +publish +info +client|setname +client|kill +script|kill >$REDIS_SENTINEL_PASSWORD" >> $redis_acl_file
  fi
  if env_exist REDIS_DEFAULT_PASSWORD; then
    echo "protected-mode yes" >> $redis_real_conf
    echo "user default on >$REDIS_DEFAULT_PASSWORD ~* &* +@all " >> $redis_acl_file
  else
    echo "protected-mode no" >> $redis_real_conf
  fi
  set_xtrace
  echo "aclfile /data/users.acl" >> $redis_real_conf
  echo "build default accounts succeeded!"
}

build_announce_ip_and_port() {
  # build announce ip and port according to whether the advertised svc is enabled
  if ! is_empty "$redis_advertised_svc_host_value" && ! is_empty "$redis_advertised_svc_port_value"; then
    echo "redis use nodeport $redis_advertised_svc_host_value:$redis_advertised_svc_port_value to announce"
    {
      echo "replica-announce-port $redis_advertised_svc_port_value"
      echo "replica-announce-ip $redis_advertised_svc_host_value"
    } >> $redis_real_conf
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
  service_port=6379
  if env_exist SERVICE_PORT; then
    service_port=$SERVICE_PORT
  fi
  echo "port $service_port" >> $redis_real_conf
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
    sed -i '' "/user default on/d" $redis_acl_file
    sed -i '' "/user $REDIS_REPL_USER on/d" $redis_acl_file
    sed -i '' "/user $REDIS_SENTINEL_USER on/d" $redis_acl_file
  else
    touch $redis_acl_file
  fi
}

init_or_get_primary_from_redis_sentinel() {
  # check redis sentinel component env
  if ! env_exist SENTINEL_COMPONENT_NAME; then
    # return default primary node if redis sentinel component name is not set
    echo "SENTINEL_COMPONENT_NAME env is not set, try to use default primary node."
    get_default_initialize_primary_node
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
  echo "timeout $timeout_value redis-cli -h $sentinel_pod_fqdn -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD sentinel get-master-addr-by-name $KB_CLUSTER_COMP_NAME"
}

get_master_addr_by_name_from_sentinel() {
  local master_addr_by_name_command
  local sentinel_pod_fqdn="$1"
  unset_xtrace
  master_addr_by_name_command=$(build_sentinel_get_master_addr_by_name_command "$sentinel_pod_fqdn")
  echo "execute get-master-addr-by-name command: $master_addr_by_name_command" | sed "s/$SENTINEL_PASSWORD/********/g"
  output=$(eval "$master_addr_by_name_command")
  exit_code=$?
  set_xtrace

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
  current_pod="$CURRENT_POD_NAME.$KB_CLUSTER_COMP_NAME"
  if contains "$primary" "$current_pod"; then
    echo "current pod is primary with name mapping, primary node: $primary, pod name:$current_pod"
    return 0
  fi

  if ! is_empty "$redis_advertised_svc_host_value" && ! is_empty "$redis_advertised_svc_port_value"; then
    if equals "$primary" "$redis_advertised_svc_host_value" && equals "$primary_port" "$redis_advertised_svc_port_value"; then
      echo "current pod is primary with advertised svc mapping, primary: $primary, primary port: $primary_port, advertised ip:$redis_advertised_svc_host_value, advertised port:$redis_advertised_svc_port_value"
      return 0
    fi
    echo "redis advertised svc host and port exist but not match, primary: $primary, primary port: $primary_port, advertised ip:$redis_advertised_svc_host_value, advertised port:$redis_advertised_svc_port_value"
  fi

  if equals "$primary" "$CURRENT_POD_IP" && equals "$primary_port" "$service_port"; then
    echo "current pod is primary with pod ip mapping, primary node: $primary, pod ip:$CURRENT_POD_IP, service port:$service_port"
    return 0
  fi
  return 1
}

start_redis_server() {
    exec_cmd="exec redis-server /etc/redis/redis.conf"
    if [ -f /opt/redis-stack/lib/redisearch.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redisearch.so ${REDISEARCH_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/redistimeseries.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redistimeseries.so ${REDISTIMESERIES_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/rejson.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/rejson.so ${REDISJSON_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/redisbloom.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redisbloom.so ${REDISBLOOM_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/redisgraph.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redisgraph.so ${REDISGRAPH_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/rediscompat.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/rediscompat.so"
    fi
    if [ -f /opt/redis-stack/lib/redisgears.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redisgears.so v8-plugin-path /opt/redis-stack/lib/libredisgears_v8_plugin.so ${REDISGEARS_ARGS}"
    fi
    echo "Starting redis server cmd: $exec_cmd"
    eval "$exec_cmd"
}

# TODO: if instanceTemplate is specified, the pod service could not be parsed from the pod ordinal.
parse_redis_advertised_svc_if_exist() {
  local pod_name="$1"

  if ! env_exist REDIS_ADVERTISED_PORT; then
    echo "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    return 0
  fi

  local found=false
  pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
  # the value format of REDIS_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  advertised_ports=($(split "$REDIS_ADVERTISED_PORT" ","))
  for advertised_port in "${advertised_ports[@]}"; do
    parts=($(split "$advertised_port" ":"))
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_ordinal_from_object_name "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      redis_advertised_svc_port_value="$port"
      redis_advertised_svc_host_value="$CURRENT_POD_HOST_IP"
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
  load_redis_template_conf
  build_announce_ip_and_port
  build_redis_service_port
  build_replicaof_config
  rebuild_redis_acl_file
  build_redis_default_accounts
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
parse_redis_advertised_svc_if_exist "$CURRENT_POD_NAME"
build_redis_conf
start_redis_server
