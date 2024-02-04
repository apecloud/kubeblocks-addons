#!/bin/bash
set -ex

# initialize the other component and pods info
init_other_component_pods_info() {
  local component="$1"
  local all_pod_ip_list="$2"
  local all_pod_name_list="$3"
  local all_component_list="$4"
  other_components=""
  other_component_pod_ips=""
  other_component_pod_names=""

  # filter out the components of the given component
  IFS=',' read -ra components <<< "$all_component_list"
  for comp in "${components[@]}"; do
    if [ "$comp" = "$component" ]; then
      continue
    fi
    other_components+=" $comp"
  done

  # filter out the pods of the given component
  IFS=',' read -ra pod_ips <<< "$all_pod_ip_list"
  IFS=',' read -ra pod_names <<< "$all_pod_name_list"
  for index in "${!pod_ips[@]}"; do
    if echo "${pod_names[$index]}" | grep -q "-$component-"; then
      continue
    fi
    other_component_pod_ips+=" ${pod_ips[$index]}"
    other_component_pod_names+=" ${pod_names[$index]}"
  done

  echo "other_components: $other_components"
  echo "other_component_pod_ips: $other_component_pod_ips"
  echo "other_component_pod_names: $other_component_pod_names"
}

# usage: parse_host_ip_from_built_in_envs <pod_name>
parse_host_ip_from_built_in_envs() {
  local given_pod_name="$1"
  local all_pod_name_list="$2"
  local all_pod_host_ip_list="$3"

  if [ -z "$all_pod_name_list" ] || [ -z "$all_pod_host_ip_list" ]; then
    echo "Error: Required environment variables all_pod_name_lis or all_pod_host_ip_list are not set."
    exit 1
  fi

  old_ifs="$IFS"
  IFS=','
  set -f
  pod_name_list="$all_pod_name_list"
  pod_ip_list="$all_pod_host_ip_list"
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

# usage: wait_random_time <max_time> <min_time>
wait_random_second() {
  local max_time="$1"
  local min_time="$2"
  local random_time=$((RANDOM % (max_time - min_time + 1) + min_time))
  echo "Sleeping for $random_time seconds"
  sleep "$random_time"
}

redis_cluster_check() {
    local -r check=$(redis-cli --cluster check "$1")
    if [[ $check =~ "All 16384 slots covered" ]]; then
        true
    else
        false
    fi
}

wait_for_dns_lookup() {
    local hostname="${1:?hostname is missing}"
    local retries="${2:-5}"
    local seconds="${3:-1}"
    check_host() {
        if [[ $(dns_lookup "$hostname") == "" ]]; then
            false
        else
            true
        fi
    }
    # Wait for the host to be ready
    retry_while "check_host ${hostname}" "$retries" "$seconds"
    dns_lookup "$hostname"
}

extract_ordinal_from_pod_name() {
  local pod_name="$1"
  local ordinal="${pod_name##*-}"
  echo "$ordinal"
}

extract_pod_name_prefix() {
  local pod_name="$1"
  # shellcheck disable=SC2001
  prefix=$(echo "$pod_name" | sed 's/-[0-9]\+$//')
  echo "$prefix"
}

is_redis_cluster_initialized() {
  if [ -z "$KB_CLUSTER_POD_IP_LIST" ]; then
    echo "Error: Required environment variable KB_CLUSTER_POD_IP_LIST is not set."
    exit 1
  fi
  local initialized="false"
  for pod_ip in $(echo "$KB_CLUSTER_POD_IP_LIST" | tr ',' ' '); do
    cluster_info=$(redis-cli -h "$pod_ip" -a "$REDIS_DEFAULT_PASSWORD" cluster info)
    echo "cluster_info $cluster_info"
    cluster_state=$(echo "$cluster_info" | grep -oP '(?<=cluster_state:)[^\s]+')
    if [ -z "$cluster_state" ] || [ "$cluster_state" == "ok" ]; then
      echo "Redis Cluster already initialized"
      initialized="true"
      break
    fi
  done
  [ "$initialized" = "true" ]
}

gen_initialize_redis_cluster_primary_node() {
  if [ -z "$KB_CLUSTER_POD_NAME_LIST" ]; then
    echo "Error: Required environment variable KB_CLUSTER_POD_NAME_LIST is not set."
    exit 1
  fi
  local cluster_nodes=()
  local port=$SERVICE_PORT
  for pod_name in $(echo "$KB_CLUSTER_POD_NAME_LIST" | tr ',' ' '); do
    pod_name_ordinal=$(extract_ordinal_from_pod_name "$pod_name")
    if [ "$pod_name_ordinal" -ne 0 ]; then
      continue
    fi
    pod_name_prefix=$(extract_pod_name_prefix "$pod_name")
    local pod_fqdn="$pod_name.$pod_name_prefix-headless"
    cluster_nodes+=(" $pod_fqdn:$port")
  done
  echo "${cluster_nodes[*]}"
}

gen_initialize_redis_cluster_secondary_nodes() {
  if [ -z "$KB_CLUSTER_POD_NAME_LIST" ]; then
    echo "Error: Required environment variable KB_CLUSTER_POD_NAME_LIST is not set."
    exit 1
  fi
  local cluster_nodes=()
  local port=$SERVICE_PORT
  for pod_name in $(echo "$KB_CLUSTER_POD_NAME_LIST" | tr ',' ' '); do
    pod_name_ordinal=$(extract_ordinal_from_pod_name "$pod_name")
    if [ "$pod_name_ordinal" -eq 0 ]; then
      continue
    fi
    pod_name_prefix=$(extract_pod_name_prefix "$pod_name")
    local pod_fqdn="$pod_name.$pod_name_prefix-headless"
    cluster_nodes+=(" $pod_fqdn:$port")
  done
  echo "${cluster_nodes[*]}"
}

initialize_or_scale_out_redis_cluster() {
    # TODO: remove random sleep, it's a workaround for the multi components initialization parallelism issue
    wait_random_second 10 1

    # if the cluster is not initialized, initialize it
    if ! is_redis_cluster_initialized; then
        echo "Redis Cluster not initialized, initializing..."
        # initialize the primary nodes
        primary_nodes=$(gen_initialize_redis_cluster_primary_node)
        if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
            initialize_command="redis-cli --cluster create $primary_nodes --cluster-replicas --cluster-yes"
        else
            initialize_command="redis-cli --cluster create $primary_nodes --cluster-replicas -a $REDIS_DEFAULT_PASSWORD --cluster-yes"
        fi
        yes yes | $initialize_command || true
        if redis_cluster_check "${primary_nodes[0]}"; then
            echo "Cluster correctly created"
        else
            echo "Failed to create Redis Cluster"
            slepp 600
            exit 1
        fi
        # initialize the secondary nodes
        secondary_nodes=$(gen_initialize_redis_cluster_secondary_nodes)
        for secondary_node in $secondary_nodes; do
            secondary_pod_name_prefix=$(extract_pod_name_prefix "$secondary_node")
            mapping_primary=$secondary_pod_name_prefix+"-0"
            if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
                redis-cli --cluster add-node 127.0.0.1:7006 127.0.0.1:7000 --cluster-slave --cluster-master-id 3c3a0c74aae0b56170ccb03a76b60cfe7dc1912e
                replicated_command="redis-cli --cluster add-node $node ${primary_nodes[0]}"
            else
                replicated_command="redis-cli --cluster add-node $node ${primary_nodes[0]} -a $REDIS_DEFAULT_PASSWORD"
            fi
            $add_node_command
        done
    else
        echo "Redis Cluster already initialized, scaling out..."
    fi
}

# main

initialize_or_scale_out_redis_cluster

sleep 600