#!/bin/sh
# Called by KubeBlocks runtime (controller / kbagent) when a member is joining
# the Galera cluster. Single-shot bootstrap-or-defer pattern: each invocation
# observes the synced marker once and decides whether to close the action or
# defer to the next re-fire. Does NOT poll in-process — that would hit
# kbagent's hardcoded 60s maxActionCallTimeout for any non-trivial Galera SST.
#
# galera-start.sh runs inside the mariadb container's main entrypoint and
# writes ${DATA_DIR}/.galera-synced after it observes wsrep_local_state=4
# (Synced) via the Unix socket. This script only checks for that marker and
# classifies the result for the next re-fire.
#
# Contract per skills/addon-lifecycle-single-shot-bootstrap-or-defer:
#   - rc=0 == genuinely synced (positive observation of the marker file).
#   - rc=1 with "next-retry-safe: yes" == still bootstrapping (SST in flight,
#     galera-start.sh has not yet written the marker); the runtime will
#     re-invoke this action and a future call will observe the marker.
#   - rc=1 with "next-retry-safe: no" == operator-attention failure
#     (DATA_DIR missing entirely == script preconditions broken).

DATA_DIR="${DATA_DIR:-/var/lib/mysql}"
SYNCED_FILE="${DATA_DIR}/.galera-synced"
ROLE_FILE="${DATA_DIR}/.galera-role"

galera_member_join_diagnose_not_ready() {
    phase="$1"
    ctx="$2"
    retry_safe="$3"
    {
        echo "memberJoin diagnosis:"
        echo "  action: galera-member-join"
        echo "  phase: ${phase}"
        echo "  cluster: ${KB_CLUSTER_NAME:-<unset>}"
        echo "  pod: ${KB_JOIN_MEMBER_POD_NAME:-<unset>}"
        echo "  data_dir: ${DATA_DIR}"
        echo "  synced_marker: ${SYNCED_FILE}"
        echo "${ctx}"
        echo "  next-retry-safe: ${retry_safe}"
    } >&2
}

if [ ! -d "${DATA_DIR}" ]; then
    galera_member_join_diagnose_not_ready \
        "data-dir-missing" \
        "  data_dir_exists: no" \
        "no"
    exit 1
fi

if [ -f "${SYNCED_FILE}" ]; then
    role="$(cat "${ROLE_FILE}" 2>/dev/null || true)"
    if [ "${role}" = "primary" ]; then
        echo "Galera node synced (${SYNCED_FILE} present, role=primary). Member join complete."
        exit 0
    fi

    galera_member_join_diagnose_not_ready \
        "synced-marker-stale-or-role-not-primary" \
        "  data_dir_exists: yes
  synced_marker_present: yes
  role_file: ${ROLE_FILE}
  role: ${role:-<missing>}
  hint: galera-start.sh must observe current wsrep_local_state=4 and wsrep_cluster_status=Primary before memberJoin can close." \
        "yes"
    exit 1
fi

galera_member_join_diagnose_not_ready \
    "sst-not-yet-synced" \
    "  data_dir_exists: yes
  synced_marker_present: no
  role_file: ${ROLE_FILE}
  hint: galera-start.sh writes this marker once wsrep_local_state reaches 4 (Synced); SST may still be in progress." \
    "yes"
exit 1
