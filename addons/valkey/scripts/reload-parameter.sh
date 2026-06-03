#!/bin/bash
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
#   Unsupported/static parameters are ignored, but value validation failures
#   must fail closed so the reconfigure action cannot report a false success.

param_name="${1}"
param_value="${2}"

# Convert UPPER_UNDERSCORE to lower-hyphen (Valkey config naming convention)
valkey_param=$(echo "${param_name}" | tr '[:upper:]_' '[:lower:]-')

port="${SERVICE_PORT:-6379}"
# Use 'timeout' to prevent the reconfigure action from hanging indefinitely
# if Valkey is slow or unresponsive.
cli_cmd=(timeout 30 valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}")
if [ -n "${VALKEY_DEFAULT_PASSWORD}" ]; then
  cli_cmd+=(-a "${VALKEY_DEFAULT_PASSWORD}")
fi
if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
  # shellcheck disable=SC2206
  cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
fi

# valkey-cli exits 0 even for protocol errors; capture output and check content.
# Connection failures also fail closed; the caller should retry the action.
output=$("${cli_cmd[@]}" CONFIG SET "${valkey_param}" "${param_value}" 2>&1) || true
# Silently ignore parameters that do not support CONFIG SET (e.g. bind, port).
# Fail closed for other CONFIG SET errors so invalid dynamic values are surfaced.
case "${output}" in
  "OK") ;;   # success
  *"ERR Unknown option"*|*"not allowed"*|*"can't set"*) ;;
  *)
    echo "ERROR: CONFIG SET ${valkey_param} failed: ${output}" >&2
    exit 1
    ;;
esac
