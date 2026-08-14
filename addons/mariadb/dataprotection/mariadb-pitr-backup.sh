#!/bin/bash
set -euo pipefail

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

DB_USER="${DP_DB_USER}"
DB_PASSWORD="${DP_DB_PASSWORD}"
if [ -n "${MYSQL_ADMIN_USER:-}" ] && [ -n "${MYSQL_ADMIN_PASSWORD:-}" ]; then
  DB_USER="$MYSQL_ADMIN_USER"
  DB_PASSWORD="$MYSQL_ADMIN_PASSWORD"
fi
export MYSQL_PWD="$DB_PASSWORD"
sql() { mariadb --skip-ssl -u "$DB_USER" -h "$DP_DB_HOST" -P "$DP_DB_PORT" -N -e "$1"; }

log_bin_basename=$(sql "SHOW VARIABLES LIKE 'log_bin_basename';" | awk -F '\t' '{print $2}')
if [ -z "$log_bin_basename" ]; then
  echo "binary logging is not enabled on ${DP_TARGET_POD_NAME}" >&2
  exit 1
fi
LOG_DIR=$(dirname "$log_bin_basename")
LOG_PREFIX=$(basename "$log_bin_basename")
last_flush=$(date +%s)
last_size=""
latest_archived=""

list_binlogs() {
  find "$LOG_DIR" -maxdepth 1 -type f -name "${LOG_PREFIX}.*" \
    | awk '/\.[0-9]+$/' | sort -V
}

normalize_binlog_time() {
  local raw="$1" date_part time_part
  [ -n "$raw" ] || return 0
  date_part=${raw%% *}
  time_part=${raw#* }
  date -u -d "20${date_part:0:2}-${date_part:2:2}-${date_part:4:2} ${time_part}" '+%Y-%m-%dT%H:%M:%SZ'
}

binlog_start_time() {
  local raw
  raw=$(mariadb-binlog "$1" 2>/dev/null | awk '/end_log_pos/ && !value{gsub(/^#/ , ""); value=$1 " " $2} END{print value}')
  normalize_binlog_time "$raw"
}

binlog_end_time() {
  local raw
  raw=$(mariadb-binlog "$1" 2>/dev/null | awk '/end_log_pos/{gsub(/^#/ , ""); value=$1 " " $2} END{print value}')
  normalize_binlog_time "$raw"
}

save_status() {
  local latest="$1" total start stop oldest_epoch
  total=$(datasafed stat / | awk '/TotalSize/{print $2}')
  [ "$total" = "$last_size" ] && return 0
  last_size="$total"
  oldest_epoch=$(datasafed list -f --recursive /binlog 2>/dev/null | sed -n 's#^.*/\([0-9][0-9]*\)-.*#\1#p' | sort -n | head -1)
  start=""
  [ -n "$oldest_epoch" ] && start=$(date -u -d "@${oldest_epoch}" '+%Y-%m-%dT%H:%M:%SZ')
  stop=$(binlog_end_time "$latest")
  echo "{\"totalSize\":\"${total}\",\"timeRange\":{\"start\":\"${start}\",\"end\":\"${stop}\"}}" > "$DP_BACKUP_INFO_FILE"
}

archive_closed_binlogs() {
  local active="$1" file base object epoch event_time existing
  existing=$(datasafed list -f --recursive /binlog 2>/dev/null || true)
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ "$file" = "$active" ] && continue
    base=$(basename "$file")
    if printf '%s\n' "$existing" | grep -q -- "-${DP_TARGET_POD_NAME}-${base}$"; then
      continue
    fi
    event_time=$(binlog_start_time "$file")
    [ -n "$event_time" ] || {
      echo "cannot determine start time for binlog $file" >&2
      return 1
    }
    epoch=$(date -u -d "$event_time" +%s)
    object="/binlog/${epoch}-${DP_TARGET_POD_NAME}-${base}"
    datasafed push -z zstd-fastest "$file" "$object"
    latest_archived="$file"
    existing="${existing}${existing:+$'\n'}${object}"
  done < <(list_binlogs)
}

trap 'sync; exit 0' TERM
while true; do
  sql "SELECT 1" >/dev/null
  active=$(list_binlogs | tail -1)
  if [ -n "$active" ]; then
    now=$(date +%s)
    size=$(stat -c '%s' "$active")
    if [ "$size" -gt "$FLUSH_BINLOG_AFTER_SIZE" ] || [ $((now - last_flush)) -ge "$FLUSH_BINLOG_INTERVAL_SECONDS" ]; then
      sql "FLUSH BINARY LOGS;"
      last_flush="$now"
      active=$(list_binlogs | tail -1)
    fi
    archive_closed_binlogs "$active"
    [ -n "$latest_archived" ] && save_status "$latest_archived"
  fi
  sleep "$BINLOG_ARCHIVE_INTERVAL"
done
