#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

source /scripts/common.sh

# Switchover readiness gate — single-shot check-or-defer.
#
# kbagent clamps every lifecycle-action invocation at 60s (SIGKILL on
# overrun, which also eats the script's own diagnostics). Waiting for AG
# replica convergence therefore belongs to the declared retryPolicy
# (cmpd.yaml: maxRetries=5, retryInterval=10s), NOT to an in-script loop.
# Each invocation either positively observes readiness and proceeds, or
# classifies why it is deferring and exits 1 so the retry layer re-invokes.
#
# Time budget (worst case, bounds enforced by sqlcmd flags):
#   probe 1:                -l 3 (login) + -t 5 (query)  <=  8s
#   inter-probe sleep:                                       3s
#   probe 2:                -l 3 + -t 5                  <=  8s
#   per-DB detail (readiness-defer path only): -l 3 + -t 3 <= 6s
#   successful readiness path                            <= 19s
#   syncerctl: 15s TERM deadline + 1s KILL/reap          <= 16s
#   failure post-check: 3 * (-l 1 + -t 2) + 2 * sleep 1 <= 11s
#   mutation + post-check path                           <= 46s
# leaving >= 14s buffer under the 60s kbagent clamp.
#
# NOTE: conn_local honors MSSQL_LOGIN_TIMEOUT/MSSQL_QUERY_TIMEOUT at call
# time, but it lacks the -h -1 -W (headerless, trimmed) flags needed for
# robust output parsing, so the probes invoke $SQLCMD directly.

PROBE_LOGIN_TIMEOUT=3
PROBE_QUERY_TIMEOUT=5
DETAIL_QUERY_TIMEOUT=3
PROBE_SLEEP=3
MAX_PROBES=2
SWITCHOVER_TIMEOUT_SECONDS=15
SWITCHOVER_KILL_AFTER_SECONDS=1
POSTCHECK_LOGIN_TIMEOUT=1
POSTCHECK_QUERY_TIMEOUT=2
POSTCHECK_SLEEP=1
POSTCHECK_MAX_PROBES=3

if [ "$KB_SWITCHOVER_ROLE" != "primary" ]; then
    log "switchover not triggered for primary, nothing to do, exit 0."
    exit 0
fi

candidate="$KB_SWITCHOVER_CANDIDATE_NAME"
ag_name="${DEFAULT_AG_NAME:-ag1}"

if [ -z "$candidate" ]; then
    # Do NOT gate all replicas here: without a named candidate the syncer
    # picks the target itself, and gating every replica would block valid
    # switchovers on one lagging follower.
    log "no candidate specified; readiness gate skipped — syncer selects candidate"
else
    # SET NOCOUNT ON + sqlcmd -h -1 -W => output is exactly one data row
    # "ready_count total_count" (no headers, no "(N rows affected)" trailer).
    readiness_sql="SET NOCOUNT ON;
SELECT
  ISNULL(SUM(CASE WHEN dcs.is_failover_ready = 1 AND dcs.is_database_joined = 1 THEN 1 ELSE 0 END), 0) AS ready_count,
  COUNT(*) AS total_count
FROM sys.dm_hadr_database_replica_cluster_states dcs
JOIN sys.availability_replicas ar ON dcs.replica_id = ar.replica_id
WHERE ar.replica_server_name = '$candidate'"

    detail_sql="SET NOCOUNT ON;
SELECT
  adc.database_name,
  dcs.is_database_joined,
  dcs.is_failover_ready
