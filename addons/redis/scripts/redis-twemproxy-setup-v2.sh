#!/bin/sh
set -ex

build_redis_twemproxy_conf() {
  ## check REDIS_SERVICE_NAME and REDIS_SERVICE_PORT env exist
  if [ -z "$REDIS_SERVICE_NAME" ] || [ -z "$REDIS_SERVICE_PORT" ]; then
    echo "REDIS_SERVICE_NAME and REDIS_SERVICE_PORT must be set"
    exit 1
  fi

  echo "alpha:" > /etc/proxy/nutcracker.conf
  # shellcheck disable=SC2129
  echo "  listen: 0.0.0.0:22121" >> /etc/proxy/nutcracker.conf
  echo "  hash: fnv1a_64" >> /etc/proxy/nutcracker.conf
  echo "  distribution: ketama" >> /etc/proxy/nutcracker.conf
  echo "  auto_eject_hosts: true" >> /etc/proxy/nutcracker.conf
  echo "  redis: true" >> /etc/proxy/nutcracker.conf
  echo "  redis_auth: $REDIS_DEFAULT_PASSWORD" >> /etc/proxy/nutcracker.conf
  echo "  server_retry_timeout: 2000" >> /etc/proxy/nutcracker.conf
  echo "  server_failure_limit: 1" >> /etc/proxy/nutcracker.conf
  echo "  servers:" >> /etc/proxy/nutcracker.conf
  echo "    - $REDIS_SERVICE_NAME:$REDIS_SERVICE_PORT:1 $KB_CLUSTER_NAME" >> /etc/proxy/nutcracker.conf
}

build_redis_twemproxy_conf
