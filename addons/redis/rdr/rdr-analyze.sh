#!/bin/bash
#
# Analyze Redis keys from an RDB snapshot with rdr.
#
# The script is executed by the redis-rdr-keys-analysis OpsDefinition. The
# OpsDefinition schedules this pod on the same node as the target Redis pod and
# mounts the target pod's `data` volume at /data, so the RDB file can be read
# without copying it through the network.
#
# Flow:
#   1. Trigger BGSAVE on the target Redis pod through redis-cli.
#   2. Wait until the BGSAVE finishes successfully.
#   3. Run `rdr dump2file` against the freshly written RDB file.
#   4. Save the JSON report to /data/rdr-report.json on the Redis data volume.
#   5. Print the JSON report between two markers. Logs go to stderr, but kubelet
#      merges both streams in `kubectl logs`, hence the markers.
#
# Environment variables (injected by the OpsDefinition / podInfoExtractor):
#   POD_FQDN                  FQDN of the target Redis pod.
#   CURRENT_POD_NAME          Name of the target Redis pod (fallback for POD_FQDN).
#   REDIS_COMPONENT_NAME      Redis component name (standalone/replication).
#   CURRENT_SHARD_COMPONENT_NAME
#                             Redis shard component name (cluster mode).
#   CLUSTER_NAMESPACE         Namespace of the Redis cluster.
#   CLUSTER_DOMAIN            Kubernetes cluster domain (fallback for POD_FQDN).
#   SERVICE_PORT              Redis service port.
#   REDIS_DEFAULT_USER        Redis default user.
#   REDIS_DEFAULT_PASSWORD    Redis default password.
#   REDIS_CLI_TLS_CMD         Extra redis-cli TLS arguments, e.g. "--tls --insecure".
#   DATA_DIR                  Mount path of the Redis data volume (default: /data).
#                             The report is written to ${DATA_DIR}/rdr-report.json.
#   TOP_N                     Top N big keys, 1-500 (default: 300).
#   SIZE_FILTER               Minimum key size, e.g. 0kb/10kb/1mb (default: 0kb).
#   NUM_OF_ELEM_MIN           Minimum element count for the big-key-by-count list (default: 3000).
#   SEPARATORS                Key prefix separators (default: ":;,_- ").
#   TOP_PREFIX                Top N key prefixes (default: 500).
#   PREFIX_SHRINK             Prefix container shrink watermark (default: 5000).
#   PREFIX_MAX_CAPACITY       Prefix container max capacity (default: 50000).
#   BGSAVE_TIMEOUT            Seconds to wait for BGSAVE (default: 600).
#   GOGC                      rdr Go GC percentage (default: 200).

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
SERVICE_PORT="${SERVICE_PORT:-6379}"
TOP_N="${TOP_N:-300}"
SIZE_FILTER="${SIZE_FILTER:-0kb}"
NUM_OF_ELEM_MIN="${NUM_OF_ELEM_MIN:-3000}"
SEPARATORS="${SEPARATORS:-:;,_- }"
TOP_PREFIX="${TOP_PREFIX:-500}"
PREFIX_SHRINK="${PREFIX_SHRINK:-5000}"
PREFIX_MAX_CAPACITY="${PREFIX_MAX_CAPACITY:-50000}"
BGSAVE_TIMEOUT="${BGSAVE_TIMEOUT:-600}"
export GOGC="${GOGC:-200}"

log() {
    echo "[rdr-keys-analysis] $*" >&2
}

fail() {
    log "ERROR: $*"
    exit 1
}

resolve_redis_host() {
    if [ -n "${POD_FQDN:-}" ]; then
        echo "${POD_FQDN}"
        return 0
    fi

    local component_name="${REDIS_COMPONENT_NAME:-${CURRENT_SHARD_COMPONENT_NAME:-}}"
    if [ -z "${CURRENT_POD_NAME:-}" ] || [ -z "${component_name}" ] || [ -z "${CLUSTER_NAMESPACE:-}" ]; then
        return 1
    fi
    echo "${CURRENT_POD_NAME}.${component_name}-headless.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN:-cluster.local}"
}

