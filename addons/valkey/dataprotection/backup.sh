#!/bin/bash
# backup.sh — physical RDB+ACL snapshot backup for Valkey.
#
# KubeBlocks DataProtection injects:
#   DP_DB_HOST           — target pod hostname/FQDN
#   DP_DB_PORT           — target pod port
#   DP_DB_PASSWORD       — target pod auth password
#   DP_BACKUP_NAME       — unique backup name (used as archive filename prefix)
#   DP_BACKUP_BASE_PATH  — datasafed backend path
#   DP_BACKUP_INFO_FILE  — path to write backup metadata JSON
#   DP_DATASAFED_BIN_PATH — path to datasafed binary
#   DATA_DIR             — data mount path (set in ActionSet env)
#
# Current BackupPolicyTemplate env schema cannot inject cross-component
# Sentinel FQDN/password values. Sentinel ACL backup is therefore inactive
# unless those SENTINEL_* variables are supplied by a future explicit contract.

set -e
set -o pipefail

function handle_exit() {
  local exit_code=$?
  # cluster-mode metadata must never remain on the live data volume
  [ "${_cluster_meta_cleanup_needed:-0}" = "1" ] && rm -f "${DATA_DIR}/cluster-meta"
  if [ "${exit_code}" -ne 0 ]; then
    echo "ERROR: backup failed with exit code ${exit_code}" >&2
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT

[ -n "${DP_DATASAFED_BIN_PATH}" ] && export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"

# Detect TLS via connection probe.
# The backup job does not mount the TLS volume (it may not exist in non-TLS
# clusters), so we probe: plain connection first, then --tls --insecure.
# --insecure is intentional HERE ONLY: no CA file is available in this execution face,
# so certificate verification is impossible; in-cluster CLIs verify via --cacert.
_tls_args=()
_probe_base=(valkey-cli --no-auth-warning -h "${DP_DB_HOST}" -p "${DP_DB_PORT}")
[ -n "${DP_DB_PASSWORD:-}" ] && _probe_base+=(-a "${DP_DB_PASSWORD}")
if ! "${_probe_base[@]}" PING 2>/dev/null | grep -q "PONG"; then
  if "${_probe_base[@]}" --tls --insecure PING 2>/dev/null | grep -q "PONG"; then
    _tls_args=(--tls --insecure)
    echo "INFO: TLS detected via connection probe — using --tls --insecure"
  fi
fi

connect_base=(valkey-cli --no-auth-warning "${_tls_args[@]}" -h "${DP_DB_HOST}" -p "${DP_DB_PORT}")
[ -n "${DP_DB_PASSWORD:-}" ] && connect_base+=(-a "${DP_DB_PASSWORD}")

# Save Sentinel ACL only when Sentinel connection variables are explicitly
# supplied. The current chart's BackupPolicyTemplate does not inject them.
save_sentinel_acl() {
  [ -z "${SENTINEL_POD_FQDN_LIST}" ] && return 0
  local acl_list=""
  for sentinel_fqdn in $(echo "${SENTINEL_POD_FQDN_LIST}" | tr ',' '\n'); do
    local s_cli_base=(valkey-cli --no-auth-warning "${_tls_args[@]}" -h "${sentinel_fqdn}" -p "${SENTINEL_SERVICE_PORT:-26379}")
    [ -n "${SENTINEL_PASSWORD:-}" ] && s_cli_base+=(-a "${SENTINEL_PASSWORD}")
    acl_list=$("${s_cli_base[@]}" ACL LIST 2>/dev/null) || continue
    case "${acl_list}" in "(error)"*|"ERR "*) continue ;; esac
    break
  done
  [ -z "${acl_list}" ] && return 0

  echo "${acl_list}" > /tmp/sentinel.acl
  datasafed push -z zstd-fastest /tmp/sentinel.acl "sentinel.acl" || return 1
  echo "INFO: Sentinel ACL saved."
}

# Trigger BGSAVE and wait for it to finish.
# Record LASTSAVE timestamp before triggering so we can confirm our BGSAVE
# completes (not a pre-existing one that was already in progress).
echo "INFO: Triggering BGSAVE on ${DP_DB_HOST}:${DP_DB_PORT}"
_lastsave_before=$("${connect_base[@]}" LASTSAVE 2>/dev/null) || _lastsave_before=0
_bgsave_output=$("${connect_base[@]}" BGSAVE 2>&1) || {
  echo "ERROR: BGSAVE command failed: ${_bgsave_output}" >&2
  exit 1
}
echo "INFO: BGSAVE response: ${_bgsave_output}"
# valkey-cli exits 0 even for protocol errors; detect server-side failures early.
case "${_bgsave_output}" in
  "(error)"*|"ERR "*)
    echo "ERROR: BGSAVE returned error: ${_bgsave_output}" >&2
    exit 1 ;;
