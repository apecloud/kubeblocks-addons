#!/bin/bash
set -e
# account-provision.sh — called by KubeBlocks to create/update a database account.
#
# KubeBlocks injects:
#   KB_ACCOUNT_NAME      - logical account name (e.g., "default")
#   KB_ACCOUNT_PASSWORD  - generated password (from passwordGenerationPolicy)
#   KB_ACCOUNT_STATEMENT - the command to execute (ACL SETUSER ...)
#
# With targetPodSelector: Role / matchingKey: primary, this runs on the
# primary pod.  After applying the ACL locally, the script pushes the same
# ACL rule to all connected replicas (discovered via INFO REPLICATION).
# Valkey ACL is not replicated via the native replication stream — each
# node maintains its own users.acl.

port="${SERVICE_PORT:-6379}"

build_cli() {
  local host="${1:-127.0.0.1}"
  _cli=(valkey-cli --no-auth-warning -h "${host}" -p "${port}")
  if [ -n "${VALKEY_DEFAULT_PASSWORD}" ]; then
    _cli+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
    # shellcheck disable=SC2206
    _cli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

apply_acl() {
  local host="${1}" label="${2}"
  build_cli "${host}"

  local output
  output=$(echo "${KB_ACCOUNT_STATEMENT}" | "${_cli[@]}" 2>&1) || {
    echo "ERROR: account statement failed on ${label} (${host}): ${output}" >&2
    return 1
  }
  if [ "${output}" != "OK" ]; then
    echo "ERROR: account statement returned unexpected response on ${label} (${host}): ${output}" >&2
    return 1
  fi

  local acl_save_out
  acl_save_out=$("${_cli[@]}" ACL SAVE 2>&1) || {
    echo "ERROR: ACL SAVE failed on ${label} (${host}): ${acl_save_out}" >&2
    return 1
  }
  if [ "${acl_save_out}" != "OK" ]; then
    echo "ERROR: ACL SAVE returned unexpected response on ${label} (${host}): ${acl_save_out}" >&2
    return 1
  fi
}

# Apply on the local primary first.
apply_acl "127.0.0.1" "primary(local)"

# Discover connected replicas via INFO REPLICATION and push the ACL to each.
# Uses only real-time data from the engine — no stale env vars.
build_cli "127.0.0.1"
repl_info=$("${_cli[@]}" INFO REPLICATION 2>&1) || {
  echo "ERROR: INFO REPLICATION failed" >&2
  exit 1
}
repl_info="${repl_info//$'\r'/}"

online_ips=()
while IFS= read -r line; do
  case "${line}" in
    slave[0-9]*:*)
      ip=$(echo "${line}" | sed 's/.*ip=\([^,]*\).*/\1/')
      state=$(echo "${line}" | sed 's/.*state=\([^,]*\).*/\1/')
      if [ "${state}" = "online" ]; then
        online_ips+=("${ip}")
      fi
      ;;
  esac
done <<< "${repl_info}"

for ip in "${online_ips[@]}"; do
  apply_acl "${ip}" "replica(${ip})"
done
