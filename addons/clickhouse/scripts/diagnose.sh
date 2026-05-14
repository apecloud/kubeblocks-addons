#!/bin/bash
# ClickHouse cluster diagnostic script
# Outputs: replica sync status, merge backlog, Keeper connection, slow queries Top-10
set -eo pipefail

# Always prefer the extracted pod FQDN over the common.sh default (localhost)
if [[ -n "$CLICKHOUSE_POD_FQDN_LIST" ]]; then
    CLICKHOUSE_HOST="${CLICKHOUSE_POD_FQDN_LIST%%,*}"
    export CLICKHOUSE_HOST
fi

SEP="════════════════════════════════════════════════════════════"

echo "$SEP"
echo "  ClickHouse Cluster Diagnostics — $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "$SEP"

# ── 1. Replica Sync Status ──────────────────────────────────────
echo ""
echo "▶ [1/4] Replica Sync Status (system.replicas)"
echo "  Columns: database | table | shard | replica | is_leader | queue_size | absolute_delay"
echo "  (delay > 300s or queue_size > 1000 warrants investigation)"
ch_query "$CLICKHOUSE_HOST" "
SELECT
    database,
    table,
    shard,
    replica_name,
    is_leader,
    queue_size,
    absolute_delay
FROM system.replicas
ORDER BY absolute_delay DESC, queue_size DESC
FORMAT PrettyCompact
" 2>&1 || echo "  [WARN] Could not query system.replicas (standalone mode or error)"

# ── 2. Merge Queue Backlog ──────────────────────────────────────
echo ""
echo "▶ [2/4] Background Merge Queue (system.merges)"
echo "  Columns: database | table | elapsed | progress | rows_read | memory_usage"
ch_query "$CLICKHOUSE_HOST" "
SELECT
    database,
    table,
    round(elapsed, 1) AS elapsed_sec,
    round(progress * 100, 1) AS progress_pct,
    formatReadableQuantity(rows_read) AS rows_read,
    formatReadableSize(memory_usage) AS memory_usage
FROM system.merges
ORDER BY elapsed DESC
LIMIT 20
FORMAT PrettyCompact
" 2>&1 || echo "  [WARN] Could not query system.merges"

# ── 3. Keeper Connection Status ─────────────────────────────────
echo ""
echo "▶ [3/4] Keeper Connection Status (system.zookeeper)"
ch_query "$CLICKHOUSE_HOST" "
SELECT
    name,
    value
FROM system.zookeeper
WHERE path = '/'
FORMAT PrettyCompact
" 2>&1 || echo "  [WARN] Keeper not configured or unreachable"

echo ""
echo "  Keeper metrics from system.metrics:"
ch_query "$CLICKHOUSE_HOST" "
SELECT metric, value, description
FROM system.metrics
WHERE metric LIKE '%Keeper%' OR metric LIKE '%ZooKeeper%'
ORDER BY metric
FORMAT PrettyCompact
" 2>&1 || true

# ── 4. Slow Queries Top-10 ──────────────────────────────────────
echo ""
echo "▶ [4/4] Slow Queries Top-10 (last 24h, system.query_log)"
echo "  Columns: query_duration_ms | memory_usage | user | normalized query"
ch_query "$CLICKHOUSE_HOST" "
SELECT
    round(query_duration_ms / 1000.0, 2) AS duration_sec,
    formatReadableSize(memory_usage) AS mem,
    user,
    left(normalizeQuery(query), 120) AS query_preview
FROM system.query_log
WHERE
    type = 'QueryFinish'
    AND event_time >= now() - INTERVAL 24 HOUR
    AND query NOT LIKE '%system.query_log%'
ORDER BY query_duration_ms DESC
LIMIT 10
FORMAT PrettyCompact
" 2>&1 || echo "  [WARN] Could not query system.query_log"

echo ""
echo "$SEP"
echo "  Diagnostics complete."
echo "$SEP"
