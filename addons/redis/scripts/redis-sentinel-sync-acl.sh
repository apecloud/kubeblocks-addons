#!/bin/bash
# redis-sentinel-sync-acl.sh — sync the Sentinel ACL across the redis Sentinel fleet.
#
# Sentinel never replicates ACLs between peers, and redis-sentinel-start-v2.sh
# writes only the "default" user (from SENTINEL_PASSWORD / requirepass) into
# /data/users.acl, so any custom account added to the fleet later has to be
# pushed to the other Sentinel pods explicitly.
#
# Three execution faces (the target decides which mode is used):
#   1. memberJoin of the sentinel component — called by
#      scripts/redis-sentinel-member-join.sh with KB_JOIN_MEMBER_POD_FQDN set:
#      only the joining pod is synced, from the min-lexicographical established
#      peer.
#   2. rebuild — redis-register-to-sentinel ops sets REBUILD_SENTINEL_POD_NAME
#      when a Sentinel pod was rebuilt (its /data volume is fresh, so its ACL
#      only has the default user): only that pod is synced.  The same mode is
#      reachable standalone by passing the target FQDN as the first argument.
#   3. manual ops — no target at all: the min-lex pod is the authoritative
#      source and every other Sentinel is brought in line.
#
# Env:
#   SENTINEL_POD_FQDN_LIST   — all Sentinel pod FQDNs (comma separated, required)
#   SENTINEL_PASSWORD        — Sentinel auth password (optional)
#   SENTINEL_SERVICE_PORT    — Sentinel port (default 26379)
#   REDIS_CLI_TLS_CMD        — TLS flags for redis-cli, e.g. "--tls --insecure"
#   KB_JOIN_MEMBER_POD_FQDN  — joining pod FQDN (optional, memberJoin mode)
#   REBUILD_SENTINEL_POD_NAME— rebuilt pod name (optional, rebuild mode)
#
# Usage: redis-sentinel-sync-acl.sh [target-fqdn]
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
  _cli=(redis-cli --no-auth-warning -h "${host}" -p "${sentinel_port}")
  if [ -n "${SENTINEL_PASSWORD}" ]; then
    _cli+=(-a "${SENTINEL_PASSWORD}")
  fi
  if [ -n "${REDIS_CLI_TLS_CMD}" ]; then
    # shellcheck disable=SC2206
    _cli+=(${REDIS_CLI_TLS_CMD})
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

# pod_fqdn_by_name <pod_name> — the FQDN of that pod as the component itself
# publishes it (SENTINEL_POD_FQDN_LIST holds the addresses KubeBlocks generates,
# so no headless-service name has to be reconstructed by hand).
pod_fqdn_by_name() {
  local pod_name="${1}" fqdn
  for fqdn in "${pod_list[@]}"; do
    [ -n "${fqdn}" ] || continue
    case "${fqdn}" in
      "${pod_name}."*)
        echo "${fqdn}"
        return 0
        ;;
    esac
  done
  return 1
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

# resolve_target_fqdn [explicit_target] — the pod to sync, empty when the whole
# fleet should be aligned.
resolve_target_fqdn() {
  local explicit="${1:-}"
  if [ -n "${explicit}" ]; then
    echo "${explicit}"
    return 0
  fi
  if [ -n "${KB_JOIN_MEMBER_POD_FQDN:-}" ]; then
    echo "${KB_JOIN_MEMBER_POD_FQDN}"
    return 0
  fi
  if [ -n "${REBUILD_SENTINEL_POD_NAME:-}" ]; then
    # Prefer the address the component itself publishes; fall back to the
    # KubeBlocks naming convention when the pod is not (yet) in the list.
    if pod_fqdn_by_name "${REBUILD_SENTINEL_POD_NAME}"; then
      return 0
    fi
    echo "${REBUILD_SENTINEL_POD_NAME}.${SENTINEL_COMPONENT_NAME}-headless.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN:-cluster.local}"
    return 0
  fi
  return 1
}

# sync_acl_to_target <source_fqdn> <target_fqdn> — replay all non-default ACL
# rules of the source on the target, then persist.  Fail-closed.
sync_acl_to_target() {
  local src_fqdn="${1}" dst_fqdn="${2}"
  local src_cli=() dst_cli=()
  build_cli "${src_fqdn}"; src_cli=("${_cli[@]}")
  build_cli "${dst_fqdn}"; dst_cli=("${_cli[@]}")

  echo "Syncing ACL from ${src_fqdn} → ${dst_fqdn}"

  # redis-cli exits non-zero on connection failure but still exits 0 for some
  # protocol errors, so the reply itself has to be inspected.
  local acl_list
  acl_list=$("${src_cli[@]}" ACL LIST 2>&1) || true
  # redis < 6 has no ACL subsystem: ACL LIST answers "unknown command".  There is
  # nothing to sync and nothing to fail on there.
  case "${acl_list}" in
    *"unknown command"*)
      echo "INFO: ACL is not supported by this redis version — skipping the ACL sync."
      return 0 ;;
  esac
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
    [ -n "${username}" ] || continue

    # Skip "default" — managed by redis-sentinel-start-v2.sh from
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

# sync_sentinel_acl [target-fqdn] — resolve source and target(s) and run the sync.
sync_sentinel_acl() {
  # redis 5 has no ACL subsystem at all — skip before touching the fleet.
  case "${SERVICE_VERSION:-}" in
    5.*)
      echo "INFO: redis ${SERVICE_VERSION} has no ACL subsystem — skipping the ACL sync."
      return 0 ;;
  esac
  if [ "${IS_REDIS5:-}" = "true" ]; then
    echo "INFO: redis 5 has no ACL subsystem — skipping the ACL sync."
    return 0
  fi

  local explicit="${1:-}"

  # Ops face on a topology that has no Sentinel at all (standalone): there is no
  # fleet to sync, so this is a no-op instead of an error.  A target (memberJoin
  # / rebuild / explicit argument) without a fleet list stays fail-closed.
  if [ -z "${SENTINEL_POD_FQDN_LIST}" ] && [ -z "${explicit}" ] &&
     [ -z "${KB_JOIN_MEMBER_POD_FQDN:-}" ] && [ -z "${REBUILD_SENTINEL_POD_NAME:-}" ]; then
    echo "INFO: no Sentinel fleet configured — skipping the ACL sync."
    return 0
  fi

  parse_pod_list || return 1
  local target_fqdn=""
  target_fqdn=$(resolve_target_fqdn "${explicit}") || true

  # The authoritative source is the min-lexicographical pod outside the
  # target set; with no explicit target every other pod is a target.
  local source_fqdn
  source_fqdn=$(min_lex_pod "${target_fqdn}") || {
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
sync_sentinel_acl "$@"
