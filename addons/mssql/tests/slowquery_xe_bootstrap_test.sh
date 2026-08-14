#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract for slow-query XE bootstrap. The configured
# event-file path is environment-derived and must remain a T-SQL literal.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$ROOT/scripts/entrypoint.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

awk '/^function config_slowquery_xe\(\)/,/^}/' "$ENTRYPOINT" > "$TMP/function.sh"
if [ ! -s "$TMP/function.sh" ]; then
  echo "FAIL  could not extract config_slowquery_xe"
  exit 1
fi
# shellcheck disable=SC1090
source "$TMP/function.sh"

SLOW_LOG_SESSION_NAME="kbSlowQueryLog"
SLOW_LOG_DIRECTORY="$TMP/slow'o"
SLOW_LOG_FILE_NAME="kb_slow_query.xel"
SLOW_LOG_BOOTSTRAP_THRESHOLD_US=1000000
SLOW_LOG_BOOTSTRAP_MAX_FILE_SIZE_MB=100
SLOW_LOG_BOOTSTRAP_MAX_ROLLOVER_FILES=5
mkdir -p "$SLOW_LOG_DIRECTORY"

TRACE="$TMP/sql.trace"
CONN_RC=0
log() { :; }
chown() { :; }
conn_local() {
  printf '%s\n' "$1" > "$TRACE"
  return "$CONN_RC"
}

pass=0
fail=0
run_case() {
  local label=$1 function_name=$2
  if "$function_name"; then
    echo "PASS  $label"
    pass=$((pass + 1))
  else
    echo "FAIL  $label"
    fail=$((fail + 1))
  fi
}

case_event_file_path_is_literal_safe() {
  CONN_RC=0
  config_slowquery_xe || return 1
  grep -Fq -- "SET filename=N'$TMP/slow''o/kb_slow_query.xel'" "$TRACE" || return 1
  ! grep -Fq -- "SET filename=N'$TMP/slow'o/kb_slow_query.xel'" "$TRACE"
}

case_bootstrap_defaults_are_fixed() {
  grep -Fq -- 'WHERE ([duration] >= 1000000)' "$TRACE" || return 1
  [ "$(grep -Fc -- 'WHERE ([duration] >= 1000000)' "$TRACE")" -eq 2 ] || return 1
  grep -Fq -- 'max_file_size=(100)' "$TRACE" || return 1
  grep -Fq -- 'max_rollover_files=(5)' "$TRACE"
}

case_existing_session_is_not_recreated() {
  grep -Fq -- "IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'kbSlowQueryLog')" "$TRACE" || return 1
  grep -Fq -- "IF NOT EXISTS (SELECT 1 FROM sys.dm_xe_sessions WHERE name = N'kbSlowQueryLog')" "$TRACE"
}

case_sql_failure_propagates() {
  CONN_RC=17
  config_slowquery_xe
  [ "$?" -eq 1 ]
}

run_case "event-file path is escaped as a T-SQL literal" case_event_file_path_is_literal_safe
run_case "bootstrap threshold and rollover defaults are fixed" case_bootstrap_defaults_are_fixed
run_case "existing session definition is preserved and only inactive session starts" case_existing_session_is_not_recreated
run_case "sqlcmd failure propagates from XE bootstrap" case_sql_failure_propagates

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
