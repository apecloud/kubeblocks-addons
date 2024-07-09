#!/bin/bash
set -ex

build_redis_twemproxy_conf() {
  ## check REDIS_SERVICE_NAMES and REDIS_SERVICE_PORTS env exist
  if [ -z "$REDIS_SERVICE_NAMES" ] || [ -z "$REDIS_SERVICE_PORTS" ]; then
    echo "REDIS_SERVICE_NAMES and REDIS_SERVICE_PORTS must be set"
    exit 1
  fi

  # Convert REDIS_SERVICE_NAMES and REDIS_SERVICE_PORTS to arrays
  IFS=',' read -r -a service_names_array <<< "$REDIS_SERVICE_NAMES"
  IFS=',' read -r -a service_ports_array <<< "$REDIS_SERVICE_PORTS"

  # Initialize servers variable
  servers=""

  # Iterate over service names and ports to build servers string
  for i in "${!service_names_array[@]}"; do
    service_name_entry="${service_names_array[$i]}"
    service_port_entry="${service_ports_array[$i]}"

    # Extract host and port
    service_host="${service_name_entry#*:}"
    service_port="${service_port_entry#*:}"

    # Append to servers string
    servers="$servers\n    - $service_host:$service_port:1"
  done

  # All the components of redis server password must be the same, So we find the first environment variable that starts with REDIS_DEFAULT_PASSWORD
  # Find the first environment variable that starts with REDIS_DEFAULT_PASSWORD
  REDIS_AUTH_PASSWORD=""
  for env_var in $(env); do
    if [[ $env_var == REDIS_DEFAULT_PASSWORD* ]]; then
      REDIS_AUTH_PASSWORD="${env_var#*=}"
      break
    fi
  done

  if [ -z "$REDIS_AUTH_PASSWORD" ]; then
    echo "No environment variable starting with REDIS_DEFAULT_PASSWORD found"
    exit 1
  fi

  # Create configuration file
  {
    echo "alpha:"
    echo "  listen: 0.0.0.0:22121"
    echo "  hash: fnv1a_64"
    echo "  distribution: ketama"
    echo "  auto_eject_hosts: true"
    echo "  redis: true"
    echo "  redis_auth: $REDIS_AUTH_PASSWORD"
    echo "  server_retry_timeout: 2000"
    echo "  server_failure_limit: 1"
    echo "  servers:"
    echo -e "$servers"
  } > /etc/proxy/nutcracker.conf
}

build_redis_twemproxy_conf
