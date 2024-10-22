#!/bin/bash

# shellcheck disable=SC2154
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
 # when running in non-unit test mode, set the options "set -ex".
 set -ex;
}

check_env_variables() {
  local required_vars=("zookeeperServers" "POD_NAME" "clusterName" "webServiceUrl" "brokerServiceUrl")
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
      echo "Error: $var environment variable is not set, Please set the $var environment variable and try again."
      exit 1
    fi
  done
}

wait_for_zookeeper() {
  local zk_servers="$1"
  local zk_domain="${zk_servers%%:*}"

  echo "Waiting for Zookeeper at ${zk_servers} to be ready..."
  until zkURL=${zk_servers} python3 /kb-scripts/zookeeper.py get /; do
    sleep 1
  done
  echo "Zookeeper is ready"
}

check_cluster_initialized() {
  local zk_servers="$1"
  local cluster_name="$2"

  if zkURL=${zk_servers} python3 /kb-scripts/zookeeper.py get /admin/clusters/${cluster_name}; then
    echo "Cluster ${cluster_name} is already initialized"
    return 0
  else
    echo "Cluster ${cluster_name} is not initialized"
    return 1
  fi
}

wait_for_cluster_metadata() {
  local zk_servers="$1"
  local cluster_name="$2"

  echo "Waiting for cluster metadata initialization..."
  until zkURL=${zk_servers} python3 /kb-scripts/zookeeper.py get /admin/clusters/${cluster_name}; do
    echo "Waiting for cluster metadata initialization..."
    sleep 1
  done
  echo "Cluster metadata initialized"
}

initialize_cluster_metadata() {
  local cluster_name="$1"
  local zk_servers="$2"
  local web_service_url="$3"
  local broker_service_url="$4"

  echo "Initializing cluster metadata for cluster: ${cluster_name}"
  bin/pulsar initialize-cluster-metadata \
    --cluster ${cluster_name} \
    --zookeeper ${zk_servers} \
    --configuration-store ${zk_servers} \
    --web-service-url ${web_service_url} \
    --broker-service-url ${broker_service_url}
}

init_broker() {
  check_env_variables
  wait_for_zookeeper "$zookeeperServers"

  # only initialize the cluster if this is the first broker pod
  local idx=${POD_NAME##*-}
  if [ $idx -ne 0 ]; then
    wait_for_cluster_metadata "$zookeeperServers" "$clusterName"
    echo "Cluster already initialized" && quit_script
  fi

  if check_cluster_initialized "$zookeeperServers" "$clusterName"; then
    echo "Cluster already initialized" && quit_script
  fi

  initialize_cluster_metadata "$clusterName" "$zookeeperServers" "$webServiceUrl" "$brokerServiceUrl"
  quit_script
}

quit_script() {
  (curl -sf -XPOST http://127.0.0.1:15020/quitquitquit || true) && exit 0
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
init_broker