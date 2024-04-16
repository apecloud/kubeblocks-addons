#!/bin/bash

set -ex

# remove_replica_from_shard_if_need removes the current pod from the cluster if it is a replica
# TODO: remove it from preStop hook and it should be implemented in memberLeave lifecycleAction in KubeBlocks
remove_replica_from_shard_if_need() {
  # initialize the current pod info
  current_pod_name=$KB_POD_NAME
  current_pod_fqdn="$current_pod_name.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"

  # get the cluster nodes info
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(redis-cli -h "$current_pod_fqdn" cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h "$current_pod_fqdn" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  echo "Cluster nodes info: $cluster_nodes_info"

  # if the cluster_nodes_info contains only one line, it means that the cluster not be initialized
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -le 1 ]; then
    echo "Cluster nodes info contains only one line or is empty, returning..."
    return
  fi

  # get the current node role, if the current node is a slave, remove it from the cluster
  current_node_role=$(echo "$cluster_nodes_info" | grep "$current_pod_name" | awk '{print $3}')
  if [[ "$current_node_role" =~ "slave" ]]; then
    echo "Current node $current_pod_name is a slave, removing it from the cluster..."
    current_node_cluster_id=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $1}')
    current_node_ip_and_port="$current_pod_fqdn:$SERVICE_PORT"
    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      del_node_command="redis-cli --cluster del-node $current_node_ip_and_port $current_node_cluster_id"
    else
      del_node_command="redis-cli --cluster del-node $current_node_ip_and_port $current_node_cluster_id -a $REDIS_DEFAULT_PASSWORD"
    fi
    echo "Remove replica from shard executing command: $del_node_command"
    for ((i=1; i<=20; i++)); do
      if $del_node_command; then
        echo "Successfully removed replica from shard."
        break
      else
        echo "Failed to remove replica from shard. Retrying... (Attempt $i/20)"
        sleep $((RANDOM % 3 + 1))
      fi
    done

    if [ "$i" -eq 20 ]; then
      echo "Failed to remove replica from shard after 20 attempts."
      exit 1
    fi

    # check if the current node is removed from the cluster
    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      cluster_nodes_info=$(redis-cli -h "$current_pod_fqdn" cluster nodes)
    else
      cluster_nodes_info=$(redis-cli -h "$current_pod_fqdn" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
    fi
    echo "Cluster nodes info: $cluster_nodes_info"

    if [ "$(echo "$cluster_nodes_info" | wc -l)" -le 1 ]; then
      echo "successfully removed replica from shard."
      return
    else
      echo "Failed to remove replica from shard."
      exit 1
    fi
  else
    echo "Current node $current_pod_name is a master, no need to remove it from the cluster."
  fi
}

save_acl() {
  if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
    redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_DEFAULT_PASSWORD" acl save
  else
    redis-cli -h 127.0.0.1 -p 6379 acl save
  fi
}

save_acl
remove_replica_from_shard_if_need