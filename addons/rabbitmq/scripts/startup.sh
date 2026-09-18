#!/bin/sh
set -e

DATA_DIR="${RABBITMQ_DATA_DIR:-/var/lib/rabbitmq}"

write_default_user_config() {
  cat > /etc/rabbitmq/conf.d/10-kubeblocks-default-user.conf <<EOF
default_user = ${RABBITMQ_DEFAULT_USER}
default_pass = ${RABBITMQ_DEFAULT_PASS}
EOF
}

# if test by shellspec include, just return 0
if [ "${__SOURCED__:+x}" ]; then
  return 0
fi

if [ ! -f "$DATA_DIR/enabled_plugins" ]; then
  cp /etc/rabbitmq/enabled_plugins "$DATA_DIR/enabled_plugins"
fi

cp /root/erlang.cookie "$DATA_DIR/.erlang.cookie"
chown rabbitmq:rabbitmq "$DATA_DIR/.erlang.cookie"
chmod 400 "$DATA_DIR/.erlang.cookie"

write_default_user_config

if [ "${TLS_ENABLED:-false}" = "true" ]; then
  : "${TLS_MOUNT_PATH:?TLS_MOUNT_PATH is required when TLS is enabled}"
  for cert_file in ca.crt tls.crt tls.key; do
    if [ ! -r "${TLS_MOUNT_PATH}/${cert_file}" ]; then
      echo "ERROR: TLS is enabled but ${TLS_MOUNT_PATH}/${cert_file} is not readable" >&2
      exit 1
    fi
  done
fi

exec /opt/rabbitmq/sbin/rabbitmq-server
