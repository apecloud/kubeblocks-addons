#!/bin/bash
# sync-acl.sh — memberJoin action: sync ACL from primary to the newly joined replica.
#
# KubeBlocks injects:
#   KB_JOIN_MEMBER_POD_NAME  — name of the pod that just joined
#   KB_JOIN_MEMBER_POD_FQDN  — FQDN of the pod that just joined
#
# targetPodSelector: Any means this runs on ANY available pod.  We pick the
# current primary as the authoritative ACL source, read all user rules via
# "ACL LIST", and replay them on the new replica via "ACL SETUSER".
#
# Why not rely on native replication?  Valkey replication transfers key-value
# data only; ACL rules are not replicated.  The ACL file (/data/users.acl) is
# a local file on each pod's PVC.  A brand-new replica starts with only the
# rules written by valkey-start.sh (i.e., the "default" user), so any custom
# accounts added later must be explicitly pushed over.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

port="${SERVICE_PORT:-6379}"

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

build_cli() {
  local host="${1}"
  _cli=(valkey-cli --no-auth-warning -h "${host}" -p "${port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    _cli+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    # shellcheck disable=SC2206
    _cli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

# Find the current primary by polling each pod's role.
find_primary_fqdn() {
  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  for fqdn in "${pod_fqdns[@]}"; do
    local role
    build_cli "${fqdn}"
    role=$("${_cli[@]}" info replication 2>/dev/null \
             | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || continue
    if [ "${role}" = "master" ]; then
      echo "${fqdn}"
      return 0
    fi
  done
  echo "ERROR: no pod reported role:master — refusing to guess an ACL source." >&2
  return 1
}

# Copy all non-default ACL rules from source to target
sync_acl_to_replica() {
  local src_fqdn="${1}" dst_fqdn="${2}"
  local src_cli=() dst_cli=()
  build_cli "${src_fqdn}"; src_cli=("${_cli[@]}")
  build_cli "${dst_fqdn}"; dst_cli=("${_cli[@]}")

  echo "Syncing ACL from ${src_fqdn} → ${dst_fqdn}"

  # Read ACL rules from primary
  # valkey-cli exits 0 even for server errors; check output for error prefix.
  local acl_list
  acl_list=$("${src_cli[@]}" ACL LIST 2>&1) || {
    echo "ERROR: could not read ACL LIST from ${src_fqdn}: ${acl_list}" >&2
    return 1
  }
  case "${acl_list}" in
    "(error)"*|"ERR "*)
      echo "ERROR: ACL LIST from ${src_fqdn} returned error: ${acl_list}" >&2
      return 1 ;;
  esac

  local sync_failures=0
  while IFS= read -r rule; do
    [ -z "${rule}" ] && continue
    # Format: "user <name> <flags...>"
    local username
    username=$(echo "${rule}" | awk '{print $2}')

    # Skip "default" — managed by valkey-start.sh from VALKEY_DEFAULT_PASSWORD
    [ "${username}" = "default" ] && continue

    # Strip the leading "user <name> " prefix to get just the rule flags
    local rule_flags
    rule_flags="${rule#user "${username}" }"

    echo "  → ACL SETUSER ${username} ${rule_flags}"
    local setuser_out
    # Disable glob expansion so ~* and &* in rule_flags are not expanded by the shell.
    # shellcheck disable=SC2086
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

  # Persist on the replica
  # valkey-cli exits 0 even for server errors; check output content.
  local acl_save_out
  acl_save_out=$("${dst_cli[@]}" ACL SAVE 2>&1) || true
  if [ "${acl_save_out}" != "OK" ]; then
    echo "ERROR: ACL SAVE failed on ${dst_fqdn}: ${acl_save_out} — rules applied in memory only, will be lost on restart" >&2
    return 1
  fi

  if [ "${sync_failures}" -gt 0 ]; then
    echo "ERROR: ACL sync completed with ${sync_failures} failure(s) — replica ACL state is incomplete." >&2
    return 1
  fi
  echo "ACL sync complete."
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────────
load_common_library

if is_empty "${KB_JOIN_MEMBER_POD_FQDN}"; then
  echo "KB_JOIN_MEMBER_POD_FQDN not set — nothing to sync." >&2
  exit 0
fi

primary_fqdn=$(find_primary_fqdn) || exit 1
if is_empty "${primary_fqdn}"; then
  echo "ERROR: could not determine primary — refusing to skip ACL sync." >&2
  exit 1
fi

# Don't sync from/to the same pod.
# Append "." to pod name so "valkey-1." is not a substring of "valkey-11.headless...".
if contains "${primary_fqdn}" "${KB_JOIN_MEMBER_POD_NAME}."; then
  echo "New member is the primary itself — no ACL sync needed."
  exit 0
fi

sync_acl_to_replica "${primary_fqdn}" "${KB_JOIN_MEMBER_POD_FQDN}"
