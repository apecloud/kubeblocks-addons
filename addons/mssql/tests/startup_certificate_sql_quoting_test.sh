#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: passwords and certificate paths consumed
# by startup certificate import must remain T-SQL data in both supported format
# branches.

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

for function_name in quote_tsql_literal create_certificate; do
  extract_function "$function_name" "$TMP/${function_name}.sh"
  if [ ! -s "$TMP/${function_name}.sh" ]; then
    echo "FAIL  could not extract production function $function_name"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$TMP/${function_name}.sh"
done

TRACE="$TMP/sql.trace"
ROOT_DIR="$TMP/root'o"
BACKUP_DIR="$TMP/backup"
SQLCMD=sqlcmd_mock
MSSQL_SERVER_PORT=1433
MSSQL_SA_USER=sa
MSSQL_SA_PASSWORD=sa-password
MSSQL_LOGIN_TIMEOUT=5
MSSQL_QUERY_TIMEOUT=5
MMSQL_MASTER_KEY_PASSWORD="mk'; DROP MASTER KEY;--"
MSSQL_PRIVATE_ENCRYPTION_PASSWORD="initial"
MAJOR_VERSION=16

log() { :; }
chown() { :; }
sqlcmd_mock() { printf '%s\n' "$MAJOR_VERSION"; }
conn_local() {
  case "$1" in
    *"SELECT 1 FROM sys.certificates"*) return 0 ;;
    *) printf '%s\n--END--\n' "$1" >> "$TRACE" ;;
  esac
}

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

prepare_case() {
  rm -rf "$ROOT_DIR" "$BACKUP_DIR"
  mkdir -p "$ROOT_DIR/data" "$BACKUP_DIR/INIT_BACKUPS/certificates"
  printf '%s' "pa'; DROP LOGIN [victim];--" > \
    "$BACKUP_DIR/INIT_BACKUPS/certificates/dbm_certificate.password"
  : > "$TRACE"
}

prepare_case
MAJOR_VERSION=16
printf 'pfx' > "$BACKUP_DIR/INIT_BACKUPS/certificates/dbm_certificate.pfx"
create_certificate
cat > "$TMP/expected-pfx" <<EXPECTED
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'mk''; DROP MASTER KEY;--';
END
--END--
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = 'dbm_certificate')
BEGIN
    CREATE CERTIFICATE dbm_certificate
        FROM FILE = N'$TMP/root''o/data/dbm_certificate.pfx'
        WITH
        FORMAT = 'PFX',
        PRIVATE KEY (
        DECRYPTION BY PASSWORD = N'pa''; DROP LOGIN [victim];--'
	  );
END
--END--
EXPECTED
check_sql "SQL Server 2022 quotes master key, PFX path, and private-key password" "$TMP/expected-pfx"

prepare_case
MAJOR_VERSION=15
printf 'cer' > "$BACKUP_DIR/INIT_BACKUPS/certificates/dbm_certificate.cer"
printf 'pvk' > "$BACKUP_DIR/INIT_BACKUPS/certificates/dbm_certificate.pvk"
create_certificate
cat > "$TMP/expected-legacy" <<EXPECTED
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'mk''; DROP MASTER KEY;--';
END
--END--
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = 'dbm_certificate')
BEGIN
    CREATE CERTIFICATE dbm_certificate
        FROM FILE = N'$TMP/root''o/data/dbm_certificate.cer'
        WITH PRIVATE KEY (
            FILE = N'$TMP/root''o/data/dbm_certificate.pvk',
            DECRYPTION BY PASSWORD = N'pa''; DROP LOGIN [victim];--'
        );
END
--END--
EXPECTED
check_sql "SQL Server 2019 quotes master key, CER/PVK paths, and private-key password" "$TMP/expected-legacy"

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
