#!/bin/sh
set -ex

# meta mysql connection parameters
# mysql_port="3306"
# mysql_username="$MYSQL_ROOT_USER"
# mysql_password="$MYSQL_ROOT_PASSWORD"

# topology_user="$ORC_TOPOLOGY_USER"
# topology_password="$ORC_TOPOLOGY_PASSWORD"

# component_name="$KB_COMP_NAME"

# register first pod to orchestrator
register_to_orchestrator() {
  local host_ip=$1

  local timeout=100
  local start_time=$(date +%s)
  local current_time

  endpoint=${ORC_ENDPOINTS%%:*}:${ORC_PORTS}

  local url="http://${endpoint}/api/discover/$host_ip/3306"
  local instance_url="http://${endpoint}/api/instance/$host_ip/3306"

  echo "register first mysql pod to orchestrator..."

  while true; do
    # register to Orchestrator
    echo "register $pod_name ($host_ip) to Orchestrator..."
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      echo "Timeout waiting for $host to become available."
      exit 1
    fi

    # url for orchestrator to discover this host_ip

    # send request to orchestrator for discovery
    response=$(curl -s -o /dev/null -w "%{http_code}" $url)
    if [ $response -eq 200 ]; then
        echo "response success"
        break
    fi
    sleep 5
  done
  echo "register $pod_name ($host_ip) to Orchestrator successful."
}

# Get the svc list from the environment variable
# and get the topology information of the current cluster from the orchestrator
main() {

  if [ -z "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" ] || [ -z "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST" ]; then
    echo "Error: Required environment variables KB_CLUSTER_COMPONENT_POD_NAME_LIST or KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are not set."
    exit 1
  fi

  old_ifs="$IFS"
  IFS=','
  pod_name_list=($KB_CLUSTER_COMPONENT_POD_NAME_LIST)
  pod_ip_list=($KB_CLUSTER_COMPONENT_POD_IP_LIST)
  IFS="$old_ifs"
  echo "pod_name_list: $pod_name_list"

  first_mysql_service_host_name=$(echo "${KB_CLUSTER_COMP_NAME}_MYSQL_0_SERVICE_HOST" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
  first_mysql_service_host=${!first_mysql_service_host_name}

  register_to_orchestrator "$first_mysql_service_host"

  echo "Initialization script completed！"
}
main

echo "completed"
