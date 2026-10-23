#!/usr/bin/env bash

set -euo pipefail

# 2026-06-02 Reason: implement Stage 3A full-backup-only data protection; Purpose: run the documented YashanDB SQL full backup and upload the generated backup set to the KubeBlocks backup repository.
# 2026-06-02 Reason: prefer the datasafed binary injected by KubeBlocks for backup jobs; Purpose: avoid accidentally using an older binary already present in the base image PATH.
# 2026-06-18 Reason: real backup jobs do not inherit an interactive YashanDB shell PATH; Purpose: locate yasql from the mounted database home and connect to the selected target Pod explicitly.
# 2026-06-18 Reason: backup jobs previously exited before KubeBlocks received a failure marker; Purpose: install bounded diagnostics and failure signaling before loading the database runtime profile.
log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" >&2
}

cleanup() {
  local exit_code=$?

  if [ -n "${YASDB_BACKUP_DIR:-}" ]; then
    rm -rf "$YASDB_BACKUP_DIR"
  fi
  if [ -n "${YASDB_BACKUP_SQL_LOG:-}" ]; then
    rm -f "$YASDB_BACKUP_SQL_LOG"
  fi
  if [ "$exit_code" -ne 0 ]; then
    log "YashanDB full backup failed with exit code $exit_code"
    if [ -n "${DP_BACKUP_INFO_FILE:-}" ]; then
      mkdir -p "$(dirname "$DP_BACKUP_INFO_FILE")"
      touch "${DP_BACKUP_INFO_FILE}.exit"
    fi
    exit "$exit_code"
  fi
}

trap cleanup EXIT

log "initializing backup runtime variables"
export PATH="${DP_DATASAFED_BIN_PATH:-}:$PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
DATASAFED_BIN="${DATASAFED_BIN:-datasafed}"

YASDB_PASSWORD="${YASDB_PASSWORD:-yasdb_123}"
YASDB_MOUNT_HOME="${YASDB_MOUNT_HOME:-/home/yashan/mydb}"
YASDB_HOME="${YASDB_HOME:-${YASDB_MOUNT_HOME}/yasdb_home}"
YASQL_BIN="${YASQL_BIN:-${YASDB_HOME}/bin/yasql}"
YASDB_CONNECT_HOST="${DP_DB_HOST:-127.0.0.1}"
YASDB_CONNECT_PORT="${DP_DB_PORT:-1688}"
YASDB_CONNECT="sys/${YASDB_PASSWORD}@${YASDB_CONNECT_HOST}:${YASDB_CONNECT_PORT}"
# 2026-06-18 Reason: backup SQL runs inside the target database process while upload runs inside the backup job; Purpose: use the shared mounted data volume so both processes see the same backup set.
YASDB_BACKUP_ROOT="${YASDB_BACKUP_ROOT:-${YASDB_MOUNT_HOME}/backup}"
YASDB_BACKUP_DIR="${YASDB_BACKUP_ROOT}/${DP_BACKUP_NAME}"
YASDB_BACKUP_ARCHIVE="${DP_BACKUP_NAME}.tar"
YASDB_BACKUP_SQL_LOG="${YASDB_BACKUP_DIR}.sql.log"
log "backup runtime variables initialized"

if [ -f "${YASDB_HOME}/conf/yasdb.bashrc" ]; then
  # shellcheck disable=SC1091
  # 2026-06-18 Reason: vendor profile expands optional variables that are unset in backup jobs; Purpose: load it without letting nounset abort the proof backup runtime.
  log "loading YashanDB runtime profile ${YASDB_HOME}/conf/yasdb.bashrc"
  set +u
  source "${YASDB_HOME}/conf/yasdb.bashrc" >/dev/null 2>&1 || true
  set -u
fi

export PATH="${YASDB_HOME}/bin:$PATH"
export LD_LIBRARY_PATH="${YASDB_HOME}/lib:${LD_LIBRARY_PATH:-}"
log "backup runtime profile loaded"

get_total_size() {
  if command -v du >/dev/null 2>&1; then
    du -sb "$YASDB_BACKUP_DIR" 2>/dev/null | awk '{print $1}'
  else
    echo "0"
  fi
}

save_backup_info() {
  local total_size
  total_size=$(get_total_size)
  echo "{\"totalSize\":\"${total_size}\"}" >"${DP_BACKUP_INFO_FILE}"
}

