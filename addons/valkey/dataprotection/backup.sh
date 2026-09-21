#!/bin/bash
# backup.sh — physical full backup for Valkey (redis-aligned flow).
#
# KubeBlocks DataProtection injects:
#   DP_DB_HOST            — target pod hostname/FQDN
#   DP_DB_PORT            — target pod port
#   DP_DB_PASSWORD        — target pod auth password
#   DP_BACKUP_NAME        — unique backup name (used as archive filename prefix)
#   DP_BACKUP_BASE_PATH   — datasafed backend path
#   DP_BACKUP_INFO_FILE   — path to write backup metadata JSON
#   DP_DATASAFED_BIN_PATH — path to datasafed binary
#   DATA_DIR              — data mount path (set in ActionSet env)
#
# Flow (mirrors redis/dataprotection/backup.sh):
#   1. BGSAVE on the target pod and wait for completion.
#   2. tar the WHOLE DATA_DIR (dump.rdb, users.acl and — with appendonly
#      enabled — appendonlydir/) and push it as <backup>.tar.zst.  Archiving
#      the live AOF together with the RDB matches the redis addon behaviour;
#      note the tar may race with AOF rewrites, in which case tar exits 1 and
#      the backup framework retries.
#   3. Push the Sentinel ACL file when Sentinel connection vars are supplied.
#
# Valkey-specific deltas vs redis (kept on purpose):
#   - TLS is detected by connection probe (plain first, then --tls --insecure):
#     the BackupPolicyTemplate env schema cannot inject VALKEY_CLI_TLS_ARGS
#     here, so a TLS cluster would be unreachable without the probe.
#   - LASTSAVE baseline: the completion we observe must be OUR BGSAVE, not a
#     pre-existing one that was already in flight.
#   - valkey-cli exits 0 even for protocol errors — BGSAVE output is checked.

set -e
set -o pipefail

# if the script exits with a non-zero exit code, touch a file to indicate that
# the backup failed; the sync progress container checks this file and exits.
function handle_exit() {
  local exit_code=$?
  if [ "${exit_code}" -ne 0 ]; then
    echo "failed with exit code ${exit_code}"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT

if [ -n "${DP_DATASAFED_BIN_PATH}" ]; then export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"; fi
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"

# TLS args — redis addon parity: when the ComponentDefinition's TLS_ENABLED
# (tlsVarRef) reaches this execution face it is the ONLY switch, and it maps to
# the same `--tls --insecure` the redis addon uses for its cli vars.
# Certificate verification is impossible there: no CA file is available in this execution face (in-cluster CLIs verify via --cacert).
# Backup/restore jobs are not guaranteed to receive component vars, so when
# TLS_ENABLED is absent fall back to a connection probe (plain, then
# --tls --insecure).
_tls_args=()
if [ "${TLS_ENABLED:-}" = "true" ]; then
  _tls_args=(--tls --insecure)
  echo "INFO: TLS_ENABLED=true — using --tls --insecure"
elif [ -z "${TLS_ENABLED:-}" ]; then
  _probe_base=(valkey-cli --no-auth-warning -h "${DP_DB_HOST}" -p "${DP_DB_PORT}")
  if [ -n "${DP_DB_PASSWORD:-}" ]; then
    _probe_base+=(-a "${DP_DB_PASSWORD}")
  fi
  if ! "${_probe_base[@]}" PING 2>/dev/null | grep -q "PONG"; then
    if "${_probe_base[@]}" --tls --insecure PING 2>/dev/null | grep -q "PONG"; then
      _tls_args=(--tls --insecure)
      echo "INFO: TLS detected via connection probe — using --tls --insecure"
    fi
  fi
fi

connect_url=(valkey-cli --no-auth-warning "${_tls_args[@]}" -h "${DP_DB_HOST}" -p "${DP_DB_PORT}")
if [ -n "${DP_DB_PASSWORD:-}" ]; then
  connect_url+=(-a "${DP_DB_PASSWORD}")
fi

# Save Sentinel ACL only when Sentinel connection variables are explicitly
# supplied (the current chart's BackupPolicyTemplate does not inject them —
# same limitation as the redis addon).
save_sentinel_acl() {
  [ -z "${SENTINEL_POD_FQDN_LIST}" ] && return 0
  local acl_list="" sentinel_fqdn s_cli
  for sentinel_fqdn in $(echo "${SENTINEL_POD_FQDN_LIST}" | tr ',' '\n'); do
    echo "INFO: save sentinel ${sentinel_fqdn} ACL file"
    s_cli=(valkey-cli --no-auth-warning "${_tls_args[@]}" -h "${sentinel_fqdn}" -p "${SENTINEL_SERVICE_PORT:-26379}")
    [ -n "${SENTINEL_PASSWORD:-}" ] && s_cli+=(-a "${SENTINEL_PASSWORD}")
    acl_list=$("${s_cli[@]}" ACL LIST 2>/dev/null) || acl_list=""
    [ -n "${acl_list}" ] && break
  done
  [ -z "${acl_list}" ] && return 0
  echo "${acl_list}" > /tmp/sentinel.acl
  datasafed push -z zstd-fastest /tmp/sentinel.acl "sentinel.acl" || return 1
  echo "INFO: Sentinel ACL saved."
}

echo "INFO: start BGSAVE"
_lastsave_before=$("${connect_url[@]}" LASTSAVE 2>/dev/null) || _lastsave_before=0
_bgsave_output=$("${connect_url[@]}" BGSAVE 2>&1) || true
echo "INFO: BGSAVE response: ${_bgsave_output}"
case "${_bgsave_output}" in
  "(error)"*|"ERR "*)
    echo "ERROR: BGSAVE returned error: ${_bgsave_output}" >&2
    exit 1 ;;
