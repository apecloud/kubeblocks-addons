#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Source contract for the remote DROP DATABASE path. Runtime execution still
# requires SQL Server; this test locks identifier and nested-literal roles.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_FILE="$ROOT/scripts/create_sp_ape_sync_db_to_ag.sql"
PROC=$(awk '/^CREATE PROCEDURE sp_ape_drop_db_sync$/,/^GO$/' "$SQL_FILE")

contains() {
  local text=$1 pattern=$2
  grep -Fq -- "$pattern" <<< "$text"
}

not_contains() {
  local text=$1 pattern=$2
  ! grep -Fq -- "$pattern" <<< "$text"
}

case_database_identifier_is_native_and_quoted() {
  contains "$PROC" '@db_name SYSNAME' || return 1
  contains "$PROC" "IF @db_name IS NULL OR @db_name = N''" || return 1
  contains "$PROC" 'DECLARE @QuotedDatabaseName NVARCHAR(258) = QUOTENAME(@db_name)' || return 1
  contains "$PROC" 'IF @QuotedDatabaseName IS NULL' || return 1
}

case_linked_server_identifier_is_fresh_and_quoted() {
  contains "$PROC" 'SET @fqdn = NULL' || return 1
  contains "$PROC" 'DECLARE @QuotedLinkedServer NVARCHAR(258)' || return 1
  contains "$PROC" 'SET @QuotedLinkedServer = QUOTENAME(@fqdn)' || return 1
  contains "$PROC" 'IF @fqdn IS NULL OR @QuotedLinkedServer IS NULL' || return 1
}

case_remote_sql_uses_only_quoted_database_identifier() {
  contains "$PROC" 'DECLARE @remote_sql NVARCHAR(MAX)' || return 1
  contains "$PROC" "N'RESTORE DATABASE ' + @QuotedDatabaseName + N' WITH RECOVERY;'" || return 1
  contains "$PROC" "N'ALTER DATABASE ' + @QuotedDatabaseName + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;'" || return 1
  contains "$PROC" "N'DROP DATABASE ' + @QuotedDatabaseName + N';'" || return 1
}

case_nested_sql_literal_and_linked_identifier_are_separate() {
  contains "$PROC" "REPLACE(@remote_sql, N'''', N'''''')" || return 1
  contains "$PROC" "N''') AT ' + @QuotedLinkedServer + N';'" || return 1
  not_contains "$PROC" "DATABASE [' + @db_name" || return 1
  not_contains "$PROC" "AT [' + @fqdn" || return 1
}

case_throw_predecessors_are_terminated() {
  contains "$PROC" 'DECLARE @QuotedDatabaseName NVARCHAR(258) = QUOTENAME(@db_name);' || return 1
  contains "$PROC" 'SET @QuotedLinkedServer = QUOTENAME(@fqdn);' || return 1
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

run_case "database name is a quoted native identifier" case_database_identifier_is_native_and_quoted
run_case "linked-server name is fresh, bounded, and quoted" case_linked_server_identifier_is_fresh_and_quoted
run_case "remote SQL uses only the quoted database identifier" case_remote_sql_uses_only_quoted_database_identifier
run_case "nested SQL literal and linked identifier stay separate" case_nested_sql_literal_and_linked_identifier_are_separate
run_case "statements before THROW are terminated" case_throw_predecessors_are_terminated

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