esac

echo "INFO: Waiting for BGSAVE to complete..."
_bgsave_timeout=300   # 5 minutes max
_bgsave_elapsed=0
while [ "${_bgsave_elapsed}" -lt "${_bgsave_timeout}" ]; do
  persistence_info=$("${connect_base[@]}" INFO persistence 2>/dev/null) || {
    echo "ERROR: lost connection to Valkey while waiting for BGSAVE" >&2
    exit 1
  }
  in_progress=$(echo "${persistence_info}" | grep rdb_bgsave_in_progress | tr -d '\r' | cut -d: -f2)
  if [ "${in_progress}" = "0" ]; then
    status=$(echo "${persistence_info}" | grep rdb_last_bgsave_status | tr -d '\r' | cut -d: -f2)
    if [ "${status}" = "err" ]; then
      echo "ERROR: BGSAVE failed" >&2
      exit 1
    fi
    # Confirm the save timestamp advanced past our baseline to ensure
    # we are not capturing a pre-existing BGSAVE completion.
    _lastsave_now=$("${connect_base[@]}" LASTSAVE 2>/dev/null) || _lastsave_now=0
    if [ "${_lastsave_now}" -gt "${_lastsave_before}" ]; then
      echo "INFO: BGSAVE completed (lastsave=${_lastsave_now})."
      break
    fi
  fi
  sleep 3
  _bgsave_elapsed=$((_bgsave_elapsed + 3))
done
if [ "${_bgsave_elapsed}" -ge "${_bgsave_timeout}" ]; then
  echo "ERROR: BGSAVE did not complete within ${_bgsave_timeout}s" >&2
  exit 1
fi

echo "INFO: Archiving consistent snapshot artifacts..."
cd "${DATA_DIR}" || { echo "ERROR: cannot cd to DATA_DIR '${DATA_DIR}'" >&2; exit 1; }
# Archive ONLY the BGSAVE-produced RDB plus the ACL file — NOT the whole
# data directory. With appendonly enabled the server keeps writing
# appendonlydir/ while tar runs, so a wholesale copy captures a torn AOF
# manifest/segment set; on startup the engine PREFERS the AOF over the RDB,
# which would make restore fidelity ride on that racy copy instead of the
# consistent BGSAVE snapshot we just waited for. restore.prepareData seeds
# a multipart AOF manifest from dump.rdb before Valkey starts, making the
# BGSAVE moment the well-defined restore point even with appendonly enabled.
if [ ! -f "./dump.rdb" ]; then
  echo "ERROR: dump.rdb not found in ${DATA_DIR} after BGSAVE" >&2
  exit 1
fi
backup_files=("./dump.rdb")
[ -f "./users.acl" ] && backup_files+=("./users.acl")

validate_cluster_slot_ranges() {
  awk -v raw="$1" 'BEGIN {
    if (raw == "") exit 1
    n = split(raw, parts, ",")
    for (i = 1; i <= n; i++) {
      token = parts[i]
      if (token ~ /^[0-9]+$/) {
        start = token + 0; end = start
      } else if (token ~ /^[0-9]+-[0-9]+$/) {
        split(token, bounds, "-")
        start = bounds[1] + 0; end = bounds[2] + 0
      } else {
        exit 1
      }
      if (start < 0 || end > 16383 || start > end) exit 1
      for (slot = start; slot <= end; slot++) {
        if (seen[slot]++) exit 1
      }
    }
  }'
}

