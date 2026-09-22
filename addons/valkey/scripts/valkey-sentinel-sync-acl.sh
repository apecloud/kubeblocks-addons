#!/bin/bash
# valkey-sentinel-sync-acl.sh — sync the Sentinel ACL across the Sentinel fleet.
#
# Two execution faces:
#   1. memberJoin of the Sentinel component (invoked by
#      scripts/valkey-sentinel-member-join.sh after the monitor registration):
#      KB_JOIN_MEMBER_POD_FQDN is set → only the joining Sentinel is synced,
#      from the min-lexicographical established peer.  valkey-sentinel-start.sh
#      writes only the "default" user from SENTINEL_PASSWORD, so any custom
#      accounts added to the fleet later must be pushed to the new pod
#      explicitly — Sentinel does not replicate ACLs between peers.
#   2. valkey-sync-sentinel-acl OpsDefinition (manual custom ops): run without
#      KB_JOIN_MEMBER_POD_* → the min-lex pod is the authoritative source and
#      every other Sentinel is brought in line.
#
# Env:
#   SENTINEL_POD_FQDN_LIST   — all Sentinel pod FQDNs (comma separated, required)
#   SENTINEL_PASSWORD        — Sentinel auth password (optional)
#   SENTINEL_SERVICE_PORT    — Sentinel port (default 26379)
#   VALKEY_CLI_TLS_ARGS      — TLS flags for valkey-cli (optional)
#   KB_JOIN_MEMBER_POD_NAME  — joining pod name (optional, memberJoin mode)
#   KB_JOIN_MEMBER_POD_FQDN  — joining pod FQDN (optional, memberJoin mode)
#
# Self-contained on purpose: the OpsDefinition action pod does not mount the
# scripts ConfigMap, so this file must not source /scripts/common.sh.  Parsing
# stays in plain bash IFS reads (older installed common.sh builds lack the
# split()/equals() helpers).

set -e

sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"

