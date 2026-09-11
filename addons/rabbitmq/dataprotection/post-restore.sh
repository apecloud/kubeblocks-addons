#!/bin/bash
set -Eeuo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/rabbitmq}"
cookie_file="${DATA_DIR}/.erlang.cookie"
if [ -r "${cookie_file}" ]; then
  export RABBITMQ_ERLANG_COOKIE
  RABBITMQ_ERLANG_COOKIE="$(cat "${cookie_file}")"
fi

: "${RABBITMQ_NODENAME:?RABBITMQ_NODENAME is required}"
: "${RABBITMQ_DEFAULT_USER:?RABBITMQ_DEFAULT_USER is required}"
: "${RABBITMQ_DEFAULT_PASS:?RABBITMQ_DEFAULT_PASS is required}"

echo "INFO: waiting for RabbitMQ node ${RABBITMQ_NODENAME} after restore"
rabbitmqctl --longnames -n "${RABBITMQ_NODENAME}" await_startup

user_exists() {
  rabbitmqctl --longnames -n "${RABBITMQ_NODENAME}" list_users --silent | awk '{print $1}' | grep -qx "${RABBITMQ_DEFAULT_USER}"
}

ensure_system_user() {
  local attempt=1
  while [ "${attempt}" -le 5 ]; do
    if user_exists; then
      echo "INFO: updating restored RabbitMQ system account ${RABBITMQ_DEFAULT_USER}"
      rabbitmqctl --longnames -n "${RABBITMQ_NODENAME}" change_password "${RABBITMQ_DEFAULT_USER}" "${RABBITMQ_DEFAULT_PASS}"
      return 0
    fi

    echo "INFO: creating restored RabbitMQ system account ${RABBITMQ_DEFAULT_USER}"
    if rabbitmqctl --longnames -n "${RABBITMQ_NODENAME}" add_user "${RABBITMQ_DEFAULT_USER}" "${RABBITMQ_DEFAULT_PASS}"; then
      return 0
    fi

    if user_exists; then
      echo "INFO: RabbitMQ system account ${RABBITMQ_DEFAULT_USER} appeared after concurrent create; updating password"
      rabbitmqctl --longnames -n "${RABBITMQ_NODENAME}" change_password "${RABBITMQ_DEFAULT_USER}" "${RABBITMQ_DEFAULT_PASS}"
      return 0
    fi

    echo "WARNING: system account create attempt ${attempt} failed; retrying" >&2
    sleep 2
    attempt=$((attempt + 1))
  done
  echo "ERROR: failed to create or update RabbitMQ system account ${RABBITMQ_DEFAULT_USER}" >&2
  return 1
}

ensure_system_user

rabbitmqctl --longnames -n "${RABBITMQ_NODENAME}" set_user_tags "${RABBITMQ_DEFAULT_USER}" administrator
rabbitmqctl --longnames -n "${RABBITMQ_NODENAME}" set_permissions -p / "${RABBITMQ_DEFAULT_USER}" ".*" ".*" ".*"
echo "INFO: RabbitMQ post-restore account reconciliation completed"
