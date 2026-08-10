#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
#
# Static regression guard for T-SQL identifier/literal escaping in the login-sync
# DDL triggers and stored procedures (create_sp_ape_sync_login.sh).
#
# A SQL Server login name is user-controlled and may legally contain a single
# quote (CREATE LOGIN [o'brien]) or a bracket. Several trigger/proc paths build
# dynamic SQL by concatenating @login_name (from EVENTDATA()) into a string
# literal or a [bracket] identifier. Without escaping, a legitimate quoted name
# breaks the generated statement (login sync fails) and a crafted name injects
# T-SQL that runs as sysadmin.
#
# This test does NOT need a live SQL Server; it asserts the source uses the
# correct escaping primitive at each single-level splice site:
#   - string literal  -> REPLACE(@login_name, '''', '''''')  (doubles the quote)
#   - [ ] identifier  -> QUOTENAME(@login_name)
# It also documents the linked-server nested EXEC('...') AT [srv] sites that are
# intentionally out of scope here (they need a runtime-tested rewrite).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/create_sp_ape_sync_login.sh"
pass=0; fail=0

# 1. No bare single-level enqueue splice remains. The pre-fix pattern was
#    `+ @login_name  + ''', @operation_type = ...` (bare, double space).
bare=$(grep -c '+ @login_name  +' "$SRC" || true)
if [ "$bare" -eq 0 ]; then
  echo "PASS  no bare '+ @login_name +' single-level enqueue splice"; pass=$((pass+1))
else
  echo "FAIL  $bare bare @login_name enqueue splice(s) remain (should use REPLACE)"; fail=$((fail+1))
fi

# 2. Every sp_ape_login_role_sync_message enqueue uses REPLACE-doubling. There
#    are four such sites (CREATE/ALTER/DROP login + ALTER SERVER ROLE).
repl=$(grep -c "REPLACE(@login_name, '''', '''''')" "$SRC" || true)
if [ "$repl" -ge 4 ]; then
  echo "PASS  $repl REPLACE(@login_name,...) escaped enqueue sites (>=4)"; pass=$((pass+1))
else
  echo "FAIL  only $repl REPLACE(@login_name,...) sites (want >=4)"; fail=$((fail+1))
fi

# 3. The ALTER_SERVER_ROLE enqueue also escapes @command_text.
if grep -q "REPLACE(@command_text, '''', '''''')" "$SRC"; then
  echo "PASS  @command_text escaped in ALTER_SERVER_ROLE enqueue"; pass=$((pass+1))
else
  echo "FAIL  @command_text not escaped in ALTER_SERVER_ROLE enqueue"; fail=$((fail+1))
fi

# 4. sp_ape_cleanup_login_users uses QUOTENAME for the [user] identifier, not a
#    raw "[' + @login_name + ']" bracket splice.
if grep -q "QUOTENAME(@login_name)" "$SRC" \
   && ! grep -q "DROP USER IF EXISTS \[' + @login_name" "$SRC"; then
  echo "PASS  cleanup_login_users uses QUOTENAME(@login_name)"; pass=$((pass+1))
else
  echo "FAIL  cleanup_login_users still raw-splices @login_name into [ ]"; fail=$((fail+1))
fi

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
