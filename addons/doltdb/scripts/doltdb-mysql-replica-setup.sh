#!/bin/sh
set -eu

: "${DOLT_MYSQL_REPLICA_REQUIRED:=false}"
: "${DOLT_MYSQL_REPLICA_SETUP_TIMEOUT_SECONDS:=300}"
: "${DOLT_MYSQL_REPLICA_SETUP_POLL_SECONDS:=2}"
: "${DOLT_MYSQL_REPLICA_STATUS_POLL_SECONDS:=$DOLT_MYSQL_REPLICA_SETUP_POLL_SECONDS}"
: "${DOLT_SQL_HOST:=127.0.0.1}"
: "${DOLT_SQL_PORT:=3306}"

die() {
  echo "$*" >&2
  exit 1
}

is_positive_integer() {
  case "$1" in
    ""|*[!0-9]*|0) return 1 ;;
    *) return 0 ;;
  esac
}

sql_escape() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}

run_local_sql_query() {
  query="$1"
  result_format="${2:-}"
  set -- \
    dolt \
    --host="$DOLT_SQL_HOST" \
    --port="$DOLT_SQL_PORT" \
    --user=root \
    --password="${DOLT_ROOT_PASSWORD:?DOLT_ROOT_PASSWORD is required}"
  if [ "${TLS_ENABLED:-false}" = "true" ]; then
    tls_ca="${DOLT_TLS_CA_FILE:-${TLS_MOUNT_PATH:-/etc/pki/tls}/ca.crt}"
    export SSL_CERT_FILE="$tls_ca"
  else
    set -- "$@" --no-tls
  fi
  if [ -n "$result_format" ]; then
    "$@" sql --query="$query" --result-format="$result_format"
  else
    "$@" sql --query="$query"
  fi
}

run_local_sql_file() {
  sql_file="$1"
  set -- \
    dolt \
    --host="$DOLT_SQL_HOST" \
    --port="$DOLT_SQL_PORT" \
    --user=root \
    --password="${DOLT_ROOT_PASSWORD:?DOLT_ROOT_PASSWORD is required}"
  if [ "${TLS_ENABLED:-false}" = "true" ]; then
    tls_ca="${DOLT_TLS_CA_FILE:-${TLS_MOUNT_PATH:-/etc/pki/tls}/ca.crt}"
    export SSL_CERT_FILE="$tls_ca"
  else
    set -- "$@" --no-tls
  fi
  "$@" sql <"$sql_file"
}

wait_for_doltdb() {
  deadline="$1"
  while [ "$(date +%s)" -le "$deadline" ]; do
    if run_local_sql_query "SELECT 1;" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$DOLT_MYSQL_REPLICA_SETUP_POLL_SECONDS"
  done
  die "timed out waiting for local Dolt SQL server"
}

replica_status_value() {
  key="$1"
  status="$2"
  printf '%s\n' "$status" | awk -v key="$key" '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      prefix = key ":"
      if (index(line, prefix) == 1) {
        value = substr(line, length(prefix) + 1)
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  '
}

first_replica_status_value() {
  status="$1"
  shift
  for key do
    value="$(replica_status_value "$key" "$status")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

is_replica_thread_running() {
  case "$1" in
    Yes|yes|YES|Running|running|RUNNING|On|on|ON|true|TRUE|1)
      return 0
      ;;
  esac
  return 1
}

summarize_replica_status() {
  status="$1"
  io_running="$(first_replica_status_value "$status" Replica_IO_Running Slave_IO_Running IO_Running || true)"
  sql_running="$(first_replica_status_value "$status" Replica_SQL_Running Slave_SQL_Running SQL_Running || true)"
  io_error="$(first_replica_status_value "$status" Last_IO_Error Last_Error || true)"
  sql_error="$(first_replica_status_value "$status" Last_SQL_Error Last_Error || true)"

  printf 'Replica_IO_Running=%s Replica_SQL_Running=%s Last_IO_Error=%s Last_SQL_Error=%s\n' \
    "${io_running:-unknown}" \
    "${sql_running:-unknown}" \
    "${io_error:-none}" \
    "${sql_error:-none}"
}

replica_status_ready() {
  status="$1"
  io_running="$(first_replica_status_value "$status" Replica_IO_Running Slave_IO_Running IO_Running || true)"
  sql_running="$(first_replica_status_value "$status" Replica_SQL_Running Slave_SQL_Running SQL_Running || true)"

  if is_replica_thread_running "$io_running" && is_replica_thread_running "$sql_running"; then
    return 0
  fi

  return 1
}

show_replica_status() {
  run_local_sql_query "SHOW REPLICA STATUS;" vertical
}

wait_for_mysql_replica() {
  deadline="$1"
  last_status=""

  while [ "$(date +%s)" -le "$deadline" ]; do
    if status="$(show_replica_status 2>&1)"; then
      last_status="$status"
      if replica_status_ready "$status"; then
        echo "Dolt MySQL replication is running: $(summarize_replica_status "$status")"
        return 0
      fi
      echo "Dolt MySQL replication is not ready yet: $(summarize_replica_status "$status")"
    else
      last_status="$status"
      echo "SHOW REPLICA STATUS failed while waiting for MySQL-source replication: ${status}"
    fi
    sleep "$DOLT_MYSQL_REPLICA_STATUS_POLL_SECONDS"
  done

  echo "timed out waiting for Dolt MySQL-source replication to run"
  if [ -n "$last_status" ]; then
    echo "last observed replica status: $(summarize_replica_status "$last_status")"
  fi
  exit 1
}

validate_replication_filter() {
  filter="$1"
  case "$filter" in
    *";"* )
      die "DOLT_MYSQL_REPLICATION_FILTER must not contain semicolons"
      ;;
  esac
}

