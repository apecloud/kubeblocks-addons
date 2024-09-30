#!/bin/bash

# shellcheck disable=SC2153
# shellcheck disable=SC2207
# shellcheck disable=SC2034
# shellcheck disable=SC1090

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

service_port=6379
cluster_bus_port=16379
redis_template_conf="/etc/conf/redis.conf"
redis_real_conf="/etc/redis/redis.conf"
redis_acl_file="/data/users.acl"
redis_acl_file_bak="/data/users.acl.bak"
retry_times=3
check_ready_times=30
retry_delay_second=2

load_redis_cluster_common_utils() {
  # the common.sh and redis-cluster-common.sh scripts are defined in the redis-cluster-scripts-template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/common.sh"
  redis_cluster_common_library_file="/scripts/redis-cluster-common.sh"
  source "${kblib_common_library_file}"
  source "${redis_cluster_common_library_file}"
}

check_and_correct_other_primary_nodes() {
  local current_primary_endpoint="$1"
  local current_primary_port="$2"

  if [ ${#other_comp_primary_nodes[@]} -eq 0 ]; then
    echo "other_comp_primary_nodes is empty, skip check_and_correct_other_primary_nodes"
    return
  fi

  # node_info value format: cluster_announce_ip#pod_fqdn#endpoint:port@bus_port
  for node_info in "${other_comp_primary_nodes[@]}"; do
    original_announce_ip=$(echo "$node_info" | awk -F '#' '{print $1}')
    node_endpoint_with_port=$(echo "$node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $3}')
    node_endpoint=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $1}')
    node_port=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $2}')
    node_bus_port=$(echo "$node_info" | awk -F '@' '{print $2}')
    while true; do
      current_announce_ip=$(get_cluster_announce_ip "$node_endpoint" "$node_port")
      echo "original_announce_ip: $original_announce_ip, node_endpoint_with_port: $node_endpoint_with_port, current_announce_ip: $current_announce_ip"
      # if current_announce_ip is empty, we need to retry
      if is_empty "$current_announce_ip"; then
        sleep_when_ut_mode_false 3
        echo "current_announce_ip is empty, retry..."
        continue
      fi

      # if original_announce_ip not equal to current_announce_ip, we need to correct it with the current_announce_ip
      if ! equals "$original_announce_ip" "$current_announce_ip"; then
        # send cluster meet command to the primary node
        unset_xtrace_when_ut_mode_false
        if is_empty "$REDIS_DEFAULT_PASSWORD"; then
          meet_command="redis-cli -h $current_primary_endpoint -p $current_primary_port cluster meet $current_announce_ip $node_port $node_bus_port"
          logging_mask_meet_command="$meet_command"
        else
          meet_command="redis-cli -h $current_primary_endpoint -p $current_primary_port -a $REDIS_DEFAULT_PASSWORD cluster meet $current_announce_ip $node_port $node_bus_port"
          logging_mask_meet_command="${meet_command/$REDIS_DEFAULT_PASSWORD/********}"
        fi
        echo "check and correct other primary nodes meet command: $logging_mask_meet_command"
        if ! $meet_command
        then
            echo "Failed to meet the node $node_endpoint_with_port in check_and_correct_other_primary_nodes"
            shutdown_redis_server "$service_port"
            exit 1
        else
          echo "Meet the node $node_endpoint_with_port successfully with new announce ip $current_announce_ip..."
          break
        fi
        set_xtrace_when_ut_mode_false
      else
        echo "node_info $node_info is correct, skipping..."
        break
      fi
    done
  done
}

# get the current component nodes for scale out replica
get_current_comp_nodes_for_scale_out_replica() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  cluster_nodes_info=$(get_cluster_nodes_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info in get_current_comp_nodes_for_scale_out_replica: $command" >&2
    return 1
  fi

  # if the cluster_nodes_info contains only one line, it means that the cluster not be initialized
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -eq 1 ]; then
    echo "Cluster nodes info contains only one line, returning..."
    return
  fi

  current_comp_primary_node=()
  current_comp_other_nodes=()
  other_comp_primary_nodes=()
  other_comp_other_nodes=()

  # if the $CURRENT_SHARD_ADVERTISED_PORT is set, parse the advertised ports, advertised_ports records the advertised ports of the current shard
  # the value format of $CURRENT_SHARD_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  declare -A advertised_ports
  local using_advertised_ports=false
  if ! is_empty "$CURRENT_SHARD_ADVERTISED_PORT"; then
    using_advertised_ports=true
    IFS=',' read -ra ADDR <<< "$CURRENT_SHARD_ADVERTISED_PORT"
    for i in "${ADDR[@]}"; do
      port=$(echo $i | cut -d':' -f2)
      advertised_ports[$port]=1
    done
  fi

  # the output of line is like:
  # 1. using the pod fqdn as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  # 2. using the nodeport or lb ip as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 172.10.0.1:31000@31888,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  while read -r line; do
    # 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc
    node_ip_port_fields=$(echo "$line" | awk '{print $2}')
    # ip:port without bus port
    node_announce_ip_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}')
    node_bus_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $2}' | awk -F ',' '{print $1}')
    node_announce_ip=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}' | cut -d':' -f1)
    node_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}' | cut -d':' -f2)
    # redis-shard-sxj-0.redis-shard-sxj-headless.default.svc
    node_fqdn=$(echo "$line" | awk '{print $2}' | awk -F ',' '{print $2}')
    node_role=$(echo "$line" | awk '{print $3}')
    if $using_advertised_ports; then
      if [[ ${advertised_ports[$node_port]+_} ]]; then
        if contains "$node_role" "master"; then
          # example format using nodeport: 172.10.0.1#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc#172.10.0.1:31000@31888
          current_comp_primary_node+=("$node_announce_ip#$node_fqdn#$node_announce_ip_port@$node_bus_port")
        else
          current_comp_other_nodes+=("$node_announce_ip#$node_fqdn#$node_announce_ip_port@$node_bus_port")
        fi
      else
        if contains "$node_role" "master"; then
          other_comp_primary_nodes+=("$node_announce_ip#$node_fqdn#$node_announce_ip_port@$node_bus_port")
        else
          other_comp_other_nodes+=("$node_announce_ip#$node_fqdn#$node_announce_ip_port@$node_bus_port")
        fi
      fi
    else
      if contains "$node_fqdn" "$CURRENT_SHARD_COMPONENT_NAME"; then
        if contains "$node_role" "master"; then
          # example format using pod fqdn: 10.42.0.227#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc:6379@16379
          current_comp_primary_node+=("$node_announce_ip#$node_fqdn#$node_fqdn:$SERVICE_PORT@$node_bus_port")
        else
          current_comp_other_nodes+=("$node_announce_ip#$node_fqdn#$node_fqdn:$SERVICE_PORT@$node_bus_port")
        fi
      else
        if contains "$node_role" "master"; then
          other_comp_primary_nodes+=("$node_announce_ip#$node_fqdn#$node_fqdn:$SERVICE_PORT@$node_bus_port")
        else
          other_comp_other_nodes+=("$node_announce_ip#$node_fqdn#$node_fqdn:$SERVICE_PORT@$node_bus_port")
        fi
      fi
    fi
  done <<< "$cluster_nodes_info"

  echo "current_comp_primary_node: ${current_comp_primary_node[*]}"
  echo "current_comp_other_nodes: ${current_comp_other_nodes[*]}"
  echo "other_comp_primary_nodes: ${other_comp_primary_nodes[*]}"
  echo "other_comp_other_nodes: ${other_comp_other_nodes[*]}"
}

