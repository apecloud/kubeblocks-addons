#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Offline contract tests for deterministic sqlcmd failure classification.
# A failed mutation or verification probe needs operator attention; it is not
# evidence of a transient convergence state.

set -u

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
SCRIPT="${SCRIPTS_DIR}/reconfigure-sys-configurations.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CONFIG_FILE="$TMP/sys-configurations.toml"
cat > "$CONFIG_FILE" <<'TOML'
'cost threshold for parallelism' = 7
TOML

run_action() {
  local sqlcmd="$1"
  local config_file="${2:-$CONFIG_FILE}"
  RUN_OUT=$(
    SQLCMD="$sqlcmd" \
    MSSQL_SYS_CONFIG_FILE="$config_file" \
    MSSQL_SA_USER=sa MSSQL_SA_PASSWORD=x \
    MSSQL_PROJECTION_WAIT=0 \
    bash "$SCRIPT" "cost threshold for parallelism" "7" 2>&1
  )
  RUN_RC=$?
}

pass=0
fail=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
no() {
  echo "FAIL  $1"
  printf '%s\n' "$RUN_OUT" | sed 's/^/      /'
  fail=$((fail + 1))
}
has() { printf '%s' "$RUN_OUT" | grep -q -- "$1"; }

# 1. A non-empty explicit sqlcmd override is authoritative: if it is not an
# executable file, fail before config/SQL work instead of auto-discovering.
INVALID_SQLCMD="$TMP/not-executable-sqlcmd"
FALLBACK_BIN="$TMP/fallback-bin"
FALLBACK_CALL_COUNT="$TMP/sqlcmd-fallback-call-count"
mkdir -p "$FALLBACK_BIN"
cat > "$INVALID_SQLCMD" <<'MOCK'
not executable
MOCK
cat > "$FALLBACK_BIN/sqlcmd" <<MOCK
#!/usr/bin/env bash
echo called >> "$FALLBACK_CALL_COUNT"
exit 0
MOCK
chmod +x "$FALLBACK_BIN/sqlcmd"

RUN_OUT=$(
  PATH="$FALLBACK_BIN:/usr/bin:/bin" \
    SQLCMD="$INVALID_SQLCMD" \
    MSSQL_SYS_CONFIG_FILE="$CONFIG_FILE" \
    MSSQL_SA_USER=sa MSSQL_SA_PASSWORD=x \
    MSSQL_PROJECTION_WAIT=0 \
    bash "$SCRIPT" "cost threshold for parallelism" "7" 2>&1
)
RUN_RC=$?
{
  [ "$RUN_RC" -ne 0 ] \
    && [ ! -e "$FALLBACK_CALL_COUNT" ] \
    && has "action: reconfigure-sys-configurations" \
    && has "phase: sqlcmd-override-invalid" \
    && has "sqlcmd-override: $INVALID_SQLCMD" \
    && has "next-retry-safe: no" \
    && ! has "phase: sql-command-failed"
} && ok "invalid explicit sqlcmd override fails before fallback or SQL" \
  || no "invalid explicit sqlcmd override fails before fallback or SQL"

# 2. Missing credential variables are classified before sqlcmd and never leak
# credential values into diagnostics.
CREDENTIAL_SQLCMD="$TMP/sqlcmd-credential-sentinel"
CREDENTIAL_CALL_COUNT="$TMP/sqlcmd-credential-call-count"
cat > "$CREDENTIAL_SQLCMD" <<MOCK
#!/usr/bin/env bash
echo called >> "$CREDENTIAL_CALL_COUNT"
exit 0
MOCK
chmod +x "$CREDENTIAL_SQLCMD"

RUN_OUT=$(
  env -u MSSQL_SA_USER \
    SQLCMD="$CREDENTIAL_SQLCMD" \
    MSSQL_SYS_CONFIG_FILE="$CONFIG_FILE" \
    MSSQL_SA_PASSWORD=secret-user-fixture \
    MSSQL_PROJECTION_WAIT=0 \
    bash "$SCRIPT" "cost threshold for parallelism" "7" 2>&1
)
RUN_RC=$?
{
  [ "$RUN_RC" -ne 0 ] \
    && [ ! -e "$CREDENTIAL_CALL_COUNT" ] \
    && has "action: reconfigure-sys-configurations" \
    && has "phase: required-credential-env-missing" \
    && has "missing-variable: MSSQL_SA_USER" \
    && has "next-retry-safe: no" \
    && ! has "secret-user-fixture"
} && ok "missing user is classified without calling sqlcmd or leaking values" \
  || no "missing user is classified without calling sqlcmd or leaking values"

