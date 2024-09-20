#!/bin/bash

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

load_redis_cluster_common_utils() {
  # the common.sh and redis-cluster-common.sh scripts are defined in the redis cluster scripts template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/common.sh"
  redis_cluster_common_library_file="/scripts/redis-cluster-common.sh"
  source "${kblib_common_library_file}"
  source "${redis_cluster_common_library_file}"
}

# remove_replica_from_shard_if_need removes the current pod from the cluster if it is a replica
# TODO: remove it from preStop hook and it should be implemented in memberLeave lifecycleAction in KubeBlocks
remove_replica_from_shard_if_need() {
  # initialize the current pod info
  current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$CURRENT_POD_NAME")
  if is_empty "$current_pod_fqdn"; then
    echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from current shard pod fqdn list: $CURRENT_SHARD_POD_FQDN_LIST. Exiting."
    exit 1
  fi

  # get the cluster nodes info
  cluster_nodes_info=$(get_cluster_nodes_info_with_retry "$current_pod_fqdn" "$service_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info in remove_replica_from_shard_if_need" >&2
    return 1
  fi
  echo "Cluster nodes info: $cluster_nodes_info"

  # if the cluster_nodes_info contains only one line, it means that the cluster not be initialized
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -le 1 ]; then
    echo "Cluster nodes info contains only one line or is empty, returning..."
    return
  fi

  # get the current node role, if the current node is a slave, remove it from the cluster
  current_node_role=$(echo "$cluster_nodes_info" | grep "$CURRENT_POD_NAME" | awk '{print $3}')
  if contains "$current_node_role" "slave"; then
    echo "Current node $CURRENT_POD_NAME is a slave, removing it from the cluster..."
    current_node_cluster_id=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $1}')
    current_node_ip_and_port=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $2}' | cut -d'@' -f1)
    unset_xtrace_when_ut_mode_false
    if is_empty "$REDIS_DEFAULT_PASSWORD"; then
      del_node_command="redis-cli --cluster del-node $current_node_ip_and_port $current_node_cluster_id"
      logging_mask_del_node_command="$del_node_command"
    else
      del_node_command="redis-cli --cluster del-node $current_node_ip_and_port $current_node_cluster_id -a $REDIS_DEFAULT_PASSWORD"
      logging_mask_del_node_command="${del_node_command/$REDIS_DEFAULT_PASSWORD/********}"
    fi
    echo "remove replica from shard executing command: $logging_mask_del_node_command"
    for ((i=1; i<=20; i++)); do
      if $del_node_command; then
        echo "Successfully removed replica from shard."
        break
      else
        echo "Failed to remove replica from shard. Retrying... (Attempt $i/20)"
        sleep $((RANDOM % 3 + 1))
      fi
    done
    set_xtrace_when_ut_mode_false

    if [ "$i" -eq 20 ]; then
      echo "Failed to remove replica from shard after 20 attempts."
      exit 1
    fi

    # check if the current node is removed from the cluster
    cluster_nodes_info=$(get_cluster_nodes_info "$current_pod_fqdn" "$service_port")
    status=$?
    if [ $status -ne 0 ]; then
      echo "Failed to get cluster nodes info in remove_replica_from_shard_if_need" >&2
      exit 1
    fi

    if [ "$(echo "$cluster_nodes_info" | wc -l)" -le 1 ]; then
      echo "successfully removed replica from shard."
      return
    else
      echo "Failed to remove replica from shard."
      exit 1
    fi
  else
    echo "Current node $CURRENT_POD_NAME is a master, no need to remove it from the cluster."
  fi
}

acl_save_before_stop() {
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    acl_save_command="redis-cli -h 127.0.0.1 -p 6379 -a $REDIS_DEFAULT_PASSWORD acl save"
    logging_mask_acl_save_command="${acl_save_command/$REDIS_DEFAULT_PASSWORD/********}"
  else
    acl_save_command="redis-cli -h 127.0.0.1 -p 6379 acl save"
    logging_mask_acl_save_command="$acl_save_command"
  fi
  echo "acl save command: $logging_mask_acl_save_command"
  if output=$($acl_save_command 2>&1); then
    echo "acl save command executed successfully: $output"
  else
    echo "failed to execute acl save command: $output"
    exit 1
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

load_redis_cluster_common_utils
acl_save_before_stop
remove_replica_from_shard_if_need