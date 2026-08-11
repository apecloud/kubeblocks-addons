#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Source contract for AFTER DROP_DATABASE -> Service Broker message dispatch.
# The database name must stay typed; it must never become executable SQL text.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_FILE="$ROOT/scripts/create_sp_ape_sync_db_to_ag.sql"
MESSAGE_PROC=$(awk '/^CREATE PROCEDURE dbo.sp_ape_db_sync_message$/,/^GO$/' "$SQL_FILE")
TRIGGER=$(awk '/^CREATE TRIGGER _\$\$_tr_\$\$_ape_drop_db ON ALL SERVER /,/^GO$/' "$SQL_FILE")

contains() {
  local text=$1 pattern=$2
  grep -Fq -- "$pattern" <<< "$text"
}

not_contains() {
  local text=$1 pattern=$2
  ! grep -Fq -- "$pattern" <<< "$text"
}

case_message_procedure_accepts_nonempty_native_identifier() {
  contains "$MESSAGE_PROC" '@db_name SYSNAME' || return 1
  contains "$MESSAGE_PROC" "IF @db_name IS NULL OR @db_name = N''" || return 1
}

case_trigger_extracts_nonempty_native_identifier() {
  contains "$TRIGGER" 'DECLARE @db_name SYSNAME;' || return 1
  contains "$TRIGGER" "IF @db_name IS NULL OR @db_name = N''" || return 1
  contains "$TRIGGER" "THROW 50003, 'DROP_DATABASE event did not include a database name.', 1;" || return 1
}

case_trigger_calls_message_procedure_with_typed_value() {
  contains "$TRIGGER" 'EXEC msdb.dbo.sp_ape_db_sync_message' || return 1
  contains "$TRIGGER" '@db_name = @db_name,' || return 1
  contains "$TRIGGER" "@operation_type = N'DROP_DATABASE';" || return 1
}

case_trigger_does_not_compile_database_name_as_sql() {
  not_contains "$TRIGGER" 'DECLARE @sql NVARCHAR(MAX)' || return 1
  not_contains "$TRIGGER" "SET @sql = N'EXEC msdb.dbo.sp_ape_db_sync_message" || return 1
  not_contains "$TRIGGER" 'EXEC sp_executesql @sql' || return 1
  not_contains "$TRIGGER" "+ @db_name  +" || return 1
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

run_case "message procedure accepts a nonempty native identifier" case_message_procedure_accepts_nonempty_native_identifier
run_case "trigger extracts a nonempty native identifier" case_trigger_extracts_nonempty_native_identifier
run_case "trigger passes the database name as a typed value" case_trigger_calls_message_procedure_with_typed_value
run_case "trigger never compiles the database name as SQL" case_trigger_does_not_compile_database_name_as_sql

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