REDIS_HOST="$(resolve_redis_host)" || fail "cannot resolve the target Redis host (POD_FQDN is empty and the pod/component/namespace env vars are incomplete)"

CLI=(redis-cli --no-auth-warning)
if [ -n "${REDIS_CLI_TLS_CMD:-}" ]; then
    # REDIS_CLI_TLS_CMD is a space-separated argument list, e.g. "--tls --insecure".
    # shellcheck disable=SC2206
    CLI+=(${REDIS_CLI_TLS_CMD})
fi
CLI+=(-h "${REDIS_HOST}" -p "${SERVICE_PORT}")
if [ -n "${REDIS_DEFAULT_USER:-}" ]; then
    CLI+=(--user "${REDIS_DEFAULT_USER}")
fi
if [ -n "${REDIS_DEFAULT_PASSWORD:-}" ]; then
    CLI+=(-a "${REDIS_DEFAULT_PASSWORD}")
fi

log "connecting to Redis at ${REDIS_HOST}:${SERVICE_PORT}"
PING_OUTPUT="$("${CLI[@]}" PING 2>&1)" || fail "failed to connect to Redis: ${PING_OUTPUT}"
if ! printf '%s\n' "${PING_OUTPUT}" | grep -q 'PONG'; then
    fail "unexpected PING response: ${PING_OUTPUT}"
fi

RDB_FILENAME="dump.rdb"
if CONFIG_OUTPUT="$("${CLI[@]}" CONFIG GET dbfilename 2>/dev/null)"; then
    CONFIGURED_FILENAME="$(printf '%s\n' "${CONFIG_OUTPUT}" | tail -n 1 | tr -d '\r')"
    if [ -n "${CONFIGURED_FILENAME}" ]; then
        RDB_FILENAME="${CONFIGURED_FILENAME}"
    fi
else
    log "WARN: CONFIG GET dbfilename failed; falling back to ${RDB_FILENAME}"
fi

log "triggering BGSAVE on ${REDIS_HOST}:${SERVICE_PORT}"
LAST_SAVE_BEFORE="$("${CLI[@]}" LASTSAVE 2>/dev/null || echo 0)"
BGSAVE_OUTPUT="$("${CLI[@]}" BGSAVE 2>&1)" || true
log "BGSAVE response: ${BGSAVE_OUTPUT}"
case "${BGSAVE_OUTPUT}" in
    *"already in progress"*)
        log "a BGSAVE is already in progress; waiting for it to finish"
        ;;
    *"Background saving started"*)
        ;;
    *ERR* | *error*)
        fail "BGSAVE failed: ${BGSAVE_OUTPUT}"
        ;;
    *)
        log "unexpected BGSAVE response; waiting for the persistence state"
        ;;
esac

# Give Redis a moment to flip rdb_bgsave_in_progress, so the first INFO poll
# cannot mistake the previous successful save for this one.
sleep 2
DEADLINE=$(( $(date +%s) + BGSAVE_TIMEOUT ))
while :; do
    PERSISTENCE_INFO="$("${CLI[@]}" INFO persistence 2>/dev/null || true)"
    IN_PROGRESS="$(printf '%s\n' "${PERSISTENCE_INFO}" | tr -d '\r' | awk -F: '/^rdb_bgsave_in_progress:/{print $2; exit}')"
    LAST_STATUS="$(printf '%s\n' "${PERSISTENCE_INFO}" | tr -d '\r' | awk -F: '/^rdb_last_bgsave_status:/{print $2; exit}')"

    if [ "${IN_PROGRESS}" = "0" ]; then
        if [ "${LAST_STATUS}" != "ok" ]; then
            fail "last BGSAVE status is '${LAST_STATUS}'"
        fi
        LAST_SAVE_NOW="$("${CLI[@]}" LASTSAVE 2>/dev/null || echo 0)"
        if [ "${LAST_SAVE_NOW}" -ge "${LAST_SAVE_BEFORE}" ]; then
            log "BGSAVE completed (lastsave=${LAST_SAVE_NOW})"
            break
        fi
    fi

    if [ "$(date +%s)" -ge "${DEADLINE}" ]; then
        fail "BGSAVE did not complete within ${BGSAVE_TIMEOUT}s"
    fi
    sleep 2
