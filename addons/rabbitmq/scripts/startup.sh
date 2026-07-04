#!/bin/sh
set -e

DATA_DIR="${RABBITMQ_DATA_DIR:-/var/lib/rabbitmq}"

write_default_user_config() {
  cat > /etc/rabbitmq/conf.d/10-kubeblocks-default-user.conf <<EOF
default_user = ${RABBITMQ_DEFAULT_USER}
default_pass = ${RABBITMQ_DEFAULT_PASS}
EOF
}

sync_default_user_password() {
  if [ -z "${RABBITMQ_DEFAULT_USER:-}" ] || [ -z "${RABBITMQ_DEFAULT_PASS:-}" ]; then
    echo "ERROR: RABBITMQ_DEFAULT_USER and RABBITMQ_DEFAULT_PASS are required" >&2
    return 1
  fi

  rabbitmq-diagnostics -q ping >/dev/null 2>&1 || return 1

  if rabbitmqctl -q authenticate_user "$RABBITMQ_DEFAULT_USER" "$RABBITMQ_DEFAULT_PASS" >/dev/null 2>&1; then
    echo "RabbitMQ default user password is already synchronized."
    return 0
  fi

  if rabbitmqctl -q list_users | awk '{print $1}' | grep -Fxq "$RABBITMQ_DEFAULT_USER"; then
    rabbitmqctl -q change_password "$RABBITMQ_DEFAULT_USER" "$RABBITMQ_DEFAULT_PASS" >/dev/null
    echo "RabbitMQ default user password synchronized."
    return 0
  fi

  return 1
}

sync_default_user_password_until_ready() {
  attempts="${RABBITMQ_PASSWORD_SYNC_ATTEMPTS:-60}"
  interval="${RABBITMQ_PASSWORD_SYNC_INTERVAL_SECONDS:-2}"
  i=0

  while [ "$i" -lt "$attempts" ]; do
    if sync_default_user_password; then
      return 0
    fi
    i=$((i + 1))
    sleep "$interval"
  done

  echo "WARN: RabbitMQ default user password sync did not complete before timeout" >&2
  return 1
}

start_default_user_password_sync() {
  (
    set +e
    sync_default_user_password_until_ready
  ) &
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

start_default_user_password_sync

exec /opt/rabbitmq/sbin/rabbitmq-server