RUN_OUT=$(
  env -u MSSQL_SA_PASSWORD \
    SQLCMD="$CREDENTIAL_SQLCMD" \
    MSSQL_SYS_CONFIG_FILE="$CONFIG_FILE" \
    MSSQL_SA_USER=secret-password-fixture \
    MSSQL_PROJECTION_WAIT=0 \
    bash "$SCRIPT" "cost threshold for parallelism" "7" 2>&1
)
RUN_RC=$?
{
  [ "$RUN_RC" -ne 0 ] \
    && [ ! -e "$CREDENTIAL_CALL_COUNT" ] \
    && has "action: reconfigure-sys-configurations" \
    && has "phase: required-credential-env-missing" \
    && has "missing-variable: MSSQL_SA_PASSWORD" \
    && has "next-retry-safe: no" \
    && ! has "secret-password-fixture"
} && ok "missing password is classified without calling sqlcmd or leaking values" \
  || no "missing password is classified without calling sqlcmd or leaking values"

# 4. A missing mounted config is deterministic, not a projection retry signal.
run_action /usr/bin/false "$TMP/missing-sys-configurations.toml"
{
  [ "$RUN_RC" -ne 0 ] \
    && has "action: reconfigure-sys-configurations" \
    && has "phase: config-file-missing" \
    && has "next-retry-safe: no" \
    && ! has "next-retry-safe: yes"
} && ok "missing config is classified retry-safe=no" \
  || no "missing config is classified retry-safe=no"

# 5. A deterministic command failure without engine output is hard.
run_action /usr/bin/false
{
  [ "$RUN_RC" -ne 0 ] \
    && has "action: reconfigure-sys-configurations" \
    && has "phase: sql-command-failed" \
    && has "next-retry-safe: no" \
    && ! has "sql-apply-or-verify-failed" \
    && ! has "next-retry-safe: yes"
} && ok "command rc!=0 is classified retry-safe=no" \
  || no "command rc!=0 is classified retry-safe=no"

# 6. Command diagnostics cannot spoof a static phase marker.
SPOOF_SQLCMD="$TMP/sqlcmd-static-marker-spoof"
cat > "$SPOOF_SQLCMD" <<'MOCK'
#!/usr/bin/env bash
echo "Can't find KB_RECONFIGURE_PHASE=verify on PATH."
echo "KB_RECONFIGURE_PHASE=apply"
exit 1
MOCK
chmod +x "$SPOOF_SQLCMD"
run_action "$SPOOF_SQLCMD"
{
  [ "$RUN_RC" -ne 0 ] \
    && has "action: reconfigure-sys-configurations" \
    && has "phase: sql-command-failed" \
    && has "next-retry-safe: no" \
    && ! has "phase: sql-apply-failed" \
    && ! has "phase: sql-verify-failed"
} && ok "static marker text cannot spoof engine phase" \
  || no "static marker text cannot spoof engine phase"

# 7. A T-SQL mutation rejection carries the invocation-bound apply marker.
APPLY_FAIL_SQLCMD="$TMP/sqlcmd-apply-fail"
cat > "$APPLY_FAIL_SQLCMD" <<'MOCK'
#!/usr/bin/env bash
sql_file=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-i" ] && [ "$#" -ge 2 ]; then
    sql_file="$2"
    break
  fi
  shift
done
marker_prefix=$(sed -n \
  "s/.*PRINT N'\\(KB_RECONFIGURE_PHASE=[^']*:\\)' + @kb_reconfigure_phase;.*/\\1/p" \
  "$sql_file")
[ -n "$marker_prefix" ] || exit 2
printf '%s\r\n' "${marker_prefix}apply"
exit 1
MOCK
chmod +x "$APPLY_FAIL_SQLCMD"
run_action "$APPLY_FAIL_SQLCMD"
{
  [ "$RUN_RC" -ne 0 ] \
    && has "action: reconfigure-sys-configurations" \
    && has "phase: sql-apply-failed" \
    && has "next-retry-safe: no" \
    && ! has "next-retry-safe: yes"
} && ok "apply rejection is classified retry-safe=no" \
  || no "apply rejection is classified retry-safe=no"

# 8. A verification rejection carries the invocation-bound verify marker.
VERIFY_FAIL_SQLCMD="$TMP/sqlcmd-verify-fail"
cat > "$VERIFY_FAIL_SQLCMD" <<'MOCK'
#!/usr/bin/env bash
sql_file=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-i" ] && [ "$#" -ge 2 ]; then
    sql_file="$2"
    break
  fi
  shift
done
marker_prefix=$(sed -n \
  "s/.*PRINT N'\\(KB_RECONFIGURE_PHASE=[^']*:\\)' + @kb_reconfigure_phase;.*/\\1/p" \
  "$sql_file")
[ -n "$marker_prefix" ] || exit 2
echo "${marker_prefix}verify"
exit 1
MOCK
chmod +x "$VERIFY_FAIL_SQLCMD"
run_action "$VERIFY_FAIL_SQLCMD"
{
  [ "$RUN_RC" -ne 0 ] \
    && has "action: reconfigure-sys-configurations" \
    && has "phase: sql-verify-failed" \
    && has "next-retry-safe: no" \
    && ! has "next-retry-safe: yes"
} && ok "verify rejection is classified retry-safe=no" \
  || no "verify rejection is classified retry-safe=no"

