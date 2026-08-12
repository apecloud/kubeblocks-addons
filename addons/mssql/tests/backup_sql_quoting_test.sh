#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: database names and generated backup paths
# must stay data when DataProtection scripts build T-SQL.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

extract_function() {
  local source_file="$1" name="$2" output="$3"
  awk -v name="$name" \
    '$0 ~ "^function " name "([ (]|$)" { found=1 } found { print } found && /^}/ { exit }' \
    "$source_file" > "$output"
}

load_function() {
  local source_file="$1" name="$2"
  extract_function "$source_file" "$name" "$TMP/${name}.sh"
  if [ -s "$TMP/${name}.sh" ]; then
    # shellcheck disable=SC1090
    source "$TMP/${name}.sh"
  fi
}

COMMON="$ROOT/dataprotection/common.sh"
INCREMENTAL="$ROOT/dataprotection/incremental-backup.sh"
ARCHIVE="$ROOT/dataprotection/archive-backup.sh"

for name in quote_tsql_identifier quote_tsql_literal backup_database_with_full; do
  load_function "$COMMON" "$name"
done
for name in need_full_backup backup_database; do
  load_function "$INCREMENTAL" "$name"
done
load_function "$ARCHIVE" do_log_backup

TRACE="$TMP/sql.trace"
BACKUP_DIR="$TMP/backup"
DP_BACKUP_NAME="set'o"
# Consumed by production functions sourced dynamically above.
# shellcheck disable=SC2034
DP_DB_HOST=host DP_DB_USER=user DP_DB_PASSWORD=password
mkdir -p "$BACKUP_DIR/$DP_BACKUP_NAME"

DP_log() { :; }
DP_error_log() { :; }
copy_only_parameter() { :; }

sqlcmd_mock() {
  local query=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-Q" ]; then
      shift
      query="$1"
    fi
    shift
  done
  printf '%s\n--END--\n' "$query" >> "$TRACE"
}

# Consumed by production functions sourced dynamically above.
# shellcheck disable=SC2034
SQLCMD=sqlcmd_mock sql_cmd=sqlcmd_mock

pass=0
fail=0

check_sql() {
  local label="$1" expected="$2"
  if diff -u "$expected" "$TRACE"; then
    echo "PASS  $label"
    pass=$((pass + 1))
  else
    echo "FAIL  $label"
    fail=$((fail + 1))
  fi
}

database_name="db']; DROP DATABASE [victim"

: > "$TRACE"
backup_database_with_full "$database_name"
cat > "$TMP/expected-full" <<EXPECTED
BACKUP DATABASE [db']]; DROP DATABASE [victim]
TO DISK = N'$BACKUP_DIR/set''o/db'']; DROP DATABASE [victim.full.bak'
   WITH FORMAT,
    COMPRESSION,
    MEDIANAME = N'KB-set''o',
    STATS=1,
    NAME = N'db'']; DROP DATABASE [victim';
GO
--END--
EXPECTED
check_sql "full backup quotes identifier and literals" "$TMP/expected-full"

: > "$TRACE"
backup_database "$database_name"
cat > "$TMP/expected-differential" <<EXPECTED
BACKUP DATABASE [db']]; DROP DATABASE [victim]
TO DISK = N'$BACKUP_DIR/set''o/db'']; DROP DATABASE [victim.incremental.bak'
   WITH DIFFERENTIAL,
    FORMAT,
    COMPRESSION,
    MEDIANAME = N'KB-set''o',
    STATS=1,
    NAME = N'db'']; DROP DATABASE [victim';
GO
--END--
EXPECTED
check_sql "differential backup quotes identifier and literals" "$TMP/expected-differential"

: > "$TRACE"
need_full_backup "$database_name"
cat > "$TMP/expected-history" <<'EXPECTED'
SET NOCOUNT ON; select database_name from backupmediaset as m join backupset as b on b.media_set_id = m.media_set_id where b.database_name = N'db'']; DROP DATABASE [victim' and type='D' and m.name like 'KB-%'
--END--
EXPECTED
check_sql "differential history lookup quotes database literal" "$TMP/expected-history"

: > "$TRACE"
# Consumed by do_log_backup for its production log message.
# shellcheck disable=SC2034
database="$database_name"
do_log_backup "$database_name"
cat > "$TMP/expected-log" <<EXPECTED
DBCC TRACEON (3226, -1);BACKUP LOG [db']]; DROP DATABASE [victim] TO DISK = N'$BACKUP_DIR/set''o/db'']; DROP DATABASE [victim.log.bak' WITH FORMAT,COMPRESSION,MEDIANAME=N'KB_LOG_BAK',STATS=1,NAME = N'db'']; DROP DATABASE [victim'
--END--
EXPECTED
check_sql "transaction-log backup quotes identifier and literals" "$TMP/expected-log"

# Literal grep patterns assert the production shell source, not expansion here.
# shellcheck disable=SC2016
if grep -Eq '^sql_cmd=.* -x"$' "$COMMON" \
   && grep -Eq '^sql_cmd=.* -x"$' "$ARCHIVE" \
   && grep -Fq '$SQLCMD -S "${DP_DB_HOST}" -U "$DP_DB_USER" -P "$DP_DB_PASSWORD" -C -x -Q "$backup_sql"' "$COMMON" \
   && grep -Fq '$SQLCMD -S "${DP_DB_HOST}" -U "$DP_DB_USER" -P "$DP_DB_PASSWORD" -C -x -Q "$backup_sql"' "$INCREMENTAL"; then
  echo "PASS  backup sqlcmd paths disable client-side variable substitution"
  pass=$((pass + 1))
else
  echo "FAIL  backup sqlcmd paths disable client-side variable substitution"
  fail=$((fail + 1))
fi

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
