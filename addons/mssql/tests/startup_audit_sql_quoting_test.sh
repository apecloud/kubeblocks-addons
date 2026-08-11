#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: server/database audit names, paths, and
# catalog values must remain T-SQL identifiers or literals as appropriate.

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
  check_auditlog \
  config_auditlog_primary \
  config_auditlog_secondary \
  config_db_auditlog; do
  extract_function "$function_name" "$TMP/${function_name}.sh"
  if [ ! -s "$TMP/${function_name}.sh" ]; then
    echo "FAIL  could not extract production function $function_name"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$TMP/${function_name}.sh"
done

TRACE="$TMP/sql.trace"
REMOTE_TRACE="$TMP/remote.trace"
AUDIT_LOG_DIRECTORY="$TMP/audit'o"
AUDIT_SERVER_NAME="audit]o'hare"
DEFAULT_DB_NAME=""

log() { :; }
chown() { :; }
sleep() { :; }

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

conn_local() {
  printf '%s\n' "$1" > "$TRACE"
}

mkdir -p "$AUDIT_LOG_DIRECTORY"
# Loaded from the extracted production function above; the later definition is
# the isolated stub used by the primary/secondary builder cases.
# shellcheck disable=SC2218
if check_auditlog; then
  :
fi
cat > "$TMP/expected-check" <<EXPECTED
SELECT audit_id
FROM sys.server_audits
WHERE name = N'audit]o''hare';
EXPECTED
check_sql "server-audit catalog lookup quotes the name literal" "$TMP/expected-check" "$TRACE"

check_auditlog() { return 1; }
config_auditlog_primary
cat > "$TMP/expected-primary" <<EXPECTED
CREATE SERVER AUDIT [audit]]o'hare]
TO FILE ( FILEPATH = N'$TMP/audit''o', MAXSIZE = 100MB, MAX_ROLLOVER_FILES = 5 );

ALTER SERVER AUDIT [audit]]o'hare]
WITH (STATE = ON);
EXPECTED
check_sql "primary server-audit SQL quotes identifier and path literal" "$TMP/expected-primary" "$TRACE"

get_primary_pod_host() { printf '%s\n' primary.example; }
conn_remote() {
  printf '%s\n' "$2" > "$REMOTE_TRACE"
  printf '%s\n' "guid'; DROP SERVER AUDIT [victim];--"
}
config_auditlog_secondary
cat > "$TMP/expected-remote" <<EXPECTED
select audit_guid from sys.server_audits where name = N'audit]o''hare'
EXPECTED
cat > "$TMP/expected-secondary" <<EXPECTED
CREATE SERVER AUDIT [audit]]o'hare]
TO FILE ( FILEPATH = N'$TMP/audit''o', MAXSIZE = 100MB, MAX_ROLLOVER_FILES = 5 )
WITH (AUDIT_GUID = N'guid'';DROPSERVERAUDIT[victim];--');
ALTER SERVER AUDIT [audit]]o'hare]
WITH (STATE = ON);
EXPECTED
check_sql "secondary catalog lookup quotes the audit-name literal" "$TMP/expected-remote" "$REMOTE_TRACE"
check_sql "secondary server-audit SQL quotes identifier, path, and GUID literals" "$TMP/expected-secondary" "$TRACE"

conn_local_with_database_retry() {
  local database="$1" sql="$2"
  printf '%s\n' "$database" > "$TMP/database.arg"
  case "$sql" in
    SELECT*) printf '%s\n' "$sql" > "$TMP/database-check.trace" ;;
    CREATE*) printf '%s\n' "$sql" > "$TMP/database-create.trace" ;;
  esac
}
config_db_auditlog "db]o'hare"
cat > "$TMP/expected-database-check" <<EXPECTED
SELECT database_specification_id
FROM sys.database_audit_specifications
WHERE name = N'db]o''hareDatabaseAudit';
EXPECTED
cat > "$TMP/expected-database-create" <<EXPECTED
CREATE DATABASE AUDIT SPECIFICATION [db]]o'hareDatabaseAudit]
FOR SERVER AUDIT [audit]]o'hare]
ADD (SELECT, INSERT, UPDATE, DELETE ON DATABASE::[db]]o'hare] BY PUBLIC)
WITH (STATE = ON);
EXPECTED
printf '%s\n' "db]o'hare" > "$TMP/expected-database-arg"
check_sql "database-audit catalog lookup quotes the specification literal" \
  "$TMP/expected-database-check" "$TMP/database-check.trace"
check_sql "database-audit SQL quotes specification, audit, and database identifiers" \
  "$TMP/expected-database-create" "$TMP/database-create.trace"
check_sql "database retry keeps the database name as a value argument" \
  "$TMP/expected-database-arg" "$TMP/database.arg"

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
