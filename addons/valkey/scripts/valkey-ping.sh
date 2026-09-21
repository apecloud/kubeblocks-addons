#!/bin/sh
# valkey-ping.sh — readinessProbe for the valkey container.
#
# Learning note:
#   readinessProbe uses a simple PING/PONG check.  This is separate from
#   roleProbe: readiness is about "is the server accepting connections?"
#   while roleProbe is about "what role does this replica have?".
#   Both probes run independently.

port="${SERVICE_PORT:-6379}"

if [ -n "${VALKEY_DEFAULT_PASSWORD}" ]; then
  response=$(valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}" -a "${VALKEY_DEFAULT_PASSWORD}" ${VALKEY_CLI_TLS_ARGS} PING 2>/dev/null)
else
  response=$(valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}" ${VALKEY_CLI_TLS_ARGS} PING 2>/dev/null)
fi

[ "${response}" = "PONG" ]
