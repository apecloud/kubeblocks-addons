#!/bin/bash
# post-provision.sh — postProvision action, runs on the primary after component creation.
#
# Learning note:
#   postProvision runs ONCE after all component pods are Ready.
#   targetPodSelector: Role + matchingKey: primary means only the current
#   primary executes this — other pods skip it.
#
#   Typical uses:
#     - Verify replication is working
#     - Register with an external sentinel (see redis addon for that pattern)
#     - Run initial data seeding
#
#   For vanilla Valkey replication we just check that replicas have connected.

set -e

port="${SERVICE_PORT:-6379}"
expected_replicas=$(( COMPONENT_REPLICAS - 1 ))

cli_cmd="valkey-cli --no-auth-warning -h 127.0.0.1 -p ${port}"
if [ -n "${VALKEY_DEFAULT_PASSWORD}" ]; then
  cli_cmd="${cli_cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
fi
if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
  cli_cmd="${cli_cmd} ${VALKEY_CLI_TLS_ARGS}"
fi

# In standalone mode there are no replicas to check
if [ "${expected_replicas}" -le 0 ]; then
  echo "postProvision: standalone mode — nothing to verify."
  exit 0
fi

echo "postProvision: waiting for ${expected_replicas} replica(s) to connect..."
max_wait=60
elapsed=0
connected=0
while [ "${elapsed}" -lt "${max_wait}" ]; do
  connected=$(${cli_cmd} info replication 2>/dev/null \
    | grep "^connected_slaves:" | cut -d: -f2 | tr -d '\r\n') || true
  if [ "${connected}" = "${expected_replicas}" ]; then
    echo "postProvision: all ${expected_replicas} replica(s) connected."
    exit 0
  fi
  sleep 2
  elapsed=$(( elapsed + 2 ))
done

echo "postProvision: WARNING — only ${connected}/${expected_replicas} replicas connected after ${max_wait}s."
# Non-fatal — don't block cluster creation
exit 0
