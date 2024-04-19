#!/bin/sh
set -ex

# meta mysql connection parameters
mysql_port="3306"
mysql_username="$MYSQL_ROOT_USER"
mysql_password="$MYSQL_ROOT_PASSWORD"

topology_user="$ORC_TOPOLOGY_USER"
topology_password="$ORC_TOPOLOGY_PASSWORD"



replica_count="$KB_REPLICA_COUNT"
cluster_component_pod_name="$KB_CLUSTER_COMP_NAME"
component_name="$KB_COMP_NAME"



# register first pod to orchestrator
forget_from_orchestrator() {
  local host_ip=$1

  endpoint=${ORC_ENDPOINTS%%:*}:${ORC_PORTS}

  local url="http://${endpoint}/api/forget/$host_ip/3306"

  # send request to orchestrator for discovery
  /scripts/orchestrator-client -c forget -i ${endpoint}:3306
}

# Get the svc list from the environment variable
# and get the topology information of the current cluster from the orchestrator
main() {
  last_digit=${KB_POD_NAME##*-}
  mysql_host_name=MYSQL_ORDINAL_HOST_${last_digit}
  HOSTIP=${!mysql_host_name}
  forget_from_orchestrator "$HOSTIP"
}
main

