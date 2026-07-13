#!/bin/sh
set -eu

: "${KB_ACCOUNT_NAME:?KB_ACCOUNT_NAME is required}"
: "${KB_ACCOUNT_PASSWORD:?KB_ACCOUNT_PASSWORD is required}"
: "${KB_ACCOUNT_STATEMENT:?KB_ACCOUNT_STATEMENT is required}"

# Match the literal controller template; account values arrive separately.
# shellcheck disable=SC2016
case "${KB_ACCOUNT_STATEMENT}" in
  'rabbitmqctl change_password ${KB_ACCOUNT_NAME} ${KB_ACCOUNT_PASSWORD}')
    rabbitmqctl -q change_password "${KB_ACCOUNT_NAME}" "${KB_ACCOUNT_PASSWORD}" >/dev/null
    rabbitmqctl -q authenticate_user "${KB_ACCOUNT_NAME}" "${KB_ACCOUNT_PASSWORD}" >/dev/null
    echo "RabbitMQ system account password synchronized."
    ;;
  *)
    echo "ERROR: unsupported account statement" >&2
    exit 1
    ;;
esac
