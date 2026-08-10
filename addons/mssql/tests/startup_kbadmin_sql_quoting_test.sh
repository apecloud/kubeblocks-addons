#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: startup admin credentials and AG names
# must stay in their intended T-SQL identifier or literal contexts.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

extract_function() {
  local name="$1" output="$2"
  awk -v name="$name" \
    '$0 ~ "^function " name "([ (]|$)" { found=1 } found { print } found && /^}/ { exit }' \
    "$ROOT/scripts/entrypoint.sh" > "$output"
}

for function_name in \
  quote_tsql_identifier \
  quote_tsql_literal \
  create_kbadmin_login \
  grant_permissions; do
  extract_function "$function_name" "$TMP/${function_name}.sh"
  if [ ! -s "$TMP/${function_name}.sh" ]; then
    echo "FAIL  could not extract production function $function_name"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$TMP/${function_name}.sh"
done

MSSQL_ADMIN_USER="kb]o'hare"
MSSQL_ADMIN_PASSWORD="p'\$\$\"word"
DEFAULT_AG_NAME="ag]o'hare"
SQL_TRACE="$TMP/sql"
OP_TRACE="$TMP/operations"
LOG_TRACE="$TMP/log"
call_count=0

log() {
  printf '%s\n' "$1" >> "$LOG_TRACE"
}

conn_local_with_retry() {
  call_count=$((call_count + 1))
  printf '%s\n' "$1" > "$SQL_TRACE.$call_count"
  printf '%s\n' "$4" >> "$OP_TRACE"
}

create_kbadmin_login
grant_permissions

cat > "$TMP/expected-login" <<'EXPECTED'
USE [master]
GO
CREATE LOGIN [kb]]o'hare] with PASSWORD= N'p''$$"word';

ALTER SERVER ROLE [sysadmin] ADD MEMBER [kb]]o'hare];
EXPECTED

cat > "$TMP/expected-grant" <<'EXPECTED'
  GRANT ALTER, CONTROL, VIEW DEFINITION ON AVAILABILITY GROUP::[ag]]o'hare] TO [kb]]o'hare];
  GRANT VIEW SERVER STATE TO [kb]]o'hare];
EXPECTED

pass=0
fail=0

check_sql() {
  local label="$1" expected="$2" actual="$3"
  if diff -u "$expected" "$actual"; then
    echo "PASS  $label"
    pass=$((pass + 1))
  else
    echo "FAIL  $label"
    fail=$((fail + 1))
  fi
}

check_sql "kbadmin login quotes username and password" "$TMP/expected-login" "$SQL_TRACE.1"
check_sql "kbadmin grants quote AG and username" "$TMP/expected-grant" "$SQL_TRACE.2"

cat > "$TMP/expected-operations" <<'EXPECTED'
create kbadmin login 'kb]o'hare'
grant permissions to kb]o'hare
EXPECTED

if ! diff -u "$TMP/expected-operations" "$OP_TRACE"; then
  echo "FAIL  retry operation names changed"
  exit 1
fi

if grep -Fq -- "$MSSQL_ADMIN_PASSWORD" "$OP_TRACE" "$LOG_TRACE"; then
  echo "FAIL  kbadmin password reached operation names or logs"
  exit 1
fi

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
