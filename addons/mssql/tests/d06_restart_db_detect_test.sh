#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
#
# Static / script-level test for the D06 restart DB DETECTION logic in
# entrypoint.sh. No live SQL Server: the D06_RESTART_DB_DETECT block is
# extracted from entrypoint.sh and sourced with mocked SQL helpers.
#
# The detection contract under test (PR #1710 review):
#   1. NEVER destructive: no branch may issue DROP DATABASE (sentinel asserts).
#   2. NEVER gates startup: every branch -- including role/query failures --
#      returns rc=0 under the production `set -eo pipefail` contract.
#   3. STUCK_DETECTED requires repeated stuck samples across the full bounded
#      observation window. A transient stuck sample that recovers is HEALTHY.
#   4. Unreadable role/query samples are retried; exhaustion is INCONCLUSIVE,
#      never silently ignored or promoted to STUCK_DETECTED.
#   5. Advisory detection stays local. Remote replica scans can consume the
#      production sqlcmd login timeout and delay every ordinary restart.
#   6. Every local query uses a short detection-specific timeout instead of
#      inheriting the normal 60s/300s login/query budgets.

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/entrypoint.sh"
TEST_BASH="${BASH:-bash}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Extract only the D06 block (between the marker comments).
BLOCK="$TMP/d06_block.sh"
awk '/# --- D06 restart DB detection ---/{f=1} f{print} /# --- end D06 restart DB detection ---/{f=0}' "$SRC" > "$BLOCK"

DROP_SENTINEL="$TMP/dropped"
REMOTE_SENTINEL="$TMP/remote-called"
UNBOUNDED_SENTINEL="$TMP/unbounded-call"
SLEEP_SENTINEL="$TMP/sleeps"
ATTEMPT_SENTINEL="$TMP/attempt"
export DROP_SENTINEL REMOTE_SENTINEL UNBOUNDED_SENTINEL SLEEP_SENTINEL \
       ATTEMPT_SENTINEL

# --- mocks (env-driven) ------------------------------------------------------
build_harness() {
  cat > "$TMP/harness.sh" <<'HZ'
log() { echo "$@"; }
sleep() { printf '%s\n' "$1" >> "$SLEEP_SENTINEL"; }
get_primary_pod_host() {
  touch "$REMOTE_SENTINEL"
  echo "primary.example"
}
get_my_role() {
  local attempt=1
  if [ -f "$ATTEMPT_SENTINEL" ]; then
    attempt=$(( $(cat "$ATTEMPT_SENTINEL") + 1 ))
  fi
  printf '%s\n' "$attempt" > "$ATTEMPT_SENTINEL"
  if [ "${MSSQL_LOGIN_TIMEOUT:-}" != "5" ] || [ "${MSSQL_QUERY_TIMEOUT:-}" != "5" ]; then
    touch "$UNBOUNDED_SENTINEL"
  fi
  if [ "${MOCK_ROLE_QUERY_FAIL:-no}" = "yes" ] ||
     { [ "${MOCK_ROLE_QUERY_FAIL_FIRST:-no}" = "yes" ] && [ "$attempt" -eq 1 ]; }; then
    my_role=""
    return 1
  fi
  if [ "$attempt" -le "${MOCK_ROLE_RESOLVING_THROUGH:-0}" ]; then
    my_role="resolving"
    return 0
  fi
  my_role="${MOCK_ROLE}"
}
conn_local() {
  local q="$1" attempt
  attempt=$(cat "$ATTEMPT_SENTINEL")
  if [ "${MSSQL_LOGIN_TIMEOUT:-}" != "5" ] || [ "${MSSQL_QUERY_TIMEOUT:-}" != "5" ]; then
    touch "$UNBOUNDED_SENTINEL"
  fi
  case "$q" in
    *"DROP DATABASE"*) touch "$DROP_SENTINEL"; return 0 ;;
    *"state_desc FROM sys.databases"*)
      if [ "${MOCK_LOCAL_QUERY_FAIL:-no}" = "yes" ] ||
         { [ "${MOCK_LOCAL_QUERY_FAIL_FIRST:-no}" = "yes" ] && [ "$attempt" -eq 1 ]; }; then
        return 1
      fi
      if [ "${MOCK_RECOVER_AFTER_FIRST:-no}" = "yes" ] && [ "$attempt" -gt 1 ]; then
        printf 's\n-\nONLINE\n'
      else
        printf 's\n-\n%s\n' "${MOCK_LOCAL_STATE}"
      fi ;;
    *"synchronization_state_desc"*)
      if [ "${MOCK_LOCAL_QUERY_FAIL:-no}" = "yes" ] ||
         { [ "${MOCK_LOCAL_QUERY_FAIL_FIRST:-no}" = "yes" ] && [ "$attempt" -eq 1 ]; }; then
        return 1
      fi
      if [ "${MOCK_RECOVER_AFTER_FIRST:-no}" = "yes" ] && [ "$attempt" -gt 1 ]; then
        printf 's\n-\nSYNCHRONIZED\n'
      else
        printf 's\n-\n%s\n' "${MOCK_LOCAL_SYNC}"
      fi ;;
    *) printf '\n\n\n' ;;
  esac
  return 0
}
conn_remote() {
  touch "$REMOTE_SENTINEL"
  echo "HEALTHY"
}
HZ
}

