#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Static / script-level negative+positive test for the modify-member custom-ops
# parameter allowlist.
#
# No live SQL Server is required. At runtime kbagent runs each ops action as
# ops_common.sh followed by the ops script (see templates/ops/*.yaml, which
# concatenate both via .Files.Get). This test reproduces that wiring but swaps
# ops_common.sh for a STUB whose SQL-executing functions only record that SQL
# was reached (a sentinel file). That lets us prove that a malicious parameter
# is rejected BEFORE any SQL statement is built or executed, and that a
# legitimate value is accepted (reaches the SQL layer).
#
# Rejection matters because the ops Job env carries MSSQL_SA_PASSWORD and the
# parameters are interpolated into T-SQL executed as sysadmin, so a value like
# '$(MSSQL_SA_PASSWORD)' (sqlcmd client-side substitution) or a quote breakout
# must never reach sqlcmd.

set -u

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SENTINEL="$TMP/sql_reached"

# Replaces ops_common.sh: every SQL-executing function records that SQL was
# reached (touch the sentinel), so a value that passes validation lands here.
read -r -d '' STUB <<'STUBEOF' || true
for f in conn_execute get_primary_endpoint execute_on_primary execute_on_local; do
  eval "$f() { touch \"\$SENTINEL\"; echo STUB_SQL; exit 0; }"
done
STUBEOF

# Optional safety-net timeout (present on the Linux runner; may be absent on a
# dev macOS host). The reject cases exit at the allowlist and the accept cases
# are bounded by the retry overrides, so the timeout is not required for
# correctness.
if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout 10"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT="gtimeout 10"
else TIMEOUT=""; fi

pass=0; fail=0
# run_case <label> <accept|reject> <script> <env assignments...>
run_case() {
  local label="$1" mode="$2" script="$3"; shift 3
  rm -f "$SENTINEL"
  local body out rc
  body="${STUB}"$'\n'"$(cat "$SCRIPTS_DIR/$script")"
  out=$(env "$@" SENTINEL="$SENTINEL" $TIMEOUT bash -c "$body" 2>&1)
  rc=$?
  if [ "$mode" = reject ]; then
    # must fail, with a clear invalid-parameter message, BEFORE any SQL.
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE 'invalid|must be numeric' \
       && [ ! -f "$SENTINEL" ]; then
      echo "PASS  [reject] $label"; pass=$((pass+1))
    else
      echo "FAIL  [reject] $label (rc=$rc, sentinel=$( [ -f "$SENTINEL" ] && echo present || echo absent ))"
      echo "      out: $(printf '%s' "$out" | head -1)"; fail=$((fail+1))
    fi
  else
    # legitimate value: must NOT hit the allowlist rejection, and must reach SQL.
    if [ -f "$SENTINEL" ] && ! printf '%s' "$out" | grep -qiE 'invalid.*(only|must be numeric)'; then
      echo "PASS  [accept] $label"; pass=$((pass+1))
    else
      echo "FAIL  [accept] $label (sentinel=$( [ -f "$SENTINEL" ] && echo present || echo absent ))"
      echo "      out: $(printf '%s' "$out" | head -1)"; fail=$((fail+1))
    fi
  fi
}

VALID_MEMBER="cluster-mssql-1.cluster-mssql-headless"

echo "== ops_modify_member.sh =="
run_case "memberServerName \$(MSSQL_SA_PASSWORD)" reject ops_modify_member.sh \
  "memberServerName=\$(MSSQL_SA_PASSWORD)" "memberEndpoint=${VALID_MEMBER}:5022"
run_case "memberServerName single-quote breakout" reject ops_modify_member.sh \
  "memberServerName=ag'; DROP DATABASE x--" "memberEndpoint=${VALID_MEMBER}:5022"
run_case "memberServerName whitespace" reject ops_modify_member.sh \
  "memberServerName=a b" "memberEndpoint=${VALID_MEMBER}:5022"
run_case "memberEndpoint host \$(VAR)" reject ops_modify_member.sh \
  "memberServerName=${VALID_MEMBER}" "memberEndpoint=\$(MSSQL_SA_PASSWORD):5022"
run_case "memberEndpoint non-numeric port" reject ops_modify_member.sh \
  "memberServerName=${VALID_MEMBER}" "memberEndpoint=${VALID_MEMBER}:5022; DROP DATABASE x"
run_case "memberEndpoint extra colon segment" reject ops_modify_member.sh \
  "memberServerName=${VALID_MEMBER}" "memberEndpoint=${VALID_MEMBER}:5022:extra"
run_case "memberEndpoint host single-quote breakout" reject ops_modify_member.sh \
  "memberServerName=${VALID_MEMBER}" "memberEndpoint=ho'st:5022"
run_case "legitimate member + endpoint" accept ops_modify_member.sh \
  "memberServerName=${VALID_MEMBER}" "memberEndpoint=${VALID_MEMBER}:5022"

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
