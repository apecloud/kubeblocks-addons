#!/bin/bash

# valkey-reset-master.sh — action of the valkey-reset-master OpsDefinition
# (port of the redis addon's reset-master.sh).
#
# Runs `SENTINEL RESET <master-name>` against the Sentinel fleet until one
# accepts.  Sentinel RESET drops all its knowledge about the master's
# replicas and peer Sentinels and triggers immediate re-discovery — used
# after operations that rebuild or replace an instance, so every Sentinel
# re-learns the current topology instead of trusting stale state.
#
# The ops pod targets the DATA component: KubeBlocks injects the sentinel
# cross-component vars (SENTINEL_POD_FQDN_LIST / SENTINEL_PASSWORD / …) into
# the valkey pods, so the pod FQDNs are read straight from the environment —
# redis assembles them from SENTINEL_HEADLESS_SERVICE_NAME + namespace
# instead because its data cmpd does not carry the FQDN list.
#
# Env (mapped by the OpsDefinition podInfoExtractor):
#   VALKEY_COMPONENT_NAME   — master name registered in Sentinel
#   SENTINEL_POD_FQDN_LIST  — FQDNs of the Sentinel pods
#   SENTINEL_PASSWORD       — Sentinel auth password (optional)
#   VALKEY_CLI_TLS_ARGS     — TLS flags for valkey-cli (optional)
#   CUSTOM_SENTINEL_MASTER_NAME — optional override of the master name

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

if [ -z "${SENTINEL_POD_FQDN_LIST}" ]; then
  echo "SENTINEL_POD_FQDN_LIST is empty — nothing to reset."
  exit 0
fi

master_name=${CUSTOM_SENTINEL_MASTER_NAME:-${VALKEY_COMPONENT_NAME}}
sentinel_service_port=${SENTINEL_SERVICE_PORT:-26379}

for sentinel_fqdn in $(echo "${SENTINEL_POD_FQDN_LIST}" | tr ',' '\n'); do
  [ -n "${sentinel_fqdn}" ] || continue
  echo "reset master in sentinel ${sentinel_fqdn}..."
  if [ -n "${SENTINEL_PASSWORD}" ]; then
    valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h "${sentinel_fqdn}" -p "${sentinel_service_port}" -a "${SENTINEL_PASSWORD}" sentinel reset "${master_name}"
  else
    valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h "${sentinel_fqdn}" -p "${sentinel_service_port}" sentinel reset "${master_name}"
  fi
  if [ $? -eq 0 ]; then
    echo "reset master in sentinel ${sentinel_fqdn} succeeded"
    exit 0
  fi
done
echo "reset master in sentinel failed"
exit 1
