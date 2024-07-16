#!/bin/sh
set -ex

convert_to_array() {
  var="$1"
  oldIFS="$IFS"
  IFS=','
  set -- $var
  IFS="$oldIFS"
  echo "$@"
}

build_redis_twemproxy_conf() {
  ## Check if required environment variables exist
  if [ -z "$REDIS_SERVICE_NAMES" ] || [ -z "$REDIS_SERVICE_PORTS" ]; then
    echo "REDIS_SERVICE_NAMES and REDIS_SERVICE_PORTS must be set"
    exit 1
  fi

  # Convert REDIS_SERVICE_NAMES and REDIS_SERVICE_PORTS to arrays
  # The format of REDIS_SERVICE_NAMES is "redis0:redis-redis0-redis,redis1:redis-redis1-redis" when there are multiple redis server shards
  # The format of REDIS_SERVICE_PORTS is "redis0:6379,redis1:6379" when there are multiple redis server shards
  # The format of REDIS_SERVICE_NAMES is "redis-redis0-redis" when there is only one redis server shard
  # The format of REDIS_SERVICE_PORTS is "6379" when there is only one redis server shard
  service_names_array=$(convert_to_array "$REDIS_SERVICE_NAMES")
  service_ports_array=$(convert_to_array "$REDIS_SERVICE_PORTS")
  echo "service_names_array: $service_names_array, service_ports_array: $service_ports_array"

  # Initialize servers configuration
  servers=""
  # shellcheck disable=SC2046
  if [ $(echo "$service_names_array" | wc -w) -eq 1 ] && [ $(echo "$service_ports_array" | wc -w) -eq 1 ]; then
    service_name="${service_names_array#*:}"
    service_port="${service_ports_array#*:}"
    servers="    - $service_name:$service_port:1"
  else
    echo "service_names_array: $service_names_array, service_ports_array: $service_ports_array"
    for service_name_entry in $service_names_array; do
      # Extract key and value from service_name_entry
      service_name_key="${service_name_entry%%:*}"
      service_name_value="${service_name_entry#*:}"

      echo "service_name_key: $service_name_key, service_name_value: $service_name_value"
      # Find the corresponding port entry
      for service_port_entry in $service_ports_array; do
        service_port_key="${service_port_entry%%:*}"
        service_port_value="${service_port_entry#*:}"
        echo "service_port_key: $service_port_key, service_port_value: $service_port_value"

        if [ "$service_name_key" = "$service_port_key" ]; then
          # Append to servers string
          if [ -n "$servers" ]; then
            servers="$servers\n"
          fi
          servers="$servers    - $service_name_value:$service_port_value:1"
        fi
      done
    done
  fi

  # All the components' password of redis server must be the same, So we find the first environment variable that starts with REDIS_DEFAULT_PASSWORD
  REDIS_AUTH_PASSWORD=""
  last_value=""
  set +x
  for env_var in $(env | grep -E '^REDIS_DEFAULT_PASSWORD'); do
    value="${env_var#*=}"
    if [ -n "$value" ]; then
      if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
        echo "Error conflicting env $env_var of redis password values found, all the components' password of redis server must be the same."
        exit 1
      fi
      last_value="$value"
    fi
  done
  REDIS_AUTH_PASSWORD="$last_value"

  if [ -z "$REDIS_AUTH_PASSWORD" ]; then
    echo "No environment variable starting with REDIS_DEFAULT_PASSWORD found"
    exit 1
  fi

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
    printf "%b" "$servers"
  } > /etc/proxy/nutcracker.conf
  set -x
  echo "build redis twemproxy conf done!"
}

build_redis_twemproxy_conf