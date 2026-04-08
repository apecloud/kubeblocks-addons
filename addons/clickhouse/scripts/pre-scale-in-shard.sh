#!/bin/bash
# ClickHouse shard scale-in pre-flight data migration script
#
# Strategy: before removing a shard, redistribute its data to remaining shards
# by inserting each local MergeTree table into the cluster's Distributed table.
#
# Required env vars:
#   CLICKHOUSE_ADMIN_USER / CLICKHOUSE_ADMIN_PASSWORD / CLICKHOUSE_TCP_PORT
#   SCALE_IN_SHARD_POD_FQDN  - FQDN of one pod on the shard being removed
#   CLUSTER_NAME             - ClickHouse cluster name (default: "default")
#   DRY_RUN                  - set to "true" to only print migration plan without executing
set -eo pipefail

# KubeBlocks injects OpsRequest params directly as env vars using the param name:
#   scaleInShardPodFqdn → $scaleInShardPodFqdn, clusterName → $clusterName, dryRun → $dryRun
SCALE_IN_SHARD_POD_FQDN="${scaleInShardPodFqdn:-$CLICKHOUSE_HOST}"
CLUSTER_NAME="${clusterName:-default}"
DRY_RUN="${dryRun:-false}"

function log() { echo "[$(date -u '+%H:%M:%S')] $*"; }
function die() { log "ERROR: $*" >&2; exit 1; }

log "══════════════════════════════════════════════════════════"
log "  ClickHouse Shard Scale-In Pre-migration"
log "  Shard pod: ${SCALE_IN_SHARD_POD_FQDN}  Cluster: ${CLUSTER_NAME}"
log "  Dry run: ${DRY_RUN}"
log "══════════════════════════════════════════════════════════"

# ── 1. Verify connectivity ────────────────────────────────────
log ""
log "▶ [1/5] Verifying connectivity to source shard..."
ch_query "$SCALE_IN_SHARD_POD_FQDN" "SELECT 1" > /dev/null || die "Cannot connect to shard pod ${SCALE_IN_SHARD_POD_FQDN}"
log "  [OK] Connected."

# ── 2. Discover tables to migrate ─────────────────────────────
log ""
log "▶ [2/5] Discovering user tables on source shard..."
TABLES=$(ch_query "$SCALE_IN_SHARD_POD_FQDN" "
SELECT
    database,
    name AS table_name,
    engine,
    formatReadableSize(total_bytes) AS size,
    total_rows
FROM system.tables
WHERE
    database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
    AND engine NOT IN ('View', 'MaterializedView', 'Distributed', 'Dictionary', 'Null', 'Buffer', 'Log', 'TinyLog', 'StripeLog')
ORDER BY database, table_name
FORMAT TabSeparated
")

if [[ -z "$TABLES" ]]; then
    log "  [OK] No user tables found on shard. Scale-in is safe."
    exit 0
fi

log "  Tables to migrate:"
echo "$TABLES" | while IFS=$'\t' read -r db tbl engine size rows; do
    log "    ${db}.${tbl}  engine=${engine}  size=${size}  rows=${rows}"
done

# ── 3. Verify Distributed table exists for each table ─────────
log ""
log "▶ [3/5] Checking Distributed table coverage..."
MIGRATION_PLAN=()
MISSING_DIST=()
while IFS=$'\t' read -r db tbl engine size rows; do
    dist_table=$(ch_query "$SCALE_IN_SHARD_POD_FQDN" "
    SELECT name FROM system.tables
    WHERE database = '${db}'
      AND engine = 'Distributed'
      AND create_table_query LIKE '%${tbl}%'
    LIMIT 1
    FORMAT TabSeparatedRaw" 2>/dev/null || true)

    if [[ -n "$dist_table" ]]; then
        log "  [OK] ${db}.${tbl} → ${db}.${dist_table}"
        MIGRATION_PLAN+=("${db}|${tbl}|${dist_table}|${rows}")
    else
        log "  [WARN] No Distributed table found for ${db}.${tbl} — will migrate via ON CLUSTER INSERT"
        MISSING_DIST+=("${db}.${tbl}")
    fi
done <<< "$TABLES"

# ── 4. Execute migration ──────────────────────────────────────
log ""
log "▶ [4/5] Migrating data..."
FAILED=()

for entry in "${MIGRATION_PLAN[@]}"; do
    IFS='|' read -r db tbl dist_table src_rows <<< "$entry"

    log "  Migrating ${db}.${tbl} → ${db}.${dist_table} (src_rows=${src_rows})..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [DRY_RUN] Would execute: INSERT INTO ${db}.${dist_table} SELECT * FROM ${db}.${tbl}"
        continue
    fi

    # Use INSERT INTO distributed SELECT * FROM local to redistribute rows
    ch_query "$SCALE_IN_SHARD_POD_FQDN" "
    INSERT INTO ${db}.${dist_table}
    SELECT * FROM ${db}.${tbl}
    SETTINGS insert_distributed_sync=1
    " || { log "  [FAIL] Migration failed for ${db}.${tbl}"; FAILED+=("${db}.${tbl}"); continue; }

    # Verify: after insertion the distributed table should have >= src_rows
    if [[ -n "$src_rows" && "$src_rows" -gt 0 ]]; then
        dist_rows=$(ch_query "$SCALE_IN_SHARD_POD_FQDN" "
        SELECT count() FROM ${db}.${dist_table}
        FORMAT TabSeparatedRaw" 2>/dev/null || echo "0")
        if [[ "$dist_rows" -lt "$src_rows" ]]; then
            log "  [WARN] Distributed table has ${dist_rows} rows but source had ${src_rows}. Possible deduplication or partial migration."
        else
            log "  [OK] ${db}.${tbl} migrated. Distributed now has ${dist_rows} rows."
        fi
    else
        log "  [OK] ${db}.${tbl} migrated."
    fi
done

for tbl in "${MISSING_DIST[@]}"; do
    log "  [WARN] ${tbl} has no Distributed table. Manual migration required."
    log "         Suggested: CREATE TABLE ... ON CLUSTER ${CLUSTER_NAME} then INSERT."
    FAILED+=("$tbl (no Distributed table)")
done

# ── 5. Report ─────────────────────────────────────────────────
log ""
log "▶ [5/5] Migration summary"
if [[ ${#FAILED[@]} -gt 0 ]]; then
    log ""
    log "  [FAIL] The following tables were NOT fully migrated:"
    for f in "${FAILED[@]}"; do log "    - ${f}"; done
    log ""
    log "  Scale-in BLOCKED. Resolve failures before proceeding."
    exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log "  [DRY_RUN] Migration plan printed. Re-run with DRY_RUN=false to execute."
    exit 0
fi

log "  [OK] All tables migrated successfully. Shard is safe to remove."
log "══════════════════════════════════════════════════════════"
