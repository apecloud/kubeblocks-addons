#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: database names and backup paths consumed
# from restore manifests must stay data when entrypoint builds T-SQL.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

extract_function() {
  local name="$1" output="$2"
  awk -v name="$name" \
    '$0 ~ "^function " name "([ (]|$)" { found=1 } found { print } found && /^}/ { exit }' \
    "$SRC/entrypoint.sh" > "$output"
}

for function_name in \
  read_chain_entries \
  quote_tsql_identifier \
  quote_tsql_literal \
  restore_database \
  restore_database_with_no_recovery \
  join_secondary_database_to_ag \
  add_db_to_ag \
  restore_from_archive_backup; do
  extract_function "$function_name" "$TMP/${function_name}.sh"
  if [ -s "$TMP/${function_name}.sh" ]; then
    # shellcheck disable=SC1090
    source "$TMP/${function_name}.sh"
  fi
done

for function_name in \
  read_chain_entries \
  restore_database \
  restore_database_with_no_recovery \
  join_secondary_database_to_ag \
  add_db_to_ag \
  restore_from_archive_backup; do
  if ! declare -F "$function_name" >/dev/null; then
    echo "FAIL  could not extract production function $function_name"
    exit 1
  fi
done

ROOT_DIR="$TMP/root"
BACKUP_DIR="$TMP/backup"
# Consumed by production functions sourced dynamically above.
# shellcheck disable=SC2034
DEFAULT_AG_NAME="ag]1"
TRACE="$TMP/sql.trace"
mkdir -p "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS"

log() { :; }
conn_local() { printf '%s\n--END--\n' "$1" >> "$TRACE"; }

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

database_name="db]; DROP DATABASE [victim"
backup_file="set/o'hare.full.bak"

: > "$TRACE"
restore_database "$database_name" "$backup_file"
cat > "$TMP/expected-recovery" <<EXPECTED
RESTORE DATABASE [db]]; DROP DATABASE [victim]
FROM DISK = N'$ROOT_DIR/backup/INIT_BACKUPS/set/o''hare.full.bak'
WITH RECOVERY;
--END--
EXPECTED
check_sql "normal RECOVERY keeps identifier and path literal inert" "$TMP/expected-recovery"

: > "$TRACE"
restore_database_with_no_recovery "$database_name" "$backup_file"
cat > "$TMP/expected-no-recovery" <<EXPECTED
RESTORE DATABASE [db]]; DROP DATABASE [victim]
FROM DISK = N'$ROOT_DIR/backup/INIT_BACKUPS/set/o''hare.full.bak'
WITH NORECOVERY;
--END--
EXPECTED
check_sql "normal NORECOVERY keeps identifier and path literal inert" "$TMP/expected-no-recovery"

: > "$TRACE"
add_db_to_ag "db']; DROP AVAILABILITY GROUP [ag1"
join_secondary_database_to_ag "$database_name"
cat > "$TMP/expected-ag" <<'EXPECTED'
USE [master]
IF NOT EXISTS (SELECT * FROM sys.availability_databases_cluster WHERE database_name = N'db'']; DROP AVAILABILITY GROUP [ag1')
BEGIN
  ALTER AVAILABILITY GROUP [ag]]1]
  ADD DATABASE [db']]; DROP AVAILABILITY GROUP [ag1];
END
--END--
ALTER DATABASE [db]]; DROP DATABASE [victim] SET HADR AVAILABILITY GROUP = [ag]]1];
--END--
EXPECTED
check_sql "AG restore actions quote identifiers and catalog literal separately" "$TMP/expected-ag"

archive_database="arc]; DROP DATABASE [victim"
archive_file="log'o.bak"
printf '%s\n' "$archive_file" > "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS/${archive_database}.chain"
printf "%s\n" "2026-07-15T04:00:00Z'; DROP DATABASE [victim];--" > "$BACKUP_DIR/.restore_archive"

: > "$TRACE"
restore_from_archive_backup "$archive_database" false
cat > "$TMP/expected-archive" <<EXPECTED
RESTORE LOG [arc]]; DROP DATABASE [victim] FROM DISK = N'$BACKUP_DIR/INIT_ARCHIVE_BACKUPS/log''o.bak' WITH NORECOVERY, STOPAT = N'2026-07-15T04:00:00Z''; DROP DATABASE [victim];--'
--END--
RESTORE DATABASE [arc]]; DROP DATABASE [victim] WITH RECOVERY
--END--
EXPECTED
check_sql "archive restore quotes identifier, path, and restore time" "$TMP/expected-archive"

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