FROM sys.dm_hadr_database_replica_cluster_states dcs
JOIN sys.availability_replicas ar ON dcs.replica_id = ar.replica_id
JOIN sys.availability_databases_cluster adc ON dcs.group_database_id = adc.group_database_id
WHERE ar.replica_server_name = '$candidate'"

    probe_candidate_readiness() {
        "$SQLCMD" -x -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" \
            -C -l "$PROBE_LOGIN_TIMEOUT" -t "$PROBE_QUERY_TIMEOUT" -h -1 -W -b -Q "$readiness_sql"
    }

    ready=""
    total=""
    ready_ok=false
    no_rows_probes=0

    attempt=0
    while [ "$attempt" -lt "$MAX_PROBES" ]; do
        attempt=$((attempt + 1))

        result=$(probe_candidate_readiness 2>&1)
        rc=$?

        if [ $rc -ne 0 ]; then
            log "candidate $candidate readiness probe failed (rc=$rc, attempt $attempt/$MAX_PROBES): $result"
        else
            # Token-match the last line carrying two integer columns; ignore
            # any sqlcmd warning noise. Guards against empty/non-numeric
            # values before any -eq comparison.
            parsed=$(printf '%s\n' "$result" | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {r=$1; t=$2; found=1} END {if (found) print r, t}')
            ready="${parsed%% *}"
            total="${parsed##* }"

            if [ -z "$parsed" ]; then
                log "candidate $candidate readiness probe returned unparseable output (attempt $attempt/$MAX_PROBES): $result"
                ready=""
                total=""
            elif [ "$total" -eq 0 ]; then
                no_rows_probes=$((no_rows_probes + 1))
                log "candidate $candidate: readiness query returned no database rows (attempt $attempt/$MAX_PROBES)"
            elif [ "$ready" -eq "$total" ]; then
                ready_ok=true
                break
            else
                log "candidate $candidate: $ready/$total database(s) failover-ready (attempt $attempt/$MAX_PROBES)"
            fi
        fi

        if [ "$attempt" -lt "$MAX_PROBES" ]; then
            sleep "$PROBE_SLEEP"
        fi
    done

    if [ "$ready_ok" != "true" ]; then
        if [ "$no_rows_probes" -ge 2 ]; then
            # Deterministic operator-attention state: the candidate has no
            # databases participating in the AG, so retrying will observe
            # the same result. Distinct from the transient defer below.
            log "ERROR: candidate $candidate has no databases in AG $ag_name — check membership; NOT retry-safe"
            exit 1
        fi

        detail=$("$SQLCMD" -x -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" \
            -C -l "$PROBE_LOGIN_TIMEOUT" -t "$DETAIL_QUERY_TIMEOUT" -h -1 -W -b -Q "$detail_sql" 2>&1)
        log "candidate $candidate per-DB status: $detail"
        log "defer: ${ready:-unknown}/${total:-unknown} candidate databases failover-ready; retry-safe"
        exit 1
    fi

    log "candidate $candidate: all $total database(s) failover-ready, proceeding with switchover"
fi

switchover_output=$(
    timeout -k "${SWITCHOVER_KILL_AFTER_SECONDS}s" "${SWITCHOVER_TIMEOUT_SECONDS}s" \
        /tools/syncerctl switchover \
        --primary "$KB_SWITCHOVER_CURRENT_NAME" \
        ${KB_SWITCHOVER_CANDIDATE_NAME:+--candidate "$KB_SWITCHOVER_CANDIDATE_NAME"} 2>&1
)
switchover_rc=$?

if [ "$switchover_rc" -eq 0 ]; then
    log "switchover command completed successfully: $switchover_output"
    exit 0
fi

log "switchover command failed (rc=$switchover_rc): $switchover_output"

if [ -z "$candidate" ]; then
    log "ERROR: non-targeted switchover failed and has no candidate topology to verify; NOT retry-safe"
    exit 1
fi

# A duplicate action can reach syncer after the first invocation has already
# moved leadership away from KB_SWITCHOVER_CURRENT_NAME. In that state syncer
# correctly rejects the stale old-primary request, but failing the action would
# turn a completed product transition into a terminal OpsRequest failure.
#
# Query the candidate because a SQL Server primary can observe the role of all
# AG replicas. Idempotent success requires both axes in the same sample:
# candidate=PRIMARY(1) and old primary=SECONDARY(2). Unknown or partial state is
# never treated as success.
postcheck_sql="SET NOCOUNT ON;
SELECT ar.replica_server_name, ars.role
FROM sys.availability_replicas ar
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ar.replica_server_name IN ('$KB_SWITCHOVER_CURRENT_NAME', '$candidate')"

postcheck_attempt=0
while [ "$postcheck_attempt" -lt "$POSTCHECK_MAX_PROBES" ]; do
    postcheck_attempt=$((postcheck_attempt + 1))
    postcheck_output=$(
        MSSQL_LOGIN_TIMEOUT="$POSTCHECK_LOGIN_TIMEOUT" \
        MSSQL_QUERY_TIMEOUT="$POSTCHECK_QUERY_TIMEOUT" \
        conn_pod "$candidate" "$postcheck_sql" 2>&1
    )
    postcheck_rc=$?

    current_role=""
    candidate_role=""
    if [ "$postcheck_rc" -eq 0 ]; then
        current_role=$(
            printf '%s\n' "$postcheck_output" |
                awk -v name="$KB_SWITCHOVER_CURRENT_NAME" \
                    '$1 == name && $2 ~ /^[0-9]+$/ {role=$2} END {print role}'
        )
        candidate_role=$(
            printf '%s\n' "$postcheck_output" |
                awk -v name="$candidate" \
                    '$1 == name && $2 ~ /^[0-9]+$/ {role=$2} END {print role}'
        )
    fi

    if [ "$current_role" = "2" ] && [ "$candidate_role" = "1" ]; then
        log "switchover already converged after command failure: candidate $candidate is primary and old primary $KB_SWITCHOVER_CURRENT_NAME is secondary"
        exit 0
    fi

    log "switchover post-check not yet converged (attempt $postcheck_attempt/$POSTCHECK_MAX_PROBES, rc=$postcheck_rc, old-primary-role=${current_role:-unknown}, candidate-role=${candidate_role:-unknown}): $postcheck_output"
    if [ "$postcheck_attempt" -lt "$POSTCHECK_MAX_PROBES" ]; then
        sleep "$POSTCHECK_SLEEP"
    fi
done

log "defer: switchover command failed and requested topology is not positively closed; retry-safe"
exit 1