done

RDB_FILE="${DATA_DIR}/${RDB_FILENAME}"
if [ ! -f "${RDB_FILE}" ]; then
    log "WARN: ${RDB_FILE} not found; searching ${DATA_DIR} for the newest .rdb file"
    RDB_FILE="$(find "${DATA_DIR}" -maxdepth 2 -type f -name '*.rdb' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2- || true)"
fi
if [ -z "${RDB_FILE}" ] || [ ! -f "${RDB_FILE}" ]; then
    fail "RDB file not found under ${DATA_DIR}"
fi
log "analyzing RDB file ${RDB_FILE} ($(du -h "${RDB_FILE}" | cut -f1))"

WORK_DIR="$(mktemp -d /tmp/rdr-keys-analysis.XXXXXX)"
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

cd "${WORK_DIR}"
set +e
rdr dump2file \
    -n "${TOP_N}" \
    -s "${SIZE_FILTER}" \
    -sn "${NUM_OF_ELEM_MIN}" \
    -sep "${SEPARATORS}" \
    -pn "${TOP_PREFIX}" \
    -psn "${PREFIX_SHRINK}" \
    -pmn "${PREFIX_MAX_CAPACITY}" \
    "${RDB_FILE}" >"${WORK_DIR}/rdr.stdout" 2>"${WORK_DIR}/rdr.stderr"
RDR_EXIT_CODE=$?
set -e

cat "${WORK_DIR}/rdr.stdout" >&2
cat "${WORK_DIR}/rdr.stderr" >&2
if [ "${RDR_EXIT_CODE}" -ne 0 ]; then
    fail "rdr exited with code ${RDR_EXIT_CODE}"
fi
if grep -qE 'decode rdb file err|open rdb file err' "${WORK_DIR}/rdr.stderr"; then
    fail "rdr failed to parse the RDB file (unsupported data type or RDB version; see the errors above)"
fi

REPORT_FILE="$(find "${WORK_DIR}" -maxdepth 1 -type f -name 'rdb-report-*.json' | head -n 1)"
if [ -z "${REPORT_FILE}" ] || [ ! -f "${REPORT_FILE}" ]; then
    fail "rdr did not produce a JSON report"
fi
if [ "$(head -c 1 "${REPORT_FILE}")" != "[" ]; then
    fail "rdr report is not a JSON array: ${REPORT_FILE}"
fi
log "report generated at ${REPORT_FILE}"

# Persist the report on the Redis data volume so it can be retrieved from the
# target Redis pod (which mounts the same PVC at /data) after this Pod finishes.
REPORT_OUTPUT_FILE="${DATA_DIR}/rdr-report.json"
REPORT_OUTPUT_TMP="${REPORT_OUTPUT_FILE}.tmp.$$"
if ! cp "${REPORT_FILE}" "${REPORT_OUTPUT_TMP}"; then
    fail "failed to write ${REPORT_OUTPUT_TMP}; make sure the data volume is mounted read-write"
fi
if ! mv "${REPORT_OUTPUT_TMP}" "${REPORT_OUTPUT_FILE}"; then
    rm -f "${REPORT_OUTPUT_TMP}"
    fail "failed to move the report to ${REPORT_OUTPUT_FILE}"
fi
sync
log "report saved to ${REPORT_OUTPUT_FILE}"

# kubelet merges stdout and stderr in `kubectl logs`, so wrap the JSON with
# markers to make it easy to extract:
#   kubectl logs <pod> | sed -n '/^===== RDR JSON REPORT BEGIN =====$/,/^===== RDR JSON REPORT END =====$/p' | sed '1d;$d'
echo "===== RDR JSON REPORT BEGIN ====="
cat "${REPORT_OUTPUT_FILE}"
echo
echo "===== RDR JSON REPORT END ====="