run_case() { # <label> <expect_grep> <reject_grep> <expected_sleeps>
  local label="$1" exp_grep="$2" reject_grep="$3" expected_sleeps="$4"
  rm -f "$DROP_SENTINEL" "$REMOTE_SENTINEL" "$UNBOUNDED_SENTINEL" \
        "$SLEEP_SENTINEL" "$ATTEMPT_SENTINEL"
  local out rc sleeps=0
  out=$(
    DEFAULT_DB_NAME=db1 \
    "$TEST_BASH" -c "set -eo pipefail; source '$TMP/harness.sh'; source '$BLOCK'; d06_restart_db_detect" 2>&1
  )
  rc=$?
  local dropped=no
  local remote_called=no
  local unbounded=no
  [ -f "$DROP_SENTINEL" ] && dropped=yes
  [ -f "$REMOTE_SENTINEL" ] && remote_called=yes
  [ -f "$UNBOUNDED_SENTINEL" ] && unbounded=yes
  [ -f "$SLEEP_SENTINEL" ] && sleeps=$(wc -l < "$SLEEP_SENTINEL" | tr -d ' ')
  if [ "$rc" -eq 0 ] &&
     [ "$dropped" = "no" ] &&
     [ "$remote_called" = "no" ] &&
     [ "$unbounded" = "no" ] &&
     [ "$sleeps" -eq "$expected_sleeps" ] &&
     { [ -z "$exp_grep" ] || printf '%s' "$out" | grep -q "$exp_grep"; } &&
     { [ -z "$reject_grep" ] || ! printf '%s' "$out" | grep -q "$reject_grep"; }; then
    echo "PASS  $label (rc=0, no-drop, local-only, bounded, sleeps=$sleeps)"
    pass=$((pass+1))
  else
    echo "FAIL  $label (rc=$rc dropped=$dropped remote_called=$remote_called unbounded=$unbounded sleeps=$sleeps; want sleeps=$expected_sleeps include='${exp_grep}' exclude='${reject_grep}')"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=$((fail+1))
  fi
}

build_harness
pass=0; fail=0
export MOCK_ROLE MOCK_ROLE_QUERY_FAIL MOCK_LOCAL_STATE MOCK_LOCAL_SYNC \
       MOCK_LOCAL_QUERY_FAIL MOCK_ROLE_QUERY_FAIL_FIRST \
       MOCK_LOCAL_QUERY_FAIL_FIRST MOCK_RECOVER_AFTER_FIRST \
       MOCK_ROLE_RESOLVING_THROUGH

# The function-level harness must not pass if production stops invoking it.
if awk '/^function configure_initialized /{f=1} f{print} /^}/{if(f){exit}}' "$SRC" \
    | grep -Eq '^[[:space:]]*d06_restart_db_detect[[:space:]]*\|\|[[:space:]]*true[[:space:]]*$'; then
  echo "PASS  production call site is advisory (d06_restart_db_detect || true)"
  pass=$((pass+1))
else
  echo "FAIL  production call site missing advisory d06_restart_db_detect || true"
  fail=$((fail+1))
fi