validate_backup_output() {
  if grep -q 'YAS-[0-9][0-9][0-9][0-9][0-9]' "$YASDB_BACKUP_SQL_LOG"; then
    log "YashanDB backup SQL returned an error while yasql exited successfully"
    cat "$YASDB_BACKUP_SQL_LOG" >&2
    return 1
  fi

  if [ ! -f "${YASDB_BACKUP_DIR}/backup_profile" ]; then
    log "YashanDB backup output is incomplete: ${YASDB_BACKUP_DIR}/backup_profile is missing"
    find "$YASDB_BACKUP_DIR" -maxdepth 3 -print >&2 || true
    return 1
  fi
}

resolve_yasql_bin() {
  if [ -x "$YASQL_BIN" ]; then
    return 0
  fi

  if [ -x "${YASDB_MOUNT_HOME}/.runtime-cache/bin/yasql" ]; then
    YASQL_BIN="${YASDB_MOUNT_HOME}/.runtime-cache/bin/yasql"
    return 0
  fi

  if command -v yasql >/dev/null 2>&1; then
    YASQL_BIN="$(command -v yasql)"
    return 0
  fi

  echo "yasql binary not found; checked ${YASQL_BIN}, ${YASDB_MOUNT_HOME}/.runtime-cache/bin/yasql, and PATH" >&2
  return 1
}

resolve_datasafed_bin() {
  if [ -n "${DP_DATASAFED_BIN_PATH:-}" ] && [ -x "$DP_DATASAFED_BIN_PATH" ] && [ ! -d "$DP_DATASAFED_BIN_PATH" ]; then
    DATASAFED_BIN="$DP_DATASAFED_BIN_PATH"
    return 0
  fi

  if [ -n "${DP_DATASAFED_BIN_PATH:-}" ] && [ -x "${DP_DATASAFED_BIN_PATH}/datasafed" ]; then
    DATASAFED_BIN="${DP_DATASAFED_BIN_PATH}/datasafed"
    return 0
  fi

  if command -v datasafed >/dev/null 2>&1; then
    DATASAFED_BIN="$(command -v datasafed)"
    return 0
  fi

  echo "datasafed binary not found; checked DP_DATASAFED_BIN_PATH=${DP_DATASAFED_BIN_PATH:-unset} and PATH" >&2
  return 1
}

main() {
  rm -rf "$YASDB_BACKUP_DIR"
  mkdir -p "$YASDB_BACKUP_ROOT"
  # 2026-06-18 Reason: backup SQL is executed by the database process user, not the job shell user; Purpose: make the prepared backup path writable from YashanDB.
  chmod 0777 "$YASDB_BACKUP_ROOT"
  resolve_yasql_bin
  resolve_datasafed_bin

  log "backup runtime: YASDB_HOME=${YASDB_HOME}"
  log "backup runtime: YASQL_BIN=${YASQL_BIN}"
  log "backup runtime: DATASAFED_BIN=${DATASAFED_BIN}"
  log "backup runtime: DP_DB_HOST=${YASDB_CONNECT_HOST}"
  log "backup runtime: DP_DB_PORT=${YASDB_CONNECT_PORT}"
  # 2026-06-29 Reason: live backup jobs failed with login denied while the same PVC and DNS path worked from a debug Pod; Purpose: capture non-secret connection diagnostics before the destructive backup SQL.
  # Time: 2026-06-29.
  log "backup runtime: YASDB_PASSWORD_LENGTH=${#YASDB_PASSWORD}"
  getent hosts "$YASDB_CONNECT_HOST" >&2 || true
  log "backup runtime: DP_BACKUP_BASE_PATH=${DP_BACKUP_BASE_PATH}"
  ls -l "$YASQL_BIN" "$DATASAFED_BIN" >&2
  command -v tar >/dev/null 2>&1 || {
    log "tar binary not found in PATH"
    return 127
  }

  log "running YashanDB full backup SQL"
  "$YASQL_BIN" "$YASDB_CONNECT" -c "select status from v\$instance" >&2
  # 2026-06-18 Reason: yasql can return zero while printing YAS errors; Purpose: reject pseudo-success backups before uploading empty archives.
  "$YASQL_BIN" "$YASDB_CONNECT" -c "backup database full format '${YASDB_BACKUP_DIR}'" >"$YASDB_BACKUP_SQL_LOG" 2>&1
  cat "$YASDB_BACKUP_SQL_LOG" >&2
  validate_backup_output

  log "uploading backup archive through datasafed"
  tar -C "$YASDB_BACKUP_DIR" -cf - . | "$DATASAFED_BIN" push - "/${YASDB_BACKUP_ARCHIVE}"
  log "writing KubeBlocks backup info"
  save_backup_info
}

main "$@"