# build_cli <host> — fills the global _cli array.
build_cli() {
  local host="${1}"
  _cli=(valkey-cli --no-auth-warning -h "${host}" -p "${sentinel_port}")
  if [ -n "${SENTINEL_PASSWORD}" ]; then
    _cli+=(-a "${SENTINEL_PASSWORD}")
  fi
  if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
    # shellcheck disable=SC2206
    _cli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

# parse_pod_list — split SENTINEL_POD_FQDN_LIST into the global pod_list array.
parse_pod_list() {
  if [ -z "${SENTINEL_POD_FQDN_LIST}" ]; then
    echo "ERROR: required environment variable SENTINEL_POD_FQDN_LIST is not set." >&2
    return 1
  fi
  IFS=',' read -ra pod_list <<< "${SENTINEL_POD_FQDN_LIST}"
}

# min_lex_pod <excluded_fqdn> — lexicographically smallest pod FQDN of the
# fleet excluding one pod (the deterministic authoritative source, same
# convention as the other registration paths).
min_lex_pod() {
  local excluded="${1}" fqdn best=""
  for fqdn in "${pod_list[@]}"; do
    [ -n "${fqdn}" ] || continue
    [ "${fqdn}" != "${excluded}" ] || continue
    if [ -z "${best}" ] || [[ "${fqdn}" < "${best}" ]]; then
      best="${fqdn}"
    fi
  done
  [ -n "${best}" ] || return 1
  echo "${best}"
}

# sync_acl_to_target <source_fqdn> <target_fqdn> — replay all non-default ACL
# rules of the source on the target, then persist.  Fail-closed.
sync_acl_to_target() {
  local src_fqdn="${1}" dst_fqdn="${2}"
  local src_cli=() dst_cli=()
  build_cli "${src_fqdn}"; src_cli=("${_cli[@]}")
  build_cli "${dst_fqdn}"; dst_cli=("${_cli[@]}")

  echo "Syncing ACL from ${src_fqdn} → ${dst_fqdn}"

  # valkey-cli exits 0 even for server errors; check output for error prefix.
  local acl_list
  acl_list=$("${src_cli[@]}" ACL LIST 2>&1) || true
  case "${acl_list}" in
    "(error)"*|"ERR "*|"Could not connect"*)
      echo "ERROR: ACL LIST from ${src_fqdn} failed: ${acl_list}" >&2
      return 1 ;;
  esac
  if [ -z "${acl_list}" ]; then
    echo "ERROR: ACL LIST from ${src_fqdn} returned nothing — source unreachable?" >&2
    return 1
  fi

  local sync_failures=0 rule username rule_flags setuser_out
  while IFS= read -r rule; do
    [ -z "${rule}" ] && continue
    # Format: "user <name> <flags...>"
    username=$(echo "${rule}" | awk '{print $2}')

    # Skip "default" — managed by valkey-sentinel-start.sh from
    # SENTINEL_PASSWORD; replaying it could desync the fleet credentials.
    [ "${username}" = "default" ] && continue

    # Strip the leading "user <name> " prefix to get just the rule flags.
    rule_flags="${rule#user "${username}" }"

    # Rule flags contain password material (#<sha256> tokens) — log only the
    # username, never the payload.
    echo "  → ACL SETUSER ${username} (rules redacted)"
    # set -f: rule flags contain ~* and &* globs that the shell would expand.
    set -f
    # shellcheck disable=SC2086
    setuser_out=$("${dst_cli[@]}" ACL SETUSER "${username}" ${rule_flags} 2>&1) || true
    set +f
    case "${setuser_out}" in
      *"ERR"*|*"WRONGTYPE"*|*"error"*)
        echo "  ERROR: failed to set ACL for ${username}: ${setuser_out}" >&2
        sync_failures=$((sync_failures + 1)) ;;
    esac
  done <<< "${acl_list}"

  # Persist on the target (ACL SAVE replies +OK — verified contract).
  local acl_save_out
  acl_save_out=$("${dst_cli[@]}" ACL SAVE 2>&1) || true
  if [ "${acl_save_out}" != "OK" ]; then
    echo "ERROR: ACL SAVE failed on ${dst_fqdn}: ${acl_save_out} — rules applied in memory only, will be lost on restart" >&2
    return 1
  fi

  if [ "${sync_failures}" -gt 0 ]; then
    echo "ERROR: ACL sync to ${dst_fqdn} completed with ${sync_failures} failure(s) — target ACL state is incomplete." >&2
    return 1
  fi
  echo "ACL sync to ${dst_fqdn} complete."
}

# sync_sentinel_acl — resolve source and target(s) and run the sync.
sync_sentinel_acl() {
  parse_pod_list || return 1

  local target_fqdn source_fqdn
  if [ -n "$REBUILD_SENTINEL_POD_NAME" ]; then
    # rebuild mode: only the rebuilt Sentinel is synced.
    target_fqdn="${REBUILD_SENTINEL_POD_NAME}.${SENTINEL_COMPONENT_NAME}-headless.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN:-cluster.local}"
  fi
  if [ -n "${KB_JOIN_MEMBER_POD_FQDN}" ]; then
    # memberJoin mode: only the joining Sentinel is synced.
    target_fqdn="${KB_JOIN_MEMBER_POD_FQDN}"
  fi

  # The authoritative source is the min-lexicographical pod outside the
  # target set; with no explicit target every other pod is a target.
  source_fqdn=$(min_lex_pod "${target_fqdn:-}") || {
    echo "ERROR: no established Sentinel peer to sync the ACL from." >&2
    return 1
  }

  if [ -n "${target_fqdn}" ]; then
    sync_acl_to_target "${source_fqdn}" "${target_fqdn}"
    return $?
  fi

  # Ops mode: align every non-source Sentinel.
  local rc=0 fqdn
  for fqdn in "${pod_list[@]}"; do
    [ -n "${fqdn}" ] || continue
    [ "${fqdn}" != "${source_fqdn}" ] || continue
    sync_acl_to_target "${source_fqdn}" "${fqdn}" || rc=1
  done
  return "${rc}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
sync_sentinel_acl
