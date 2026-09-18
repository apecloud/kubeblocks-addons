#!/bin/bash
# valkey-cluster-check-role.sh — roleProbe for Valkey Cluster (sharding) mode.
# Phase C of issue #3021 (issue #3037).
#
# Contract: SINGLE-TOKEN role output (KB's EventTime gate applies).
# The versioned (role + uint64) path is deliberately NOT used: a version
# token must represent the COMPLETE role fact (including which pod is the
# shard primary, per 05a), and this pod's local myself-line epoch cannot
# prove shard-wide convergence of that fact during failover windows.
# A versioned probe would require multi-node view agreement per sample —
# deferred until designed properly (review: PR #3038 blocker 1).
#
# Pure read-and-emit: the probe never mutates anything. Unknown state is a
# non-zero exit (KB keeps the last trusted label and skips this sample) —
# NEVER an empty-string role (design review class 4: empty must not be a
# sentinel value).

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

build_cli_cmd() {
  cli_cmd=(valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}")
  if [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ]; then
    cli_cmd+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if [ -n "${VALKEY_CLI_TLS_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

# Prints "<role>" from this node's own CLUSTER NODES myself line, or fails
# (non-zero) when the line is absent or the role is unrecognizable.
probe_cluster_role() {
  local nodes myself flags role
  build_cli_cmd
  nodes=$("${cli_cmd[@]}" CLUSTER NODES 2>/dev/null) || {
    echo "role probe: CLUSTER NODES unreachable — skip sample." >&2
    return 1
  }
  myself=$(echo "${nodes}" | tr -d '\r' | awk '$3 ~ /myself/')
  if [ -z "${myself}" ]; then
    echo "role probe: no myself line in CLUSTER NODES — skip sample." >&2
    return 1
  fi
  flags=$(echo "${myself}" | awk '{print $3}')
  case "${flags}" in
    *master*) role="primary" ;;
    *slave*)  role="secondary" ;;
    *)
      echo "role probe: unrecognized flags '${flags}' — skip sample." >&2
      return 1 ;;
  esac
  echo "${role}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

load_common_library
probe_cluster_role
