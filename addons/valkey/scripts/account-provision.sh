#!/bin/bash
set -e
# account-provision.sh — called by KubeBlocks to create/update a database account.
#
# KubeBlocks injects:
#   KB_ACCOUNT_NAME      - logical account name (e.g., "default")
#   KB_ACCOUNT_PASSWORD  - generated password (from passwordGenerationPolicy)
#   KB_ACCOUNT_STATEMENT - the command to execute (ACL SETUSER ...)
#
# With targetPodSelector: All, KubeBlocks runs this on every pod.
# Each pod applies the ACL locally via ACL SETUSER + ACL SAVE.
# Valkey ACL is not replicated via the native replication stream —
# each node maintains its own users.acl, so every pod must be
# provisioned independently.

port="${SERVICE_PORT:-6379}"

cli_cmd=(valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}")
if [ -n "${VALKEY_DEFAULT_PASSWORD}" ]; then
  cli_cmd+=(-a "${VALKEY_DEFAULT_PASSWORD}")
fi
if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
  # shellcheck disable=SC2206
  cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
fi

output=$(echo "${KB_ACCOUNT_STATEMENT}" | "${cli_cmd[@]}" 2>&1) || {
  echo "ERROR: account statement failed: ${output}" >&2
  exit 1
}
if [ "${output}" != "OK" ]; then
  echo "ERROR: account statement returned unexpected response: ${output}" >&2
  exit 1
fi

acl_save_out=$("${cli_cmd[@]}" ACL SAVE 2>&1) || {
  echo "ERROR: ACL SAVE failed: ${acl_save_out}" >&2
  exit 1
}
if [ "${acl_save_out}" != "OK" ]; then
  echo "ERROR: ACL SAVE returned unexpected response: ${acl_save_out}" >&2
  exit 1
fi
