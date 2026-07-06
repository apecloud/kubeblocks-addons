#!/bin/bash
# valkey-cluster-check-role.sh — roleProbe for Valkey Cluster (sharding) mode.
# Phase C of issue #3021 (issue #3037).
#
# Contract (KB role+version, post-#10280): stdout's first whitespace token is
# the role (must match a ComponentDefinition roles[] name), the optional
# second token is a uint64 role version the controller uses as a staleness
# gate against replayed events. We emit this shard's config-epoch as the
# version token (it increases on every failover — same anti-replay idea as
# the sentinel-mode probe).
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

# Prints "<role> <epoch>" from this node's own CLUSTER NODES myself line, or
# fails (non-zero) when the line is absent or the role is unrecognizable.
probe_cluster_role() {
  local nodes myself flags epoch role
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
  epoch=$(echo "${myself}" | awk '{print $7}')
  case "${epoch}" in
    ''|*[!0-9]*)
      echo "role probe: non-numeric config-epoch '${epoch}' — skip sample." >&2
      return 1 ;;
  esac
  case "${flags}" in
    *master*) role="primary" ;;
    *slave*)  role="secondary" ;;
    *)
      echo "role probe: unrecognized flags '${flags}' — skip sample." >&2
      return 1 ;;
  esac
  echo "${role} ${epoch}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

load_common_library
probe_cluster_role
