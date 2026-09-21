#!/bin/bash
# valkey-account.sh — on-demand account (ACL) management for the account OpsRequest.
#
# Inlined into the ops pod by templates/opsdefinition-account.yaml (the ops pod
# does not mount the scripts ConfigMap), so this file must stay self-contained:
# it must not source /scripts/common.sh.
#
# Contract (same as redis/scripts/redis-account.sh):
#   ACL_COMMAND      — the full ACL statement to run on every pod, e.g.
#                      'ACL SETUSER alice-sen on ~* &* +@all #<hash>' or
#                      'ACL DELUSER alice-sen'
#   REPLICAS         — expected number of pods the command must reach; the ops
#                      fails unless every one of them answered
#   VALKEY_POD_FQDN_LIST / SERVICE_PORT / VALKEY_DEFAULT_USER /
#   VALKEY_DEFAULT_PASSWORD — target pods and admin credentials
#   TLS_ENABLED              — forwarded by the podInfoExtractor (tlsVarRef);
#                              the only TLS switch, exactly like the redis
#                              addon's REDIS_CLI_TLS_CMD-driven decision
#
# Valkey deltas vs redis:
#   - Replication topology only (no cluster/shard mode), so the CLUSTER NODES
#     discovery path of the redis script is not needed.
#   - ACL_COMMAND is split into an argv array instead of relying on unquoted
#     expansion, and REPLICAS defaults to the number of hosts in the list.

set -e

service_port="${SERVICE_PORT:-6379}"

# build_cli <host> <port> <user> <password> — fills the global _cli array.
# TLS decision — same as the redis addon: TLS_ENABLED (injected by the
# ComponentDefinition from tlsVarRef and forwarded into the ops pod by the
# podInfoExtractor) is the only switch; the ops pod does not mount the TLS
# volume, so no CA file is available in this execution face and --tls
# --insecure is the only workable form (in-pod scripts verify via --cacert).
# Evaluated per call, like the redis addon's $REDIS_CLI_TLS_CMD expansion.
build_cli() {
  local host="$1" port="$2" user="$3" password="$4"
  local -a tls=()
  if [ "${TLS_ENABLED:-false}" = "true" ]; then
    tls=(--tls --insecure)
  fi
  _cli=(valkey-cli --no-auth-warning "${tls[@]}" -h "${host}" -p "${port}" --user "${user}")
  if [ -n "${password}" ]; then
    _cli+=(-a "${password}")
  fi
}

env_pre_check() {
  if [ -z "${ACL_COMMAND}" ]; then
    echo "ERROR: ACL_COMMAND is empty, nothing to do." >&2
    exit 1
  fi
  if [ -z "${VALKEY_DEFAULT_USER}" ]; then
    echo "ERROR: VALKEY_DEFAULT_USER is empty, cannot authenticate." >&2
    exit 1
  fi
  if [ -z "${VALKEY_POD_FQDN_LIST}" ]; then
    echo "ERROR: VALKEY_POD_FQDN_LIST is empty, cannot reach any pod." >&2
    exit 1
  fi
}

# create_post_check <success_count> <expected> — the ops succeeds only when the
# command reached exactly the expected number of pods (redis contract).
create_post_check() {
  local success_count="$1" expected="$2"
  if [ "${success_count}" -eq "${expected}" ]; then
    echo "DO ACL COMMAND FOR ALL ${expected} HOSTS SUCCESS"
    exit 0
  fi
  echo "ERROR: expected ${expected} hosts account updated, only ${success_count} succeeded" >&2
  exit 1
}

do_acl_command() {
  local hosts="$1" user="$2" password="$3"
  local -a host_list=() acl_args=()
  local host port expected success_count=0 output exit_code

  IFS=',' read -ra host_list <<< "${hosts}"
  expected="${REPLICAS:-}"
  if [ -z "${expected}" ]; then
    expected="${#host_list[@]}"
    echo "INFO: REPLICAS is not set — expecting all ${expected} hosts in the list."
  fi

  IFS=' ' read -ra acl_args <<< "${ACL_COMMAND}"

  for host in "${host_list[@]}"; do
    [ -n "${host}" ] || continue
    # Tolerate "host:port" entries; plain pod FQDNs keep the default port.
    port="${service_port}"
    case "${host}" in
      *:*)
        port="${host##*:}"
        host="${host%%:*}"
        ;;
    esac
    build_cli "${host}" "${port}" "${user}" "${password}"

    echo "DO ACL COMMAND FOR HOST: ${host}"
    exit_code=0
    output=$("${_cli[@]}" "${acl_args[@]}" 2>&1) || exit_code=$?
    # valkey-cli exits 0 for some protocol errors — check the answer too.
    case "${output}" in
      ERR*|*"(error)"*)
        echo "DO ACL COMMAND FOR HOST: ${host} FAILED" >&2
        echo "Exit Code: ${exit_code}" >&2
        echo "Output: ${output}" >&2
        exit 1
        ;;
    esac
    if [ "${exit_code}" -ne 0 ]; then
      echo "DO ACL COMMAND FOR HOST: ${host} FAILED" >&2
      echo "Exit Code: ${exit_code}" >&2
      echo "Output: ${output}" >&2
      exit 1
    fi

    echo "DO ACL SAVE FOR HOST: ${host}"
    exit_code=0
    output=$("${_cli[@]}" ACL SAVE 2>&1) || exit_code=$?
    if [ "${exit_code}" -ne 0 ] || [ "${output}" != "OK" ]; then
      echo "DO ACL SAVE FOR HOST: ${host} FAILED (exit=${exit_code}, output=${output:-<empty>})" >&2
      exit 1
    fi
    success_count=$((success_count + 1))
  done

  create_post_check "${success_count}" "${expected}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
# No `ut_mode` / `set -x` block on purpose: the ACL commands carry the account
# password via `-a`, and xtrace would print it into the ops pod log.
env_pre_check
do_acl_command "${VALKEY_POD_FQDN_LIST}" "${VALKEY_DEFAULT_USER}" "${VALKEY_DEFAULT_PASSWORD}"
