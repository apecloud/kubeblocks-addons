#!/bin/bash
# restore-sentinel-acl.sh — postReady phase: restore Sentinel ACL after a full restore.
#
# After data is restored and Sentinel pods are running, re-apply any non-default
# ACL rules that were saved during backup.  The "default" user is managed by
# KubeBlocks (systemAccounts) and must not be overwritten here.
#
# KubeBlocks DataProtection injects the standard DP_* variables.

set -e

[ -n "${DP_DATASAFED_BIN_PATH}" ] && export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"

if [ -z "${SENTINEL_POD_FQDN_LIST}" ]; then
  echo "INFO: No Sentinel component — skipping Sentinel ACL restore."
  exit 0
fi

sentinel_acl_file="sentinel.acl"
if ! datasafed list "${sentinel_acl_file}" 2>/dev/null | grep -qF "${sentinel_acl_file}"; then
  echo "INFO: No sentinel.acl in backup repository — skipping."
  exit 0
fi

datasafed pull -d zstd-fastest "${sentinel_acl_file}" /tmp/sentinel.acl
echo "INFO: Downloaded sentinel.acl"

# Detect TLS via connection probe on the first reachable Sentinel.
# Restore jobs do not mount the TLS volume (it may not exist in non-TLS clusters).
_tls_args=""
_first_sentinel=$(echo "${SENTINEL_POD_FQDN_LIST}" | tr ',' '\n' | head -1)
_probe="valkey-cli --no-auth-warning -h ${_first_sentinel} -p ${SENTINEL_SERVICE_PORT:-26379}"
[ -n "${SENTINEL_PASSWORD}" ] && _probe="${_probe} -a ${SENTINEL_PASSWORD}"
if ! ${_probe} PING 2>/dev/null | grep -q "PONG"; then
  if ${_probe} --tls --insecure PING 2>/dev/null | grep -q "PONG"; then
    _tls_args="--tls --insecure"
    echo "INFO: TLS detected via connection probe — using --tls --insecure"
  fi
fi

for sentinel_fqdn in $(echo "${SENTINEL_POD_FQDN_LIST}" | tr ',' '\n'); do
  s_cli="valkey-cli --no-auth-warning ${_tls_args} -h ${sentinel_fqdn} -p ${SENTINEL_SERVICE_PORT:-26379}"
  [ -n "${SENTINEL_PASSWORD}" ] && s_cli="${s_cli} -a ${SENTINEL_PASSWORD}"

  # Verify connectivity
  if ! ${s_cli} PING 2>/dev/null | grep -q "PONG"; then
    echo "WARNING: Sentinel ${sentinel_fqdn} not reachable — skipping." >&2
    continue
  fi

  echo "INFO: Restoring ACL rules to Sentinel ${sentinel_fqdn}..."
  while IFS= read -r rule; do
    [ -z "${rule}" ] && continue
    username=$(echo "${rule}" | awk '{print $2}')
    # Skip "default" — managed by KubeBlocks credentials
    [ "${username}" = "default" ] && continue

    rule_flags="${rule#user "${username}" }"
    # Disable glob expansion so ~* and &* in rule_flags are not expanded by the shell.
    # shellcheck disable=SC2086
    set -f
    setuser_out=$(${s_cli} ACL SETUSER "${username}" ${rule_flags} 2>&1) || true
    set +f
    # valkey-cli exits 0 even for protocol errors; check output content.
    case "${setuser_out}" in
      *"ERR"*|*"WRONGTYPE"*|*"error"*)
        echo "WARNING: failed to restore ACL for ${username}: ${setuser_out}" >&2 ;;
    esac
  done < /tmp/sentinel.acl

  # valkey-cli exits 0 even for server errors; check output content.
  acl_save_out=$(${s_cli} ACL SAVE 2>&1) || true
  if [ "${acl_save_out}" != "OK" ]; then
    echo "WARNING: ACL SAVE failed on ${sentinel_fqdn}: ${acl_save_out} — rules applied in memory only, will be lost on restart" >&2
  fi
  echo "INFO: ACL restore complete for ${sentinel_fqdn}."
done
