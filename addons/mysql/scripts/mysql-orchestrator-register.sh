#!/bin/sh
set -ex

# register a mysql instance to orchestrator
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

# register the first MySQL instance to Orchestrator,
# and Orchestrator will obtain the entire MySQL cluster topology info from this instance.
register_first_mysql_instance() {

  # get first MySQL instance host name.
  first_mysql_service_host_name=$(echo "${KB_CLUSTER_COMP_NAME}_MYSQL_0_SERVICE_HOST" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
  first_mysql_service_host=${!first_mysql_service_host_name}

  register_to_orchestrator "$first_mysql_service_host"

  echo "Initialization script completed！"
}

register_first_mysql_instance
