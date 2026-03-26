#!/bin/sh
set -eu

POD_NAME="${CURRENT_POD_NAME:-}"
if [ -z "${POD_NAME}" ]; then
  echo "CURRENT_POD_NAME is required" >&2
  exit 1
fi

POD_BASENAME="${POD_NAME%-*}"
POD_ORDINAL="${POD_NAME##*-}"

if [ "${POD_ORDINAL}" = "0" ]; then
  BOOTSTRAP_ROLE="primary"
  STANDBY_HOST="${POD_BASENAME}-1"
else
  BOOTSTRAP_ROLE="standby"
  STANDBY_HOST="${POD_BASENAME}-0"
fi

HEADLESS_SERVICE_NAME="${POD_BASENAME}-headless"
REMOTES_API_PORT="${REMOTES_API_PORT:-50051}"

sed \
  -e "s|\${BOOTSTRAP_ROLE}|${BOOTSTRAP_ROLE}|g" \
  -e "s|\${STANDBY_HOST}|${STANDBY_HOST}|g" \
  -e "s|\${HEADLESS_SERVICE_NAME}|${HEADLESS_SERVICE_NAME}|g" \
  -e "s|\${REMOTES_API_PORT}|${REMOTES_API_PORT}|g" \
  /config/config.yaml > /tmp/config.yaml

dolt sql-server --config /tmp/config.yaml &
child_pid=$!

term_handler() {
  kill -TERM "${child_pid}" 2>/dev/null || true
}

trap term_handler TERM INT
wait "${child_pid}"
