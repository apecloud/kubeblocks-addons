#!/bin/sh
set -e
# valkey-sentinel-account-provision.sh — run KubeBlocks-generated ACL statement
# on the Sentinel process and persist it.
#
# KubeBlocks injects:
#   KB_ACCOUNT_STATEMENT  — a full "ACL SETUSER ..." command
#
# Sentinel uses the same ACL mechanism as the data node.

sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"

if [ -n "${SENTINEL_PASSWORD}" ]; then
  cli="valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p ${sentinel_port} -a ${SENTINEL_PASSWORD}"
else
  cli="valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p ${sentinel_port}"
fi

# Pipe via stdin so that '>' in ACL password syntax (e.g. >mypassword) is not
# misinterpreted as a shell output-redirect operator.
# valkey-cli exits 0 even for protocol errors; capture output and check content.
output=$(echo "${KB_ACCOUNT_STATEMENT}" | ${cli} 2>&1) || {
  echo "ERROR: account statement failed: ${output}" >&2
  exit 1
}
if [ "${output}" != "OK" ]; then
  echo "ERROR: account statement returned unexpected response: ${output}" >&2
  exit 1
fi

acl_save_out=$(${cli} ACL SAVE 2>&1) || {
  echo "ERROR: ACL SAVE failed: ${acl_save_out}" >&2
  exit 1
}
if [ "${acl_save_out}" != "OK" ]; then
  echo "ERROR: ACL SAVE returned unexpected response: ${acl_save_out}" >&2
  exit 1
fi
