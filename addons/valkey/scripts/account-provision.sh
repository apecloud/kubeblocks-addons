#!/bin/sh
set -e
# account-provision.sh — called by KubeBlocks to create/update a database account.
#
# Learning note:
#   KubeBlocks injects three special variables before calling this action:
#     KB_ACCOUNT_NAME      - logical account name (e.g., "default")
#     KB_ACCOUNT_PASSWORD  - generated password (from passwordGenerationPolicy)
#     KB_ACCOUNT_STATEMENT - the command to execute, built by KubeBlocks
#
#   For Redis/Valkey, KB_ACCOUNT_STATEMENT is an ACL SETUSER command:
#     e.g. "ACL SETUSER myuser on >password ~* +@all"
#
#   Because Valkey's auth model is ACL-based (not SQL), the provision script
#   simply passes KB_ACCOUNT_STATEMENT verbatim to valkey-cli and then
#   calls ACL SAVE to persist the ACL file to disk.
#
#   The `initAccount: true` flag on the systemAccount means KubeBlocks
#   calls this action once during cluster initialisation, using the
#   "default" user.  Subsequent ACL changes go through OpsRequest.

port="${SERVICE_PORT:-6379}"

base_cmd="valkey-cli --no-auth-warning -p ${port}"
if [ -n "${VALKEY_DEFAULT_PASSWORD}" ]; then
  base_cmd="${base_cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
fi
if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
  base_cmd="${base_cmd} ${VALKEY_CLI_TLS_ARGS}"
fi

# Execute the statement provided by KubeBlocks.
# Pipe via stdin so that '>' in ACL password syntax (e.g. >mypassword) is not
# misinterpreted as a shell output-redirect operator.
# valkey-cli exits 0 even for protocol errors; capture output and check content.
output=$(echo "${KB_ACCOUNT_STATEMENT}" | ${base_cmd} 2>&1) || {
  echo "ERROR: account statement failed: ${output}" >&2
  exit 1
}
if [ "${output}" != "OK" ]; then
  echo "ERROR: account statement returned unexpected response: ${output}" >&2
  exit 1
fi

# Persist ACL to disk so it survives pod restarts
acl_save_out=$(${base_cmd} ACL SAVE 2>&1) || {
  echo "ERROR: ACL SAVE failed: ${acl_save_out}" >&2
  exit 1
}
if [ "${acl_save_out}" != "OK" ]; then
  echo "ERROR: ACL SAVE returned unexpected response: ${acl_save_out}" >&2
  exit 1
fi
