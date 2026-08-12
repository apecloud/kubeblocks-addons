#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Source contract for sp_help_revlogin / sp_ape_help_revlogin generated DDL.
# These procedures print login-creation SQL that is later replayed on replicas,
# so login names must be emitted as string literals, not raw concatenation.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_FILE="$ROOT/scripts/create_sp_help_revlogin.sql"

HELP_PROC=$(awk '/^CREATE PROCEDURE dbo.sp_help_revlogin/,/^GO$/' "$SQL_FILE")
APE_HELP_PROC=$(awk '/^CREATE PROCEDURE dbo.sp_ape_help_revlogin/,/^GO$/' "$SQL_FILE")

contains() {
  local text=$1 pattern=$2
  grep -Fq -- "$pattern" <<< "$text"
}

not_contains() {
  local text=$1 pattern=$2
  ! grep -Fq -- "$pattern" <<< "$text"
}

case_help_revlogin_login_literal_safe() {
  contains "$HELP_PROC" 'DECLARE @name_literal          [nvarchar](260)' || return 1
  contains "$HELP_PROC" "SET @name_literal = N'N' + QUOTENAME(@name, N'''')" || return 1
  contains "$HELP_PROC" "WHERE [name] = ' + @name_literal + N'" || return 1
  not_contains "$HELP_PROC" "WHERE [name] = N''' + @name + N'''" || return 1
}

case_ape_help_revlogin_login_literal_safe() {
  contains "$APE_HELP_PROC" 'DECLARE @name_literal          [nvarchar](260)' || return 1
  contains "$APE_HELP_PROC" "SET @name_literal = N'N' + QUOTENAME(@name, N'''')" || return 1
  contains "$APE_HELP_PROC" "WHERE [name] = ' + @name_literal + N'" || return 1
  not_contains "$APE_HELP_PROC" "WHERE [name] = N''' + @name + N'''" || return 1
}

case_help_revlogin_role_membership_safe() {
  contains "$HELP_PROC" "@Prefix + QUOTENAME(LoginName, N'''') + N', @rolename = N''sysadmin'''" || return 1
  contains "$HELP_PROC" "@Prefix + QUOTENAME(LoginName, N'''') + N', @rolename = N''bulkadmin'''" || return 1
  not_contains "$HELP_PROC" "@Prefix + LoginName + N''', @rolename" || return 1
}

case_ape_help_revlogin_role_membership_safe() {
  contains "$APE_HELP_PROC" "@Prefix + QUOTENAME(LoginName, N'''') + N', @rolename = N''sysadmin'''" || return 1
  contains "$APE_HELP_PROC" "@Prefix + QUOTENAME(LoginName, N'''') + N', @rolename = N''bulkadmin'''" || return 1
  not_contains "$APE_HELP_PROC" "@Prefix + LoginName + N''', @rolename" || return 1
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

run_case "sp_help_revlogin emits escaped login-name literals" case_help_revlogin_login_literal_safe
run_case "sp_ape_help_revlogin emits escaped login-name literals" case_ape_help_revlogin_login_literal_safe
run_case "sp_help_revlogin emits escaped role-membership logins" case_help_revlogin_role_membership_safe
run_case "sp_ape_help_revlogin emits escaped role-membership logins" case_ape_help_revlogin_role_membership_safe

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
