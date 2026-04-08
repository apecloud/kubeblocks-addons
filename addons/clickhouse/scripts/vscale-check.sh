#!/bin/bash
# ClickHouse vertical scale pre/post check script
# Checks memory and CPU utilization from system.metrics
# Exits non-zero if unsafe to scale down (memory usage too high)
set -eo pipefail

if [[ -n "$CLICKHOUSE_POD_FQDN_LIST" ]]; then
    CLICKHOUSE_HOST="${CLICKHOUSE_POD_FQDN_LIST%%,*}"
    export CLICKHOUSE_HOST
fi

# ── Parameters ────────────────────────────────────────────────
# KubeBlocks injects OpsRequest params directly as env vars using the param name.
# mode: "pre" (before scale) or "post" (after scale)
# newMemoryBytes: target memory limit in bytes (for pre-check shrink guard)
# shrinkThresholdPct: refuse scale-down if MemoryTracking > N% of new limit
VSCALE_MODE="${mode:-pre}"
VSCALE_NEW_MEMORY_BYTES="${newMemoryBytes:-0}"
SHRINK_THRESHOLD_PCT="${shrinkThresholdPct:-80}"

echo "══════════════════════════════════════════════"
echo "  ClickHouse VScale ${VSCALE_MODE}-check"
echo "  Host: ${CLICKHOUSE_HOST}  Mode: ${VSCALE_MODE}"
echo "══════════════════════════════════════════════"

# ── Query current resource usage ──────────────────────────────
echo ""
echo "▶ Current resource metrics:"
ch_query "$CLICKHOUSE_HOST" "
SELECT
    metric,
    value,
    description
FROM system.metrics
WHERE metric IN (
    'MemoryTracking',
    'BackgroundMergesAndMutationsPoolTask',
    'Query',
    'HTTPConnection',
    'TCPConnection'
)
ORDER BY metric
FORMAT PrettyCompact
"

# ── Read MemoryTracking for safety check ─────────────────────
MEMORY_TRACKING=$(ch_query "$CLICKHOUSE_HOST" "
SELECT value FROM system.metrics WHERE metric = 'MemoryTracking'
" 2>/dev/null || echo "0")

echo ""
echo "  MemoryTracking (current): $(numfmt --to=iec-i --suffix=B "${MEMORY_TRACKING}" 2>/dev/null || echo "${MEMORY_TRACKING} bytes")"

if [[ "$VSCALE_MODE" == "pre" && "$VSCALE_NEW_MEMORY_BYTES" -gt 0 ]]; then
    threshold=$(( VSCALE_NEW_MEMORY_BYTES * SHRINK_THRESHOLD_PCT / 100 ))
    echo "  Target memory limit:      $(numfmt --to=iec-i --suffix=B "${VSCALE_NEW_MEMORY_BYTES}" 2>/dev/null || echo "${VSCALE_NEW_MEMORY_BYTES} bytes")"
    echo "  Safety threshold (${SHRINK_THRESHOLD_PCT}%):   $(numfmt --to=iec-i --suffix=B "${threshold}" 2>/dev/null || echo "${threshold} bytes")"
    if [[ "$MEMORY_TRACKING" -gt "$threshold" ]]; then
        echo ""
        echo "  [FAIL] Current memory usage (${MEMORY_TRACKING} bytes) exceeds ${SHRINK_THRESHOLD_PCT}% of target limit."
        echo "         Scale-down is unsafe. Wait for active queries/merges to complete."
        exit 1
    fi
    echo "  [OK] Memory usage within safe range for scale-down."
fi

# ── Merge queue check ─────────────────────────────────────────
echo ""
echo "▶ Active merges:"
ch_query "$CLICKHOUSE_HOST" "
SELECT
    database, table,
    round(elapsed, 1) AS elapsed_sec,
    round(progress * 100, 1) AS progress_pct
FROM system.merges
ORDER BY elapsed DESC
LIMIT 5
FORMAT PrettyCompact
" 2>&1 || true

if [[ "$VSCALE_MODE" == "post" ]]; then
    echo ""
    echo "▶ Post-scale health check: verifying ClickHouse is responsive..."
    ch_query "$CLICKHOUSE_HOST" "SELECT 'ok' AS status" > /dev/null
    echo "  [OK] ClickHouse is responsive after scale."
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  VScale ${VSCALE_MODE}-check passed."
echo "══════════════════════════════════════════════"