configure_mysql_replica() {
  : "${DOLT_MYSQL_SOURCE_HOST:?DOLT_MYSQL_SOURCE_HOST is required}"
  : "${DOLT_MYSQL_SOURCE_PORT:?DOLT_MYSQL_SOURCE_PORT is required}"
  : "${DOLT_MYSQL_SOURCE_USER:?DOLT_MYSQL_SOURCE_USER is required}"
  : "${DOLT_MYSQL_SOURCE_PASSWORD:?DOLT_MYSQL_SOURCE_PASSWORD is required}"
  : "${DOLT_MYSQL_REPLICA_SERVER_ID:?DOLT_MYSQL_REPLICA_SERVER_ID is required}"

  is_positive_integer "$DOLT_MYSQL_SOURCE_PORT" || die "DOLT_MYSQL_SOURCE_PORT must be a positive integer"
  is_positive_integer "$DOLT_MYSQL_REPLICA_SERVER_ID" || die "DOLT_MYSQL_REPLICA_SERVER_ID must be a positive integer"

  filter="${DOLT_MYSQL_REPLICATION_FILTER:-}"
  validate_replication_filter "$filter"

  echo "configuring Dolt as MySQL replica from ${DOLT_MYSQL_SOURCE_HOST}:${DOLT_MYSQL_SOURCE_PORT}"
  deadline="$(($(date +%s) + DOLT_MYSQL_REPLICA_SETUP_TIMEOUT_SECONDS))"
  wait_for_doltdb "$deadline"

  tmp_dir="${TMPDIR:-/tmp}"
  tmp_sql="$(mktemp "${tmp_dir%/}/doltdb-mysql-replica.XXXXXX")" || die "failed to create temporary SQL file"
  chmod 600 "$tmp_sql"
  trap 'rm -f "$tmp_sql"' EXIT HUP INT TERM

  {
    printf "CHANGE REPLICATION SOURCE TO SOURCE_HOST='%s', SOURCE_USER='%s', SOURCE_PASSWORD='%s', SOURCE_PORT=%s;\n" \
      "$(sql_escape "$DOLT_MYSQL_SOURCE_HOST")" \
      "$(sql_escape "$DOLT_MYSQL_SOURCE_USER")" \
      "$(sql_escape "$DOLT_MYSQL_SOURCE_PASSWORD")" \
      "$DOLT_MYSQL_SOURCE_PORT"
  } >"$tmp_sql"

  run_local_sql_query "STOP REPLICA;" >/dev/null 2>&1 || true
  run_local_sql_query "SET @@PERSIST.server_id=${DOLT_MYSQL_REPLICA_SERVER_ID};" >/dev/null
  run_local_sql_file "$tmp_sql" >/dev/null
  if [ -n "$filter" ]; then
    run_local_sql_query "CHANGE REPLICATION FILTER ${filter};" >/dev/null
  fi
  run_local_sql_query "START REPLICA;" >/dev/null
  wait_for_mysql_replica "$deadline"
  rm -f "$tmp_sql"
  trap - EXIT HUP INT TERM
  echo "Dolt MySQL replication source configured"
}

if [ -z "${DOLT_MYSQL_SOURCE_HOST:-}" ]; then
  if [ "$DOLT_MYSQL_REPLICA_REQUIRED" = "true" ]; then
    die "MySQL-source replication requires mysql-source ServiceRef binding"
  fi
  echo "mysql-source ServiceRef is not bound; skipping MySQL replica setup"
  exit 0
fi

configure_mysql_replica
