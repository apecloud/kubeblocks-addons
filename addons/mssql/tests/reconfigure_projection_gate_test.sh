#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Static / script-level test for the reconfigure projection-freshness gate in
# reconfigure-sys-configurations.sh. No live SQL Server.
#
# The gate decides whether the mounted sys-configurations.toml has converged to
# the change that triggered this reconfigure, using the target key/value passed
# by kbagent as $1/$2 -- deterministically, NOT via ..data mtime or a 15s
# content-change window (which could not recognise an already-settled
# projection and wedged the OpsRequest forever).
#
# We run the real script with a mock config file, a mock sqlcmd (SQLCMD env),
# and a target key/value. A sentinel proves whether the gate let execution
# reach the apply (sqlcmd) stage.

set -u

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
SCRIPT="${SCRIPTS_DIR}/reconfigure-sys-configurations.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SENTINEL="$TMP/apply_reached"
SLEEP_SENTINEL="$TMP/sleep_reached"
PROBE_COUNT="$TMP/probe_count"
MOCK_SQLCMD="$TMP/sqlcmd"
MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_SQLCMD" <<MOCK
#!/usr/bin/env bash
touch "$SENTINEL"   # reaching sqlcmd means the gate let us proceed to apply
echo ""             # benign empty output; the script's later verify may fail,
exit 0              # but this test only asserts the GATE outcome
MOCK
chmod +x "$MOCK_SQLCMD"
cat > "$MOCK_BIN/sleep" <<MOCK
#!/usr/bin/env bash
touch "$SLEEP_SENTINEL"
exit 0
MOCK
chmod +x "$MOCK_BIN/sleep"
cat > "$MOCK_BIN/cat" <<MOCK
#!/usr/bin/env bash
count=0
[ ! -f "$PROBE_COUNT" ] || count=\$(/bin/cat "$PROBE_COUNT")
printf '%s' "\$((count + 1))" > "$PROBE_COUNT"
exec /bin/cat "\$@"
MOCK
chmod +x "$MOCK_BIN/cat"

# A representative sys-configurations.toml with <value> for the tuned key.
write_config() { # <value-for-cost-threshold>
  cat > "$TMP/sys-configurations.toml" <<TOML
'clr strict security' = 1
'cost threshold for parallelism' = $1
'max degree of parallelism' = 0
TOML
}
# Variant whose tuned key is absent entirely.
write_config_missing_key() {
  cat > "$TMP/sys-configurations.toml" <<'TOML'
'clr strict security' = 1
'max degree of parallelism' = 0
TOML
}

run() { # <projection_wait> <arg1?> <arg2?>
  local wait="$1"; shift
  run_with_timeouts "$wait" 10 25 "$@"
}

run_with_timeouts() { # <projection_wait> <login_timeout> <query_timeout> <arg1?> <arg2?>
  local wait="$1" login_timeout="$2" query_timeout="$3"; shift 3
  rm -f "$SENTINEL" "$SLEEP_SENTINEL" "$PROBE_COUNT"
  RUN_OUT=$(
    PATH="$MOCK_BIN:$PATH" \
    SQLCMD="$MOCK_SQLCMD" \
    MSSQL_SYS_CONFIG_FILE="$TMP/sys-configurations.toml" \
    MSSQL_SA_USER=sa MSSQL_SA_PASSWORD=x \
    MSSQL_PROJECTION_WAIT="$wait" \
    MSSQL_LOGIN_TIMEOUT="$login_timeout" \
    MSSQL_QUERY_TIMEOUT="$query_timeout" \
    bash "$SCRIPT" "$@" 2>&1
  )
  RUN_RC=$?
}

pass=0; fail=0
ok(){ echo "PASS  $1"; pass=$((pass+1)); }
no(){ echo "FAIL  $1"; printf '%s\n' "$RUN_OUT" | sed 's/^/      /'; fail=$((fail+1)); }

has(){ printf '%s' "$RUN_OUT" | grep -q -- "$1"; }
reached(){ [ -f "$SENTINEL" ]; }
slept(){ [ -f "$SLEEP_SENTINEL" ]; }
probe_count(){ [ -f "$PROBE_COUNT" ] && /bin/cat "$PROBE_COUNT" || printf '0'; }
retry_safe_count(){ printf '%s\n' "$RUN_OUT" | grep -c -- "next-retry-safe:"; }

# 1. spaced key, file already at target value -> proceed to apply
write_config 7
run 0 "cost threshold for parallelism" "7"
{ reached && ! has "projection-target-not-visible"; } && ok "converged (spaced key) proceeds to apply" || no "converged (spaced key) proceeds to apply"

# 2. target key passed WITH surrounding single-quotes -> stripped, still matches
write_config 7
run 0 "'cost threshold for parallelism'" "7"
{ reached && ! has "projection-target-not-visible"; } && ok "quoted target key is stripped and matches" || no "quoted target key is stripped and matches"

# 3. file still at old value -> defer with expected/observed + retry-safe, no apply
write_config 5
run 0 "cost threshold for parallelism" "7"
{ [ "$RUN_RC" -ne 0 ] && ! reached && has "projection-target-not-visible" \
  && has "expected: 'cost threshold for parallelism' = 7" \
  && has "observed: 'cost threshold for parallelism' = '5'" \
  && has "next-retry-safe: yes"; } \
  && ok "stale value defers (expected/observed/retry-safe, no apply)" || no "stale value defers (expected/observed/retry-safe, no apply)"

# 4. target key absent from config -> defer, observed <absent>
write_config_missing_key
run 0 "cost threshold for parallelism" "7"
{ [ "$RUN_RC" -ne 0 ] && ! reached && has "projection-target-not-visible" \
  && has "observed: 'cost threshold for parallelism' = '<absent>'"; } \
  && ok "absent key defers with observed <absent>" || no "absent key defers with observed <absent>"

