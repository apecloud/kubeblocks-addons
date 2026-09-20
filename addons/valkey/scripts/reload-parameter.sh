#!/bin/bash
# reload-parameter.sh — hot-reload a single configuration parameter.
#
# Invocation (KubeBlocks 1.0):
#   ParametersDefinition.spec.reloadAction.shellTrigger runs
#       reload-parameter.sh <parameter-name> <value>
#   once per changed dynamic parameter, inside the config-manager sidecar.  The
#   sidecar uses the Valkey image, so valkey-cli below is available, and the
#   component env vars (SERVICE_PORT, VALKEY_DEFAULT_PASSWORD,
#   VALKEY_CLI_TLS_ARGS) are injected into it.
#
#   This script translates the parameter name from environment-variable style
#   (MAXMEMORY_POLICY) to Valkey config style (maxmemory-policy) and runs
#   CONFIG SET on the live server.
#
#   Not all parameters support CONFIG SET (e.g., bind, port require restart).
#   Unsupported/static parameters are ignored, but value validation failures
#   must fail closed so the reload cannot report a false success.

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
# Exit codes:
#   0 — CONFIG SET succeeded; caller should verify with CONFIG GET.
#   2 — static/immutable parameter, silently skipped; no verify needed.
#   1 — real CONFIG SET error (invalid value, connection failure); fail closed.
case "${output}" in
  "OK") exit 0 ;;
  *"ERR Unknown option"*|*"not allowed"*|*"can't set"*) exit 2 ;;
  *)
    echo "ERROR: CONFIG SET ${valkey_param} failed: ${output}" >&2
    exit 1
    ;;
esac
