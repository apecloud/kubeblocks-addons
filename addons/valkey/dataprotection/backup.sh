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

validate_cluster_master_slot_coverage() {
  awk '
    NF {
      masters++
      if (NF < 9) { bad=1; next }
      for (i = 9; i <= NF; i++) {
        token = $i
        if (token ~ /^[0-9]+$/) {
          start = token + 0; end = start
        } else if (token ~ /^[0-9]+-[0-9]+$/) {
          split(token, bounds, "-")
          start = bounds[1] + 0; end = bounds[2] + 0
        } else {
          bad=1; continue
        }
        if (start < 0 || end > 16383 || start > end) {
          bad=1; continue
        }
        for (slot = start; slot <= end; slot++) {
          if (seen[slot]++) bad=1
          total++
        }
      }
    }
    END { exit bad || masters == 0 || total != 16384 }
  '
}

cluster_info_value() {
  printf '%s\n' "${1}" | awk -F: -v key="$2" '
    $1 == key { gsub(/\r/, "", $2); value=$2; count++ }
    END { if (count != 1 || value == "") exit 1; print value }
  '
}

# Capture an authoritative primary-local topology view. Calling this before
# and after BGSAVE detects role, parent, slot, and migration drift within the
# per-shard snapshot window.
capture_cluster_snapshot_contract() {
  local info nodes myself_lines myself_flags myself_parent master_rows
  local state assigned ok pfail failed current_epoch my_epoch
  info=$("${connect_base[@]}" CLUSTER INFO 2>/dev/null) || {
    echo "ERROR: cluster mode — cannot read CLUSTER INFO." >&2
    return 1
  }
  state=$(cluster_info_value "${info}" cluster_state) || return 1
  assigned=$(cluster_info_value "${info}" cluster_slots_assigned) || return 1
  ok=$(cluster_info_value "${info}" cluster_slots_ok) || return 1
  pfail=$(cluster_info_value "${info}" cluster_slots_pfail) || return 1
  failed=$(cluster_info_value "${info}" cluster_slots_fail) || return 1
  current_epoch=$(cluster_info_value "${info}" cluster_current_epoch) || return 1
  my_epoch=$(cluster_info_value "${info}" cluster_my_epoch) || return 1
  case "${current_epoch}" in
    ''|*[!0-9]*)
      echo "ERROR: cluster mode — malformed cluster_current_epoch receipt." >&2
      return 1 ;;
  esac
  case "${my_epoch}" in
    ''|*[!0-9]*)
      echo "ERROR: cluster mode — malformed cluster_my_epoch receipt." >&2
      return 1 ;;
  esac
  if [ "${state}" != "ok" ] || [ "${assigned}" != "16384" ] ||
     [ "${ok}" != "16384" ] || [ "${pfail}" != "0" ] || [ "${failed}" != "0" ]; then
    echo "ERROR: cluster mode — cluster is not healthy with all 16384 slots available." >&2
    return 1
  fi

  nodes=$("${connect_base[@]}" CLUSTER NODES 2>/dev/null | tr -d "\r") || return 1
  myself_lines=$(printf '%s\n' "${nodes}" | awk '$3 ~ /(^|,)myself(,|$)/')
  if [ "$(printf '%s\n' "${myself_lines}" | awk 'NF {n++} END {print n+0}')" -ne 1 ]; then
    echo "ERROR: cluster mode — expected exactly one myself row." >&2
    return 1
  fi
  myself_flags=$(printf '%s\n' "${myself_lines}" | awk '{print $3}')
  myself_parent=$(printf '%s\n' "${myself_lines}" | awk '{print $4}')
  if ! printf '%s\n' "${myself_flags}" | grep -Eq '(^|,)master(,|$)' ||
     [ "${myself_parent}" != "-" ]; then
    echo "ERROR: cluster mode — backup target is not the authoritative primary." >&2
    return 1
  fi

  master_rows=$(printf '%s\n' "${nodes}" | awk '$3 ~ /(^|,)master(,|$)/')
  if printf '%s\n' "${master_rows}" |
    awk '$3 ~ /(^|,)(fail|fail\?|handshake|noaddr)(,|$)/ {bad=1} END {exit bad ? 0 : 1}'; then
    echo "ERROR: cluster mode — a master row is failed or not addressable." >&2
    return 1
  fi
  if ! printf '%s\n' "${master_rows}" | validate_cluster_master_slot_coverage; then
    echo "ERROR: cluster mode — master slot ownership is incomplete, overlapping, malformed, or migrating." >&2
    return 1
  fi
  _source_shards=$(printf '%s\n' "${master_rows}" | awk 'NF {n++} END {print n+0}')
  if [ "${_source_shards}" -lt 3 ] || [ "${_source_shards}" -gt 32 ]; then
    echo "ERROR: cluster mode — source shard count ${_source_shards} is outside 3..32." >&2
    return 1
  fi
  _shard_master_id=$(printf '%s\n' "${myself_lines}" | awk '{print $1}')
  _shard_slot_ranges=$(printf '%s\n' "${myself_lines}" | cut -d' ' -f9- | tr ' ' ',')
  _cluster_current_epoch="${current_epoch}"
  _cluster_my_epoch="${my_epoch}"
  if ! validate_cluster_slot_ranges "${_shard_slot_ranges}"; then
    echo "ERROR: cluster mode — invalid slot ranges '${_shard_slot_ranges}' (migration markers, overlap, malformed or out-of-domain)." >&2
    return 1
  fi
  _cluster_topology_signature=$(printf '%s\n' "${nodes}" |
    awk 'NF {
      printf "%s %s %s %s", $1, $3, $4, $7
      for (i=9; i<=NF; i++) printf " %s", $i
      printf "\n"
    }' | LC_ALL=C sort)
}