# 5. missing $1/$2 -> fail closed before apply
write_config 7
run 0
{ [ "$RUN_RC" -ne 0 ] && ! reached && has "target-args-missing" \
  && has 'refusing to apply an unproven mounted config' \
  && has 'next-retry-safe: no'; } \
  && ok "missing key/value fails closed before apply" || no "missing key/value fails closed before apply"

# 6. missing $2 alone is also a contract error, not an empty desired value
write_config 7
run 0 "cost threshold for parallelism"
{ [ "$RUN_RC" -ne 0 ] && ! reached && has "target-args-missing" \
  && has 'next-retry-safe: no'; } \
  && ok "missing value fails closed before apply" || no "missing value fails closed before apply"

# 7. diagnostic on defer carries phase + next-retry-safe
write_config 5
run 0 "cost threshold for parallelism" "7"
{ has "phase: projection-target-not-visible" && has "next-retry-safe: yes"; } \
  && ok "defer diagnostic carries phase + next-retry-safe" || no "defer diagnostic carries phase + next-retry-safe"

# 8. NOT substring matching: a key that is a substring of the target must not match
#    (config has only the shorter key; target is the longer real key)
cat > "$TMP/sys-configurations.toml" <<'TOML'
'cost threshold' = 7
TOML
run 0 "cost threshold for parallelism" "7"
{ [ "$RUN_RC" -ne 0 ] && ! reached && has "observed: 'cost threshold for parallelism' = '<absent>'"; } \
  && ok "substring key does not falsely match" || no "substring key does not falsely match"

# 9. MSSQL_PROJECTION_WAIT is a legacy input and no longer controls in-action
# polling. Even a nonzero value gets one snapshot and immediate defer.
write_config 5
run 3 "cost threshold for parallelism" "7"
{ [ "$RUN_RC" -ne 0 ] && ! slept && ! reached \
  && [ "$(probe_count)" -eq 1 ] \
  && has "phase: projection-target-not-visible" \
  && has "next-retry-safe: yes" \
  && [ "$(retry_safe_count)" -eq 1 ]; } \
  && ok "legacy nonzero projection wait still probes once and defers without sleep/sqlcmd" \
  || no "legacy nonzero projection wait still probes once and defers without sleep/sqlcmd"

# 10. Projection wait is not part of the command budget, but the remaining
# login + query timeout sum must still fit the 50s action-command budget.
write_config 5
run_with_timeouts 999 26 25 "cost threshold for parallelism" "7"
{ [ "$RUN_RC" -ne 0 ] && ! slept && ! reached \
  && [ "$(probe_count)" -eq 0 ] \
  && has "phase: action-timeout-invalid" \
  && has "combined-timeout: 51s" \
  && has "maximum-command-budget: 50s" \
  && has "next-retry-safe: no"; } \
  && ok "login plus query timeout over budget fails before probe/sleep/sqlcmd" \
  || no "login plus query timeout over budget fails before probe/sleep/sqlcmd"

# 11. A nonnumeric legacy wait is also ignored by the one-shot projection gate.
write_config 5
run not-a-number "cost threshold for parallelism" "7"
{ [ "$RUN_RC" -ne 0 ] && ! slept && ! reached \
  && [ "$(probe_count)" -eq 1 ] \
  && has "phase: projection-target-not-visible" \
  && has "next-retry-safe: yes"; } \
  && ok "legacy nonnumeric projection wait does not affect one-shot defer" \
  || no "legacy nonnumeric projection wait does not affect one-shot defer"

# 12. sqlcmd interprets login timeout zero as infinite, so reject it before
# the projection wait or sqlcmd even when the arithmetic total looks bounded.
write_config 5
run_with_timeouts 999 0 25 "cost threshold for parallelism" "7"
{ [ "$RUN_RC" -ne 0 ] && ! slept && ! reached \
  && has "phase: action-timeout-invalid" \
  && has "invalid-variable: MSSQL_LOGIN_TIMEOUT" \
  && has "next-retry-safe: no"; } \
  && ok "zero login timeout fails before sleep or sqlcmd" \
  || no "zero login timeout fails before sleep or sqlcmd"

# 13. Query timeout zero is also infinite in sqlcmd and must fail before work.
write_config 5
run_with_timeouts 999 10 0 "cost threshold for parallelism" "7"
{ [ "$RUN_RC" -ne 0 ] && ! slept && ! reached \
  && has "phase: action-timeout-invalid" \
  && has "invalid-variable: MSSQL_QUERY_TIMEOUT" \
  && has "next-retry-safe: no"; } \
  && ok "zero query timeout fails before sleep or sqlcmd" \
  || no "zero query timeout fails before sleep or sqlcmd"

# 14. A regular config file that cannot be read is a deterministic probe error,
# not a clean absent-key observation. It must fail before sleep/sqlcmd and emit
# exactly one authoritative retry-safe field.
write_config 7
chmod 000 "$TMP/sys-configurations.toml"
run 5 "cost threshold for parallelism" "7"
chmod 600 "$TMP/sys-configurations.toml"
{ [ "$RUN_RC" -ne 0 ] && ! slept && ! reached \
  && has "phase: config-file-read-failed" \
  && has "read-rc:" \
  && has "next-retry-safe: no" \
  && [ "$(retry_safe_count)" -eq 1 ] \
  && ! has "projection-target-not-visible" \
  && ! has "observed: 'cost threshold for parallelism' = '<absent>'"; } \
  && ok "unreadable regular config fails hard before sleep/sqlcmd" \
  || no "unreadable regular config fails hard before sleep/sqlcmd"

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