esac

echo "INFO: wait for saving rdb successfully"
_bgsave_timeout=300
_bgsave_elapsed=0
while true; do
  if [ "${_bgsave_elapsed}" -ge "${_bgsave_timeout}" ]; then
    echo "ERROR: BGSAVE did not complete within ${_bgsave_timeout}s" >&2
    exit 1
  fi
  persistence_info=$("${connect_url[@]}" INFO persistence 2>/dev/null) || {
    echo "ERROR: lost connection to Valkey while waiting for BGSAVE" >&2
    exit 1
  }
  bgsave_in_progress=$(echo "${persistence_info}" | grep rdb_bgsave_in_progress | tr -d '\r' | cut -d: -f2)
  if [ "${bgsave_in_progress}" = "0" ]; then
    bgsave_status=$(echo "${persistence_info}" | grep rdb_last_bgsave_status | tr -d '\r' | cut -d: -f2)
    if [ "${bgsave_status}" = "err" ]; then
      echo "ERROR: BGSAVE failed on target pod" >&2
      exit 1
    fi
    # Confirm the save timestamp advanced past our baseline so we do not
    # mistake a pre-existing BGSAVE completion for ours.
    _lastsave_now=$("${connect_url[@]}" LASTSAVE 2>/dev/null) || _lastsave_now=0
    if [ "${_lastsave_now}" -gt "${_lastsave_before}" ]; then
      echo "INFO: BGSAVE completed (no changes since last save)"
      break
    fi
  fi
  sleep 3
  _bgsave_elapsed=$((_bgsave_elapsed + 3))
done

echo "INFO: start to save data file..."
cd "${DATA_DIR}" || { echo "ERROR: cannot cd to DATA_DIR '${DATA_DIR}'" >&2; exit 1; }
# NOTE: if files changed during taring, the exit code will be 1 when it ends
# (the AOF is archived together with the RDB, as in the redis addon).
tar -cvf - ./ | datasafed push -z zstd-fastest - "${DP_BACKUP_NAME}.tar.zst" || exit 1
save_sentinel_acl || \
  echo "WARNING: Sentinel ACL save failed — ACL rules will not be restored after a cluster restore." >&2
echo "INFO: save data file successfully"

TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}') || true
if [ -z "${TOTAL_SIZE}" ]; then
  echo "WARNING: could not parse TotalSize from datasafed stat — reporting 0" >&2
  TOTAL_SIZE=0
fi
echo "{\"totalSize\":\"${TOTAL_SIZE}\"}" > "${DP_BACKUP_INFO_FILE}" && sync || {
  echo "ERROR: failed to write backup info file '${DP_BACKUP_INFO_FILE}'" >&2
  exit 1
}