_cluster_mode_info=$("${connect_base[@]}" INFO cluster 2>/dev/null) || {
  echo "ERROR: cannot determine whether cluster mode is enabled." >&2
  exit 1
}
_cluster_enabled=$(cluster_info_value "${_cluster_mode_info}" cluster_enabled) || {
  echo "ERROR: malformed cluster-mode response." >&2
  exit 1
}
case "${_cluster_enabled}" in
  0|1) ;;
  *)
    echo "ERROR: unsupported cluster_enabled value '${_cluster_enabled}'." >&2
    exit 1 ;;
esac
if [ "${_cluster_enabled}" = "1" ]; then
  capture_cluster_snapshot_contract || exit 1
  _cluster_topology_signature_before="${_cluster_topology_signature}"
  _source_shards_before="${_source_shards}"
  _shard_master_id_before="${_shard_master_id}"
  _shard_slot_ranges_before="${_shard_slot_ranges}"
  _cluster_current_epoch_before="${_cluster_current_epoch}"
  _cluster_my_epoch_before="${_cluster_my_epoch}"
else
  _replication_info=$("${connect_base[@]}" INFO replication 2>/dev/null) || {
    echo "ERROR: cannot read replication state before backup." >&2
    exit 1
  }
  _backup_role=$(cluster_info_value "${_replication_info}" role) || {
    echo "ERROR: malformed replication role before backup." >&2
    exit 1
  }
  case "${_backup_role}" in
    master)
      ;;
    slave)
      _master_link_status=$(cluster_info_value "${_replication_info}" master_link_status) || {
        echo "ERROR: replica backup source has no master_link_status." >&2
        exit 1
      }
      _master_sync_in_progress=$(cluster_info_value "${_replication_info}" master_sync_in_progress) || {
        echo "ERROR: replica backup source has no master_sync_in_progress." >&2
        exit 1
      }
      if [ "${_master_link_status}" != "up" ] || [ "${_master_sync_in_progress}" != "0" ]; then
        echo "ERROR: refusing backup from a stale or synchronizing replica (master_link_status=${_master_link_status}, master_sync_in_progress=${_master_sync_in_progress})." >&2
        exit 1
      fi
      ;;
    *)
      echo "ERROR: unsupported replication role '${_backup_role}' before backup." >&2
      exit 1
      ;;
  esac
fi

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

# Trigger BGSAVE and wait for the accepted operation to finish. BGSAVE returns
# only after the server has accepted the child; LASTSAVE has one-second
# resolution and cannot distinguish a valid fast save in the same second.
echo "INFO: Triggering BGSAVE on ${DP_DB_HOST}:${DP_DB_PORT}"
_bgsave_output=$("${connect_base[@]}" BGSAVE 2>&1) || {
  echo "ERROR: BGSAVE command failed: ${_bgsave_output}" >&2
  exit 1
}
echo "INFO: BGSAVE response: ${_bgsave_output}"
# valkey-cli exits 0 even for protocol errors; detect server-side failures early.
case "${_bgsave_output}" in
  "Background saving started"|"Background saving scheduled") ;;
  "(error)"*|"ERR "*)
    echo "ERROR: BGSAVE returned error: ${_bgsave_output}" >&2
    exit 1 ;;
  *)
    echo "ERROR: unexpected BGSAVE response: ${_bgsave_output}" >&2
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
    if [ "${status}" != "ok" ]; then
      echo "ERROR: BGSAVE failed" >&2
      exit 1
    fi
    echo "INFO: BGSAVE completed."
    break
  elif [ "${in_progress}" != "1" ]; then
    echo "ERROR: invalid rdb_bgsave_in_progress value: ${in_progress:-<empty>}" >&2
    exit 1
  fi
  sleep 3
  _bgsave_elapsed=$((_bgsave_elapsed + 3))
done
if [ "${_bgsave_elapsed}" -ge "${_bgsave_timeout}" ]; then
  echo "ERROR: BGSAVE did not complete within ${_bgsave_timeout}s" >&2
  exit 1
fi

if [ "${_cluster_enabled}" = "1" ]; then
  capture_cluster_snapshot_contract || exit 1
  if [ "${_cluster_topology_signature}" != "${_cluster_topology_signature_before}" ] ||
     [ "${_source_shards}" != "${_source_shards_before}" ] ||
     [ "${_shard_master_id}" != "${_shard_master_id_before}" ] ||
     [ "${_shard_slot_ranges}" != "${_shard_slot_ranges_before}" ] ||
     [ "${_cluster_current_epoch}" != "${_cluster_current_epoch_before}" ] ||
     [ "${_cluster_my_epoch}" != "${_cluster_my_epoch_before}" ]; then
    echo "ERROR: cluster mode — topology changed during BGSAVE; refusing a stale snapshot contract." >&2
    exit 1
  fi
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

# Cluster (sharding) mode: embed the source shard count as engine truth
# (master lines in CLUSTER NODES) so restore can verify the same-shard-count
# v1 boundary. Sentinel/standalone targets skip this (cluster_enabled:0).
if [ "${_cluster_enabled}" = "1" ]; then
  # These values were read from the primary's authoritative myself row and
  # proven stable across the BGSAVE window above.
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
