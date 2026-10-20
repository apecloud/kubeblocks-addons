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
ACTION_CLIENT_TIMEOUT_SECONDS="${ACTION_CLIENT_TIMEOUT_SECONDS:-3}"
SYNC_ACL_RETRY_SAFE="yes"

member_join_diagnose() {
  local phase="$1"
  local retry_safe="$2"
  local detail="$3"
  {
    echo "memberJoin diagnosis:"
    echo "  action: memberJoin"
    echo "  phase: ${phase}"
    echo "  cluster: ${KB_CLUSTER_NAME:-<unset>}"
    echo "  detail: ${detail}"
    echo "  next-retry-safe: ${retry_safe}"
  } >&2
}

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

run_bounded_cli() {
  if [ "${ut_mode:-false}" = "true" ]; then
    "$@"
    return $?
  fi
  timeout "${ACTION_CLIENT_TIMEOUT_SECONDS}" "$@"
}

# Find the current primary by polling each pod's role.
find_primary_fqdn() {
  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  local masters=()
  for fqdn in "${pod_fqdns[@]}"; do
    local role
    build_cli "${fqdn}"
    role=$(run_bounded_cli "${_cli[@]}" info replication 2>/dev/null \
             | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || continue
    if [ "${role}" = "master" ]; then
      masters+=("${fqdn}")
    fi
  done
  if [ "${#masters[@]}" -ne 1 ]; then
    echo "ERROR: ${#masters[@]} pods reported role:master — refusing an ambiguous ACL source." >&2
    return 1
  fi
  echo "${masters[0]}"
}

# Copy all non-default ACL rules from source to target
sync_acl_to_replica() {
  local src_fqdn="${1}" dst_fqdn="${2}"
  local src_cli=() dst_cli=()
  SYNC_ACL_RETRY_SAFE="yes"
  build_cli "${src_fqdn}"; src_cli=("${_cli[@]}")
  build_cli "${dst_fqdn}"; dst_cli=("${_cli[@]}")

  echo "Syncing ACL from ${src_fqdn} → ${dst_fqdn}"

  # Read ACL rules from primary
  # valkey-cli exits 0 even for server errors; check output for error prefix.
  local acl_list
  acl_list=$(run_bounded_cli "${src_cli[@]}" ACL LIST 2>&1) || {
    echo "ERROR: could not read ACL LIST from ${src_fqdn}: ${acl_list}" >&2
    return 1
  }
  case "${acl_list}" in
    "")
      SYNC_ACL_RETRY_SAFE="no"
      echo "ERROR: ACL LIST from ${src_fqdn} returned an empty reply." >&2
      return 1 ;;
    "(error)"*|"ERR "*)
      SYNC_ACL_RETRY_SAFE="no"
      echo "ERROR: ACL LIST from ${src_fqdn} returned error: ${acl_list}" >&2
      return 1 ;;
  esac

  local sync_failures=0
  while IFS= read -r rule; do
    [ -z "${rule}" ] && continue
    # Format: "user <name> <flags...>"
    local username rule_flags
    case "${rule}" in
      "user "*" "*) ;;
      *)
        SYNC_ACL_RETRY_SAFE="no"
        echo "ERROR: ACL LIST from ${src_fqdn} contains a malformed rule." >&2
        return 1 ;;
    esac
    username=$(echo "${rule}" | awk '{print $2}')
    [ -n "${username}" ] || {
      SYNC_ACL_RETRY_SAFE="no"
      echo "ERROR: ACL LIST from ${src_fqdn} contains an empty username." >&2
      return 1
    }

    # Skip "default" — managed by valkey-start.sh from VALKEY_DEFAULT_PASSWORD
    [ "${username}" = "default" ] && continue

    # Strip the leading "user <name> " prefix to get just the rule flags
    rule_flags="${rule#user "${username}" }"

    # Rule flags contain password material (#<sha256> / ><plain> tokens) —
    # log only the username, never the rule payload.
    echo "  → ACL SETUSER ${username} (rules redacted)"
    local setuser_out setuser_rc=0
    # Disable glob expansion so ~* and &* in rule_flags are not expanded by the shell.
    # shellcheck disable=SC2086
    set -f
    # shellcheck disable=SC2086
    setuser_out=$(run_bounded_cli "${dst_cli[@]}" ACL SETUSER "${username}" ${rule_flags} 2>&1) || setuser_rc=$?
    set +f
    setuser_out="${setuser_out//$'\r'/}"
    setuser_out="${setuser_out//$'\n'/}"
    if [ "${setuser_rc}" -ne 0 ]; then
      echo "  ERROR: ACL SETUSER for ${username} failed with rc=${setuser_rc}: ${setuser_out}" >&2
      sync_failures=$((sync_failures + 1))
    elif [ "${setuser_out}" != "OK" ]; then
      SYNC_ACL_RETRY_SAFE="no"
      echo "  ERROR: ACL SETUSER for ${username} returned non-OK reply: ${setuser_out}" >&2
      sync_failures=$((sync_failures + 1))
    fi
  done <<< "${acl_list}"

  # Persist on the replica
  # valkey-cli exits 0 even for server errors; check output content.
  local acl_save_out acl_save_rc=0
  acl_save_out=$(run_bounded_cli "${dst_cli[@]}" ACL SAVE 2>&1) || acl_save_rc=$?
  acl_save_out="${acl_save_out//$'\r'/}"
  acl_save_out="${acl_save_out//$'\n'/}"
  if [ "${acl_save_rc}" -ne 0 ]; then
    echo "ERROR: ACL SAVE failed on ${dst_fqdn} with rc=${acl_save_rc}: ${acl_save_out} — rules applied in memory only, will be lost on restart" >&2
    return 1
  fi
  if [ "${acl_save_out}" != "OK" ]; then
    SYNC_ACL_RETRY_SAFE="no"
    echo "ERROR: ACL SAVE returned non-OK reply on ${dst_fqdn}: ${acl_save_out} — rules applied in memory only, will be lost on restart" >&2
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

if is_empty "${KB_JOIN_MEMBER_POD_FQDN}" || is_empty "${KB_JOIN_MEMBER_POD_NAME}"; then
  member_join_diagnose \
    "missing-join-member" "no" \
    "KB_JOIN_MEMBER_POD_NAME and KB_JOIN_MEMBER_POD_FQDN are both required."
  exit 1
fi

primary_fqdn=$(find_primary_fqdn) || {
  member_join_diagnose \
    "primary-not-yet-observable" "yes" \
    "No current data pod positively reported role:master."
  exit 1
}
if is_empty "${primary_fqdn}"; then
  member_join_diagnose \
    "primary-not-yet-observable" "yes" \
    "Primary lookup returned an empty address."
  exit 1
fi

# Don't sync from/to the same pod.
# Append "." to pod name so "valkey-1." is not a substring of "valkey-11.headless...".
if contains "${primary_fqdn}" "${KB_JOIN_MEMBER_POD_NAME}."; then
  echo "New member is the primary itself — no ACL sync needed."
  exit 0
fi

if ! sync_acl_to_replica "${primary_fqdn}" "${KB_JOIN_MEMBER_POD_FQDN}"; then
  member_join_diagnose \
    "acl-sync-incomplete" "${SYNC_ACL_RETRY_SAFE}" \
    "The target member did not positively complete ACL SETUSER plus ACL SAVE."
  exit 1
fi