# scale out replica of redis cluster shard if needed
scale_redis_cluster_replica() {
  # Waiting for redis-server to start
  if check_redis_server_ready_with_retry ; then
    echo "Redis server is ready, continue to scale out replica..."
  else
    echo "Redis server is not ready, exit scale out replica..."
    exit 1
  fi

  # get the current component nodes for scale out replica
  target_node_name=$(min_lexicographical_order_pod "$CURRENT_SHARD_POD_NAME_LIST")
  if ! is_empty "$CURRENT_SHARD_PRIMARY_POD_NAME"; then
    target_node_name="$CURRENT_SHARD_PRIMARY_POD_NAME"
  fi
  target_node_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$target_node_name")
  if is_empty "$target_node_fqdn"; then
    echo "Error: Failed to get target node fqdn from current shard pod fqdn list: $CURRENT_SHARD_POD_FQDN_LIST. Exiting."
    exit 1
  fi
  # get the current component nodes for scale out replica
  get_current_comp_nodes_for_scale_out_replica "$target_node_fqdn" "$service_port"

  # check current_comp_primary_node is empty or not
  if [ ${#current_comp_primary_node[@]} -eq 0 ]; then
    echo "current_comp_primary_node is empty, skip scale out replica"
    exit 0
  fi

  # primary_node_info value format: cluster_announce_ip#pod_fqdn#endpoint:port@bus_port
  primary_node_info=${current_comp_primary_node[0]}
  primary_node_endpoint_with_port=$(echo "$primary_node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $3}')
  primary_node_endpoint=$(echo "$primary_node_endpoint_with_port" | awk -F ':' '{print $1}')
  primary_node_port=$(echo "$primary_node_endpoint_with_port" | awk -F ':' '{print $2}')
  primary_node_fqdn=$(echo "$primary_node_info" | awk -F '#' '{print $2}')
  primary_node_bus_port=$(echo "$primary_node_info" | awk -F '@' '{print $2}')
  if check_node_in_cluster_with_retry "$primary_node_endpoint" "$primary_node_port" "$CURRENT_POD_NAME"; then
    # if current pod is primary node, check the others primary info, if the others primary node info is expired, send cluster meet command again
    current_pod_fqdn_prefix="$CURRENT_POD_NAME.$CURRENT_SHARD_COMPONENT_NAME"
    if contains "$primary_node_fqdn" "$current_pod_fqdn_prefix"; then
      echo "Current pod $CURRENT_POD_NAME is primary node, check and correct other primary nodes..."
      check_and_correct_other_primary_nodes "$primary_node_endpoint" "$primary_node_port"
    fi
    echo "Node $CURRENT_POD_NAME is already in the cluster, skipping scale out replica..."
    exit 0
  fi

  # add the current node as a replica of the primary node
  primary_node_cluster_id=$(get_cluster_id_with_retry "$primary_node_endpoint" "$primary_node_port")
  status=$?
  if is_empty "$primary_node_cluster_id" || [ $status -ne 0 ]; then
    echo "Failed to get the cluster id of the primary node $primary_node_endpoint_with_port"
    shutdown_redis_server "$service_port"
    exit 1
  fi
  # current_node_with_port do not use advertised svc and port, because advertised svc and port are not ready when Pod is not Ready.
  current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$CURRENT_POD_NAME")
  current_node_with_port="$current_pod_fqdn:$service_port"
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    replicated_command="redis-cli --cluster add-node $current_node_with_port $primary_node_endpoint_with_port --cluster-slave --cluster-master-id $primary_node_cluster_id"
    logging_mask_replicated_command="$replicated_command"
  else
    replicated_command="redis-cli --cluster add-node $current_node_with_port $primary_node_endpoint_with_port --cluster-slave --cluster-master-id $primary_node_cluster_id -a $REDIS_DEFAULT_PASSWORD"
    logging_mask_replicated_command="${replicated_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "scale out replica replicated command: $logging_mask_replicated_command"
  replicated_output=$($replicated_command)
  replicated_exit_code=$?
  set_xtrace_when_ut_mode_false
  echo "Scale out replica replicated command result: $replicated_output"
  if [ $replicated_exit_code -ne 0 ]; then
    if contains "$replicated_output" "is not empty"; then
      echo "Replica is not empty, Either the node already knows other nodes (check with CLUSTER NODES) or contains some key in database 0"
    else
      echo "Failed to add the node $current_pod_fqdn to the cluster in scale_redis_cluster_replica, shutdown redis server"
      echo "Error message: $replicated_output"
      shutdown_redis_server "$service_port"
      exit 1
    fi
  fi

  # cluster meet the primary node until the current node is successfully added to the cluster
  while true; do
    if check_node_in_cluster "$primary_node_endpoint" "$primary_node_port" "$CURRENT_POD_NAME"; then
      echo "Node $CURRENT_POD_NAME is successfully added to the cluster."
      break
    fi
    primary_node_cluster_announce_ip=$(get_cluster_announce_ip_with_retry "$primary_node_endpoint" "$primary_node_port")
    # send cluster meet command to the primary node
    unset_xtrace_when_ut_mode_false
    if is_empty "$REDIS_DEFAULT_PASSWORD"; then
      meet_command="redis-cli cluster meet $primary_node_cluster_announce_ip $primary_node_port $primary_node_bus_port"
      logging_mask_meet_command="$meet_command"
    else
      meet_command="redis-cli -a $REDIS_DEFAULT_PASSWORD cluster meet $primary_node_cluster_announce_ip $primary_node_port $primary_node_bus_port"
      logging_mask_meet_command="${meet_command/$REDIS_DEFAULT_PASSWORD/********}"
    fi
    echo "scale out replica meet command: $logging_mask_meet_command"
    if ! $meet_command
    then
        echo "Failed to meet the node $primary_node_endpoint_with_port in scale_redis_cluster_replica, shutdown redis server"
        shutdown_redis_server "$service_port"
        exit 1
    fi
    set_xtrace_when_ut_mode_false
    sleep 3
  done
  exit 0
}

load_redis_template_conf() {
  echo "include $redis_template_conf" >> $redis_real_conf
}

build_redis_default_accounts() {
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$REDIS_REPL_PASSWORD"; then
    echo "masteruser $REDIS_REPL_USER" >> $redis_real_conf
    echo "masterauth $REDIS_REPL_PASSWORD" >> $redis_real_conf
    echo "user $REDIS_REPL_USER on +psync +replconf +ping >$REDIS_REPL_PASSWORD" >> $redis_acl_file
  fi
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    echo "protected-mode yes" >> $redis_real_conf
    echo "user default on >$REDIS_DEFAULT_PASSWORD ~* &* +@all " >> $redis_acl_file
  else
    echo "protected-mode no" >> $redis_real_conf
  fi
  set_xtrace_when_ut_mode_false
  echo "aclfile $redis_acl_file" >> $redis_real_conf
  echo "build redis default accounts succeeded!"
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

build_announce_ip_and_port() {
  # build announce ip and port according to whether the advertised svc is enabled
  if ! is_empty "$redis_advertised_svc_host_value" && ! is_empty "$redis_advertised_svc_port_value"; then
    echo "redis use advertised svc $redis_advertised_svc_host_value:$redis_advertised_svc_port_value to announce"
    {
      echo "replica-announce-port $redis_advertised_svc_port_value"
      echo "replica-announce-ip $redis_advertised_svc_host_value"
    } >> $redis_real_conf
  else
    current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$CURRENT_POD_NAME")
    if is_empty "$current_pod_fqdn"; then
      echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from current shard pod fqdn list: $CURRENT_SHARD_POD_FQDN_LIST. Exiting."
      exit 1
    fi
    echo "redis use kb pod fqdn $current_pod_fqdn to announce"
    echo "replica-announce-ip $current_pod_fqdn" >> $redis_real_conf
  fi
}

build_cluster_announce_info() {
  current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$CURRENT_POD_NAME")
  if is_empty "$current_pod_fqdn"; then
    echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from current shard pod fqdn list: $CURRENT_SHARD_POD_FQDN_LIST. Exiting."
    exit 1
  fi
  # build announce ip and port according to whether the advertised svc is enabled
  if ! is_empty "$redis_advertised_svc_host_value" && ! is_empty "$redis_advertised_svc_port_value" && ! is_empty "$redis_advertised_svc_bus_port_value"; then
    echo "redis cluster use advertised svc $redis_advertised_svc_host_value:$redis_advertised_svc_port_value@$redis_advertised_svc_bus_port_value to announce"
    {
      echo "cluster-announce-ip $redis_advertised_svc_host_value"
      echo "cluster-announce-port $redis_advertised_svc_port_value"
      echo "cluster-announce-bus-port $redis_advertised_svc_bus_port_value"
      echo "cluster-announce-hostname $current_pod_fqdn"
      echo "cluster-preferred-endpoint-type ip"
    } >> $redis_real_conf
  else
    echo "redis use kb pod fqdn $current_pod_fqdn to announce"
    {
      echo "cluster-announce-ip $CURRENT_POD_IP"
      echo "cluster-announce-hostname $current_pod_fqdn"
      echo "cluster-preferred-endpoint-type hostname"
    } >> $redis_real_conf
  fi
}

build_redis_cluster_service_port() {
  if ! is_empty "$SERVICE_PORT"; then
    service_port=$SERVICE_PORT
  fi
  if ! is_empty "$CLUSTER_BUS_PORT"; then
    cluster_bus_port=$CLUSTER_BUS_PORT
  fi
  {
    echo "port $service_port"
    echo "cluster-port $cluster_bus_port"
  } >> $redis_real_conf
}

parse_current_pod_advertised_svc_if_exist() {
  local pod_name="$CURRENT_POD_NAME"
  # The value format of CURRENT_SHARD_ADVERTISED_PORT and CURRENT_SHARD_ADVERTISED_BUS_PORT are "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  if is_empty "$CURRENT_SHARD_ADVERTISED_PORT" || is_empty "$CURRENT_SHARD_ADVERTISED_BUS_PORT"; then
    echo "Environment variable CURRENT_SHARD_ADVERTISED_PORT and CURRENT_SHARD_ADVERTISED_BUS_PORT not found. Ignoring."
    return 0
  fi

  local port
  local bus_port
  port=$(parse_advertised_port "$pod_name" "$CURRENT_SHARD_ADVERTISED_PORT")
  if [[ $? -ne 0 ]] || is_empty "$port"; then
    echo "Exiting due to error in CURRENT_SHARD_ADVERTISED_PORT."
    exit 1
  fi

  bus_port=$(parse_advertised_port "$pod_name" "$CURRENT_SHARD_ADVERTISED_BUS_PORT")
  if [[ $? -ne 0 ]] || is_empty "$bus_port"; then
    echo "Exiting due to error in CURRENT_SHARD_ADVERTISED_BUS_PORT."
    exit 1
  fi
  redis_advertised_svc_port_value="$port"
  redis_advertised_svc_bus_port_value="$bus_port"
  redis_advertised_svc_host_value="$CURRENT_POD_HOST_IP"
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

# build redis cluster configuration redis.conf
build_redis_conf() {
  load_redis_template_conf
  build_redis_cluster_service_port
  build_announce_ip_and_port
  build_cluster_announce_info
  rebuild_redis_acl_file
  build_redis_default_accounts
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

load_redis_cluster_common_utils
parse_current_pod_advertised_svc_if_exist
build_redis_conf
# TODO: move to memberJoin action in the future
scale_redis_cluster_replica &
start_redis_server
