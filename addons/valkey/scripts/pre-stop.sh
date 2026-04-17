#!/bin/bash
# pre-stop.sh — preStop hook for graceful shutdown.
#
# Learning note:
#   Kubernetes calls preStop before sending SIGTERM.  For a Valkey primary,
#   we trigger a BGSAVE to flush the RDB so the data is durable before the
#   pod exits.  We also optionally initiate a REPLICAOF NO ONE on ourselves
#   to detach cleanly (though Kubernetes will terminate us regardless).
#
#   We do NOT block indefinitely here — the terminationGracePeriodSeconds
#   on the Pod spec provides the hard deadline.

set -e

port="${SERVICE_PORT:-6379}"

cli_cmd="valkey-cli --no-auth-warning -h 127.0.0.1 -p ${port}"
if [ -n "${VALKEY_DEFAULT_PASSWORD}" ]; then
  { set +x; } 2>/dev/null
  cli_cmd="${cli_cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
fi
if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
  cli_cmd="${cli_cmd} ${VALKEY_CLI_TLS_ARGS}"
fi

echo "preStop: triggering BGSAVE..."
# Record the timestamp of the last completed save before we start a new one.
last_save_before=$(${cli_cmd} LASTSAVE 2>/dev/null || echo "0")
${cli_cmd} BGSAVE 2>/dev/null || true

# Wait until LASTSAVE advances past the pre-BGSAVE timestamp (max 30 s).
for i in $(seq 1 30); do
  sleep 1
  in_progress=$(${cli_cmd} INFO persistence 2>/dev/null \
    | grep rdb_bgsave_in_progress | tr -d '\r' | cut -d: -f2)
  # If bgsave_in_progress is empty the server may be unreachable; break safely.
  [ -z "${in_progress}" ] && break
  if [ "${in_progress}" = "0" ]; then
    current_save=$(${cli_cmd} LASTSAVE 2>/dev/null || echo "0")
    if [ "${current_save}" -gt "${last_save_before}" ]; then
      echo "preStop: BGSAVE completed (${current_save})."
      break
    fi
  fi
done

echo "preStop: done."
