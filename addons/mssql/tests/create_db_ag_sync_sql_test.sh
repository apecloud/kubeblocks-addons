#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Source contract for the CREATE_DATABASE -> SQL Agent -> AG sync path. Runtime
# execution still requires SQL Server; this test locks identifier/literal roles.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_FILE="$ROOT/scripts/create_sp_ape_sync_db_to_ag.sql"

PROC=$(awk '/^CREATE PROCEDURE sp_ape_sync_db_to_ag /,/^GO$/' "$SQL_FILE")
TRIGGER=$(awk '/^CREATE TRIGGER _\$\$_tr_\$\$_ape_create_database /,/^GO$/' "$SQL_FILE")

contains() {
  local text=$1 pattern=$2
  grep -Fq -- "$pattern" <<< "$text"
}

not_contains() {
  local text=$1 pattern=$2
  ! grep -Fq -- "$pattern" <<< "$text"
}

case_bounded_native_identifiers() {
  contains "$PROC" '@AddToGroupName SYSNAME' || return 1
  contains "$PROC" '@DatabaseName SYSNAME' || return 1
  contains "$PROC" 'IF LEN(@DatabaseName) > 115' || return 1
  contains "$PROC" 'QUOTENAME(@DatabaseName)' || return 1
  contains "$PROC" 'QUOTENAME(@AddToGroupName)' || return 1
  contains "$PROC" 'QUOTENAME(@AuditName)' || return 1
}

case_audit_catalog_parameterized() {
  contains "$PROC" 'WHERE name = @AuditName' || return 1
  contains "$PROC" "EXEC sys.sp_executesql @audit_sql, N'@AuditName SYSNAME', @AuditName = @AuditName;" || return 1
  not_contains "$PROC" "WHERE name = ''' + @DatabaseName" || return 1
}

case_recovery_backup_join_safe() {
  contains "$PROC" "N'ALTER DATABASE ' + @QuotedDatabaseName + N' SET RECOVERY FULL WITH NO_WAIT'" || return 1
  contains "$PROC" "HASHBYTES('SHA2_256', @DatabaseName)" || return 1
  contains "$PROC" "N'BACKUP DATABASE ' + @QuotedDatabaseName + N' TO DISK = @TargetFile'" || return 1
  contains "$PROC" "EXEC sys.sp_executesql @BackupCommand, N'@TargetFile NVARCHAR(2048)', @TargetFile = @TargetFile;" || return 1
  contains "$PROC" "N'ALTER AVAILABILITY GROUP ' + @QuotedGroupName + N' ADD DATABASE ' + @QuotedDatabaseName" || return 1
}

case_job_command_safe() {
  contains "$TRIGGER" 'DECLARE @AddToGroupName SYSNAME;' || return 1
  contains "$TRIGGER" "SET @JobName = N'HADR_Add_' + CONVERT(NVARCHAR(36), NEWID());" || return 1
  contains "$TRIGGER" "N'EXEC master.dbo.sp_ape_sync_db_to_ag '" || return 1
  contains "$TRIGGER" "QUOTENAME(@AddToGroupName, '''')" || return 1
  contains "$TRIGGER" "QUOTENAME(@DatabaseName, '''')" || return 1
  not_contains "$TRIGGER" "'HADR_Add_' + @DatabaseName" || return 1
}

case_raw_concatenation_removed() {
  not_contains "$PROC" "USE [' + @DatabaseName" || return 1
  not_contains "$PROC" "DATABASE [' + @DatabaseName" || return 1
  not_contains "$PROC" "GROUP [' + @AddToGroupName" || return 1
  not_contains "$PROC" "N''' + @TargetFile" || return 1
  not_contains "$PROC" "N'/var/opt/mssql/' + @DatabaseName" || return 1
  not_contains "$TRIGGER" "@AddToGroupName + '''" || return 1
  not_contains "$TRIGGER" "@DatabaseName + '''" || return 1
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

run_case "procedure bounds and quotes native identifiers" case_bounded_native_identifiers
run_case "audit catalog lookup is parameterized" case_audit_catalog_parameterized
run_case "recovery, backup, and AG join commands are safe" case_recovery_backup_join_safe
run_case "SQL Agent job command quotes stored-procedure values" case_job_command_safe
run_case "raw dynamic SQL concatenation is absent" case_raw_concatenation_removed

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
