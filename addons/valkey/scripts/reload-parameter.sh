#!/bin/bash
# reload-parameter.sh — apply one changed parameter to the running Valkey server.
#
# Invocation (KubeBlocks 1.0):
#   ParametersDefinition.spec.reloadAction.shellTrigger runs
#       reload-parameter.sh <parameter-name> <value>
#   once per changed dynamic parameter, inside the config-manager sidecar.  The
#   sidecar is built from the Valkey image (asContainerImage: true), so
#   valkey-cli below is available, and the component vars (SERVICE_PORT,
#   VALKEY_DEFAULT_PASSWORD, VALKEY_CLI_TLS_ARGS) are injected into it.
#
#   The parameter name is the config file key as declared by the CUE schema, so
#   it is passed to CONFIG SET unchanged.  Static and immutable parameters never
#   reach this script — KubeBlocks only calls it for the parameters listed in
#   ParametersDefinition.spec.dynamicParameters.
#
#   A non-zero exit marks the whole reconfigure as failed, so everything except
#   a confirmed successful CONFIG SET must fail closed.

param_name="${1:?missing parameter name}"
param_value="${2:-}"

cli_cmd=(timeout 30 valkey-cli --no-auth-warning -h 127.0.0.1 -p "${SERVICE_PORT:-6379}")
if [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ]; then
  cli_cmd+=(-a "${VALKEY_DEFAULT_PASSWORD}")
fi
if [ -n "${VALKEY_CLI_TLS_ARGS:-}" ]; then
  # shellcheck disable=SC2206 # intentional splitting: "--tls --cacert <path>/ca.crt"
  cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
fi

# valkey-cli exits 0 even for protocol errors, so the reply text is the verdict.
output=$("${cli_cmd[@]}" CONFIG SET "${param_name}" "${param_value}" 2>&1) || true
if [ "${output}" = "OK" ]; then
  exit 0
fi

echo "ERROR: CONFIG SET ${param_name} failed: ${output}" >&2
exit 1