# Cluster (sharding) mode: embed the source shard count as engine truth
# (master lines in CLUSTER NODES) so restore can verify the same-shard-count
# v1 boundary. Sentinel/standalone targets skip this (cluster_enabled:0).
_cluster_enabled=$("${connect_base[@]}" INFO cluster 2>/dev/null | grep "^cluster_enabled:" | tr -d "\\r" | cut -d: -f2)
if [ "${_cluster_enabled}" = "1" ]; then
  _source_shards=$("${connect_base[@]}" CLUSTER NODES 2>/dev/null | tr -d "\r" | awk '$3 ~ /master/' | grep -c . || true)
  if [ -z "${_source_shards}" ] || [ "${_source_shards}" -lt 3 ] || [ "${_source_shards}" -gt 32 ]; then
    echo "ERROR: cluster mode detected but could not count source shards from CLUSTER NODES." >&2
    exit 1
  fi
  # Record THIS SHARD's slot ranges + master identity: shard count alone
  # is not a sufficient restore precondition (post-rebalance layouts
  # differ from a re-formed even split). The backup target is normally a
  # SECONDARY (BPT role) which owns no slots — so the ranges must come
  # from this shard's MASTER line, resolved from the target's view:
  # myself's parent id when the target is a slave, else myself itself.
  _nodes=$("${connect_base[@]}" CLUSTER NODES 2>/dev/null | tr -d "\r")
  _myself_line=$(echo "${_nodes}" | awk '$3 ~ /myself/')
  if echo "${_myself_line}" | awk '{print $3}' | grep -q slave; then
    _shard_master_id=$(echo "${_myself_line}" | awk '{print $4}')
  else
    _shard_master_id=$(echo "${_myself_line}" | awk '{print $1}')
  fi
  _master_line=$(echo "${_nodes}" | awk -v id="${_shard_master_id}" '$1 == id')
  if [ -z "${_master_line}" ] || [ "${_shard_master_id}" = "-" ]; then
    echo "ERROR: cluster mode — cannot resolve this shard's master from the target's CLUSTER NODES view." >&2
    exit 1
  fi
  _shard_slot_ranges=$(echo "${_master_line}" | cut -d' ' -f9- | tr ' ' ',')
  if [ -z "${_shard_slot_ranges}" ]; then
    echo "ERROR: cluster mode — this shard's master ${_shard_master_id} owns no slot ranges; refusing to write empty metadata." >&2
    exit 1
  fi
  if ! validate_cluster_slot_ranges "${_shard_slot_ranges}"; then
    echo "ERROR: cluster mode — invalid slot ranges '${_shard_slot_ranges}' (migration markers, overlap, malformed or out-of-domain); refusing backup metadata." >&2
    exit 1
  fi
  _rdb_sha256=$(sha256sum ./dump.rdb 2>/dev/null | awk '{print $1}')
  case "${_rdb_sha256}" in
    ''|*[!0-9a-fA-F]* )
      echo "ERROR: cluster mode — cannot compute dump.rdb SHA-256 for restore identity." >&2
      exit 1 ;;
  esac
  [ "${#_rdb_sha256}" -eq 64 ] || {
    echo "ERROR: cluster mode — invalid dump.rdb SHA-256 length." >&2
    exit 1
  }
  {
    printf 'source_shards=%s\n' "${_source_shards}"
    printf 'shard_master_id=%s\n' "${_shard_master_id}"
    printf 'shard_slot_ranges=%s\n' "${_shard_slot_ranges}"
    printf 'rdb_sha256=%s\n' "${_rdb_sha256}"
  } > ./cluster-meta
  backup_files+=("./cluster-meta")
  # cluster-meta is backup metadata, not engine data: it must not remain
  # on the live DATA_DIR after archiving (review blocker). Cleaned right
  # after tar below AND on failure via handle_exit (single EXIT trap —
  # a second `trap EXIT` here would clobber handle_exit).
  _cluster_meta_cleanup_needed=1
  echo "INFO: cluster mode — embedded cluster-meta (source_shards=${_source_shards})."
fi
tar -cvf - "${backup_files[@]}" | datasafed push -z zstd-fastest - "${DP_BACKUP_NAME}.tar.zst" || exit 1
rm -f ./cluster-meta

save_sentinel_acl || \
  echo "WARNING: Sentinel ACL save failed — ACL rules will not be restored after a cluster restore." >&2

echo "INFO: Data archived successfully."
TOTAL_SIZE=$(datasafed stat "${DP_BACKUP_NAME}.tar.zst" | grep TotalSize | awk '{print $2}') || true
if [ -z "${TOTAL_SIZE}" ]; then
  echo "WARNING: could not parse TotalSize from datasafed stat — reporting 0" >&2
  TOTAL_SIZE=0
fi
echo "{\"totalSize\":\"${TOTAL_SIZE}\"}" > "${DP_BACKUP_INFO_FILE}" && sync || {
  echo "ERROR: failed to write backup info file '${DP_BACKUP_INFO_FILE}'" >&2
  exit 1
}
