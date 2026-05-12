#!/bin/sh
set -eu

NUTCRACKER_CONF="${NUTCRACKER_CONF:-/etc/proxy/nutcracker.conf}"
NUTCRACKER_PID_FILE="${NUTCRACKER_PID_FILE:-/tmp/nutcracker.pid}"
NUTCRACKER_ARGS="${NUTCRACKER_ARGS:-}"
SENTINEL_POLL_INTERVAL_SECONDS="${TWEMPROXY_SENTINEL_POLL_INTERVAL_SECONDS:-1}"
LAST_MASTER_ADDR=""
NUTCRACKER_PID=""

first_value() {
  value="${1:-}"
  value="${value%%,*}"
  case "$value" in
    *:*) value="${value#*:}" ;;
  esac
  printf '%s' "$value"
}

default_master_name() {
  redis_service="$(first_value "${REDIS_SERVICE_NAMES:-}")"
  if [ -n "$redis_service" ]; then
    printf '%s' "${redis_service%-redis}"
  fi
}

query_sentinel_master() {
  sentinel_host="$1"
  sentinel_port="$2"
  master_name="$3"
  master_len=${#master_name}

  {
    printf '*3\r\n'
    printf '$8\r\nSENTINEL\r\n'
    printf '$23\r\nget-master-addr-by-name\r\n'
    printf '$%s\r\n%s\r\n' "$master_len" "$master_name"
  } | nc -w 2 "$sentinel_host" "$sentinel_port" 2>/dev/null | awk '
    /^\$/ {
      if (getline value) {
        gsub(/\r/, "", value)
        fields++
        if (fields == 1) {
          host = value
        } else if (fields == 2) {
          print host ":" value
          exit
        }
      }
    }
  '
}

start_nutcracker() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) starting nutcracker"
  # shellcheck disable=SC2086
  nutcracker -c "$NUTCRACKER_CONF" -v 4 -m 16384 -p "$NUTCRACKER_PID_FILE" $NUTCRACKER_ARGS &
  NUTCRACKER_PID="$!"
}

stop_nutcracker() {
  if [ -n "${NUTCRACKER_PID:-}" ] && kill -0 "$NUTCRACKER_PID" 2>/dev/null; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) stopping nutcracker pid=$NUTCRACKER_PID"
    kill "$NUTCRACKER_PID" 2>/dev/null || true
    wait "$NUTCRACKER_PID" 2>/dev/null || true
  fi
  NUTCRACKER_PID=""
}

restart_nutcracker() {
  stop_nutcracker
  start_nutcracker
}

shutdown() {
  stop_nutcracker
  exit 0
}

trap shutdown TERM INT

sentinel_host="$(first_value "${REDIS_SENTINEL_SERVICE_HOSTS:-}")"
sentinel_port="$(first_value "${REDIS_SENTINEL_SERVICE_PORTS:-}")"
sentinel_master_name="${SENTINEL_MASTER_NAME:-$(default_master_name)}"

if [ -z "$sentinel_host" ] || [ -z "$sentinel_port" ] || [ -z "$sentinel_master_name" ]; then
  echo "Fake Sentinel service is not configured; starting nutcracker without master watcher"
  exec nutcracker -c "$NUTCRACKER_CONF" -v 4 -m 16384
fi

if ! command -v nc >/dev/null 2>&1; then
  echo "nc is required for twemproxy master watcher but was not found"
  exit 1
fi

echo "twemproxy master watcher enabled: sentinel=${sentinel_host}:${sentinel_port}, master=${sentinel_master_name}, interval=${SENTINEL_POLL_INTERVAL_SECONDS}s"
LAST_MASTER_ADDR="$(query_sentinel_master "$sentinel_host" "$sentinel_port" "$sentinel_master_name" || true)"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) initial Fake Sentinel master=${LAST_MASTER_ADDR:-unknown}"

start_nutcracker

while true; do
  if [ -n "${NUTCRACKER_PID:-}" ] && ! kill -0 "$NUTCRACKER_PID" 2>/dev/null; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) nutcracker exited; restarting"
    start_nutcracker
  fi

  current_master_addr="$(query_sentinel_master "$sentinel_host" "$sentinel_port" "$sentinel_master_name" || true)"
  if [ -n "$current_master_addr" ]; then
    if [ -n "$LAST_MASTER_ADDR" ] && [ "$current_master_addr" != "$LAST_MASTER_ADDR" ]; then
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Fake Sentinel master changed: ${LAST_MASTER_ADDR} -> ${current_master_addr}; restarting nutcracker"
      LAST_MASTER_ADDR="$current_master_addr"
      restart_nutcracker
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) nutcracker restarted after master change"
    else
      LAST_MASTER_ADDR="$current_master_addr"
    fi
  fi

  sleep "$SENTINEL_POLL_INTERVAL_SECONDS"
done
