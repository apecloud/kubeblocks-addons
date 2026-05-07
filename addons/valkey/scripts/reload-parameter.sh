#!/bin/sh
# reload-parameter.sh — hot-reload a single configuration parameter.
#
# Learning note:
#   KubeBlocks calls the reconfigure action when a config parameter changes.
#   The action script iterates all env vars and calls this script once per
#   parameter.  This script translates the parameter name from
#   environment-variable style (MAXMEMORY_POLICY) to Valkey config style
#   (maxmemory-policy) and runs CONFIG SET on the live server.
#
#   Not all parameters support CONFIG SET (e.g., bind, port require restart).
#   We silently ignore errors for unsupported parameters.

param_name="${1}"
param_value="${2}"

# Convert UPPER_UNDERSCORE to lower-hyphen (Valkey config naming convention)
valkey_param=$(echo "${param_name}" | tr '[:upper:]_' '[:lower:]-')

port="${SERVICE_PORT:-6379}"
# Use 'timeout' to prevent the reconfigure action from hanging indefinitely
# if Valkey is slow or unresponsive.
cli_cmd="timeout 30 valkey-cli --no-auth-warning -h 127.0.0.1 -p ${port}"
if [ -n "${VALKEY_DEFAULT_PASSWORD}" ]; then
  cli_cmd="${cli_cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
fi
if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
  cli_cmd="${cli_cmd} ${VALKEY_CLI_TLS_ARGS}"
fi

# valkey-cli exits 0 even for protocol errors; capture output and check content.
output=$(${cli_cmd} CONFIG SET "${valkey_param}" "${param_value}" 2>&1) || true
# Silently ignore parameters that do not support CONFIG SET (e.g. bind, port).
# Log a warning only when the error is not "ERR Unknown option" or similar
# (which indicate a static/unsupported param) so that invalid values are surfaced.
case "${output}" in
  "OK") ;;   # success
  *"ERR Unknown option"*|*"not allowed"*|*"can't set"*) ;;
  *) echo "WARNING: CONFIG SET ${valkey_param} failed: ${output}" >&2 ;;
esac