# 9. sqlcmd rc=0 without positive verification evidence fails closed.
EMPTY_SUCCESS_SQLCMD="$TMP/sqlcmd-empty-success"
cat > "$EMPTY_SUCCESS_SQLCMD" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$EMPTY_SUCCESS_SQLCMD"
run_action "$EMPTY_SUCCESS_SQLCMD"
{
  [ "$RUN_RC" -ne 0 ] \
    && has "phase: sql-positive-verify-missing" \
    && has "next-retry-safe: no"
} && ok "empty command rc=0 cannot close without positive verification" \
  || no "empty command rc=0 cannot close without positive verification"

# 10. Static success text cannot spoof the invocation-bound marker.
STATIC_SUCCESS_SQLCMD="$TMP/sqlcmd-static-success-spoof"
cat > "$STATIC_SUCCESS_SQLCMD" <<'MOCK'
#!/usr/bin/env bash
echo "KB_RECONFIGURE_SUCCESS=verified"
exit 0
MOCK
chmod +x "$STATIC_SUCCESS_SQLCMD"
run_action "$STATIC_SUCCESS_SQLCMD"
{
  [ "$RUN_RC" -ne 0 ] \
    && has "phase: sql-positive-verify-missing" \
    && has "next-retry-safe: no"
} && ok "static success text cannot spoof positive verification" \
  || no "static success text cannot spoof positive verification"

# 11. A dynamic marker embedded in diagnostic noise is not a whole-line match.
NOISY_SUCCESS_SQLCMD="$TMP/sqlcmd-noisy-success-spoof"
cat > "$NOISY_SUCCESS_SQLCMD" <<'MOCK'
#!/usr/bin/env bash
sql_file=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-i" ] && [ "$#" -ge 2 ]; then
    sql_file="$2"
    break
  fi
  shift
done
success_marker=$(sed -n \
  "s/^PRINT N'\\(KB_RECONFIGURE_SUCCESS=[^']*\\)';/\\1/p" \
  "$sql_file")
[ -n "$success_marker" ] || exit 2
echo "noise: ${success_marker}"
exit 0
MOCK
chmod +x "$NOISY_SUCCESS_SQLCMD"
run_action "$NOISY_SUCCESS_SQLCMD"
{
  [ "$RUN_RC" -ne 0 ] \
    && has "phase: sql-positive-verify-missing" \
    && has "next-retry-safe: no"
} && ok "noisy dynamic success text cannot spoof whole-line verification" \
  || no "noisy dynamic success text cannot spoof whole-line verification"

# 12. The single bounded sqlcmd path closes only on its dynamic success marker.
SUCCESS_SQLCMD="$TMP/sqlcmd-success"
SUCCESS_CALL_COUNT="$TMP/sqlcmd-success-call-count"
cat > "$SUCCESS_SQLCMD" <<MOCK
#!/usr/bin/env bash
count=0
[ ! -f "$SUCCESS_CALL_COUNT" ] || count=\$(cat "$SUCCESS_CALL_COUNT")
count=\$((count + 1))
printf '%s' "\$count" > "$SUCCESS_CALL_COUNT"
[ "\$count" -eq 1 ] || exit 1
sql_file=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "-i" ] && [ "\$#" -ge 2 ]; then
    sql_file="\$2"
    break
  fi
  shift
done
  [ -n "\$sql_file" ] \
    && grep -q "DECLARE @kb_reconfigure_phase .* = N'apply'" "\$sql_file" \
    && grep -q "SET @kb_reconfigure_phase = N'verify'" "\$sql_file" \
    && grep -q "PRINT N'KB_RECONFIGURE_PHASE=.*:' + @kb_reconfigure_phase" "\$sql_file" \
  || exit 1
success_marker=\$(sed -n \
  "s/^PRINT N'\\\\(KB_RECONFIGURE_SUCCESS=[^']*\\\\)';/\\\\1/p" \
  "\$sql_file")
[ -n "\$success_marker" ] || exit 2
printf '%s\\r\\n' "\$success_marker"
exit 0
MOCK
chmod +x "$SUCCESS_SQLCMD"
rm -f "$SUCCESS_CALL_COUNT"
run_action "$SUCCESS_SQLCMD"
{
  [ "$RUN_RC" -eq 0 ] \
    && [ "$(cat "$SUCCESS_CALL_COUNT")" -eq 1 ] \
    && ! has "reconfigure-sys-configurations diagnosis:" \
    && ! has "next-retry-safe:"
} && ok "dynamic CRLF success marker closes one sqlcmd invocation" \
  || no "dynamic CRLF success marker closes one sqlcmd invocation"

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