reset_mocks() {
  MOCK_ROLE=secondary MOCK_ROLE_QUERY_FAIL=no MOCK_LOCAL_STATE=RESTORING \
  MOCK_LOCAL_SYNC=NOT_SYNCHRONIZING MOCK_LOCAL_QUERY_FAIL=no \
  MOCK_ROLE_QUERY_FAIL_FIRST=no MOCK_LOCAL_QUERY_FAIL_FIRST=no \
  MOCK_RECOVER_AFTER_FIRST=no MOCK_ROLE_RESOLVING_THROUGH=0
}

# Role gates: all advisory, all rc=0, none destructive.
reset_mocks; MOCK_ROLE=primary \
  run_case "role=primary -> silent rc0" "" "STUCK_DETECTED" 0
reset_mocks; MOCK_ROLE=resolving \
  run_case "role=resolving -> bounded INCONCLUSIVE rc0" "INCONCLUSIVE.*role='resolving'" "STUCK_DETECTED" 6
reset_mocks; MOCK_ROLE="" \
  run_case "role=empty -> bounded INCONCLUSIVE rc0" "INCONCLUSIVE.*role='<empty>'" "STUCK_DETECTED" 6
reset_mocks; MOCK_ROLE_QUERY_FAIL=yes \
  run_case "role query fail -> bounded INCONCLUSIVE rc0" "INCONCLUSIVE.*role='<empty>'" "STUCK_DETECTED" 6

# Local state readings.
reset_mocks; MOCK_LOCAL_STATE=ONLINE MOCK_LOCAL_SYNC=SYNCHRONIZED \
  run_case "secondary healthy -> HEALTHY rc0" "HEALTHY db=db1 state=ONLINE sync=SYNCHRONIZED" "STUCK_DETECTED" 0
reset_mocks; MOCK_LOCAL_QUERY_FAIL=yes \
  run_case "local query fail -> bounded INCONCLUSIVE rc0" "INCONCLUSIVE db=db1.*reason=local-db-query-failed" "STUCK_DETECTED" 6
reset_mocks; MOCK_LOCAL_STATE=ONLINE MOCK_LOCAL_SYNC=NOT_SYNCHRONIZING \
  run_case "ONLINE lagging -> bounded INCONCLUSIVE rc0" "INCONCLUSIVE db=db1.*state=ONLINE" "STUCK_DETECTED" 6

# Transient recovery must never be promoted from the first stuck sample.
reset_mocks; MOCK_RECOVER_AFTER_FIRST=yes \
  run_case "transient stuck -> HEALTHY after bounded retry" "HEALTHY db=db1 state=ONLINE sync=SYNCHRONIZED attempt=2/7" "STUCK_DETECTED" 1

# A partial final streak is evidence, but not a full-window persistent verdict.
reset_mocks; MOCK_ROLE_QUERY_FAIL_FIRST=yes \
  run_case "initial role failure -> 50s stuck evidence is INCONCLUSIVE" "INCONCLUSIVE db=db1.*confirmations=6.*stuck_window_seconds=50" "STUCK_DETECTED" 6
reset_mocks; MOCK_LOCAL_QUERY_FAIL_FIRST=yes \
  run_case "initial local query failure -> 50s stuck evidence is INCONCLUSIVE" "INCONCLUSIVE db=db1.*confirmations=6.*stuck_window_seconds=50" "STUCK_DETECTED" 6
reset_mocks; MOCK_ROLE_RESOLVING_THROUGH=4 \
  run_case "late final three stuck samples -> 20s evidence is INCONCLUSIVE" "INCONCLUSIVE db=db1.*confirmations=3.*stuck_window_seconds=20" "STUCK_DETECTED" 6

# The stuck shape is classified only after the full bounded observation window.
reset_mocks; \
  run_case "persistent stuck -> local-only STUCK_DETECTED" "STUCK_DETECTED db=db1 role=secondary local_state=RESTORING local_sync=NOT_SYNCHRONIZING.*confirmations=7.*stuck_window_seconds=60.*sample_window_seconds=60.*upper_bound_seconds=165" "" 6

# The signature must carry the explicit-repair pointer.
reset_mocks; \
  run_case "persistent stuck signature carries repair pointer" "action=run-explicit-Day2-repair-see-issue-1711" "" 6

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
