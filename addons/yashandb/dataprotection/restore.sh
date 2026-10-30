#!/usr/bin/env bash

set -euo pipefail

# 2026-06-02 Reason: implement Stage 3B restore preparation without controlling the database process in the restore job; Purpose: download the full backup set and mark the new cluster for startup-time restore.
# 2026-06-02 Reason: prefer the datasafed binary injected by KubeBlocks for restore jobs; Purpose: avoid accidentally using an older binary already present in the base image PATH.
# 2026-06-18 Reason: real restore jobs may not expose datasafed on PATH; Purpose: resolve the injected binary explicitly and keep proof restore failures observable.
log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" >&2
}

export PATH="${DP_DATASAFED_BIN_PATH:-}:$PATH"
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH:-}"
DATASAFED_BIN="${DATASAFED_BIN:-datasafed}"
YASDB_MOUNT_HOME="${YASDB_MOUNT_HOME:-/home/yashan/mydb}"

YASDB_RESTORE_ROOT="${YASDB_RESTORE_ROOT:-}"
YASDB_RESTORE_DIR="${YASDB_RESTORE_DIR:-}"
YASDB_RESTORE_MARKER="${YASDB_RESTORE_MARKER:-}"
YASDB_RESTORE_ARCHIVE="${YASDB_RESTORE_ARCHIVE:-}"

validate_restore_inputs() {
  # 2026-06-18 Reason: KubeBlocks restore jobs mount the data PVC but do not inject the addon-specific path variable; Purpose: keep the proof restore script aligned with the fixed YashanDB volume mount.
  : "${YASDB_MOUNT_HOME:?YASDB_MOUNT_HOME is required for YashanDB restore preparation}"
  : "${DP_BACKUP_NAME:?DP_BACKUP_NAME is required for YashanDB restore preparation}"
  : "${DP_BACKUP_BASE_PATH:?DP_BACKUP_BASE_PATH is required for datasafed restore preparation}"
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

  log "datasafed binary not found; checked DP_DATASAFED_BIN_PATH=${DP_DATASAFED_BIN_PATH:-unset} and PATH"
  return 1
}

set_restore_paths() {
  YASDB_RESTORE_ROOT="${YASDB_RESTORE_ROOT:-${YASDB_MOUNT_HOME}/restore}"
  YASDB_RESTORE_DIR="${YASDB_RESTORE_DIR:-${YASDB_RESTORE_ROOT}/${DP_BACKUP_NAME}}"
  YASDB_RESTORE_MARKER="${YASDB_RESTORE_MARKER:-${YASDB_MOUNT_HOME}/.restore_new_cluster}"
  YASDB_RESTORE_ARCHIVE="${YASDB_RESTORE_ARCHIVE:-${DP_BACKUP_NAME}.tar}"
}

prepare_restore_data() {
  validate_restore_inputs
  resolve_datasafed_bin
  set_restore_paths

  # 2026-06-02 Reason: keep restore preparation inside the mounted data path; Purpose: prevent an incomplete dataprotection environment from deleting or marking an unintended directory.
  rm -rf "$YASDB_RESTORE_DIR"
  mkdir -p "$YASDB_RESTORE_DIR"

  log "restore runtime: DATASAFED_BIN=${DATASAFED_BIN}"
  log "restore runtime: DP_BACKUP_BASE_PATH=${DP_BACKUP_BASE_PATH}"
  log "restore runtime: YASDB_RESTORE_DIR=${YASDB_RESTORE_DIR}"
  "$DATASAFED_BIN" pull "/${YASDB_RESTORE_ARCHIVE}" - | tar -C "$YASDB_RESTORE_DIR" -xf -
  printf '%s\n' "$YASDB_RESTORE_DIR" >"$YASDB_RESTORE_MARKER"
}

main() {
  prepare_restore_data
}

${__SOURCED__:+false} : || return 0

main "$@"
