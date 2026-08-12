#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: certificate output paths and encryption
# passwords must stay data when backup actions build PFX or PVK/CER T-SQL.

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
  extract_function "$source_file" "$name" "$TMP/${name}-$(basename "$source_file").sh"
  # shellcheck disable=SC1090
  source "$TMP/${name}-$(basename "$source_file").sh"
}

COMMON="$ROOT/dataprotection/common.sh"
ARCHIVE="$ROOT/dataprotection/archive-backup.sh"

for name in quote_tsql_identifier quote_tsql_literal; do
  load_function "$COMMON" "$name"
done

TRACE="$TMP/sql.trace"
BACKUP_DIR="$TMP/backup"
DP_BACKUP_NAME="set'o"
DP_CERTIFICATE_NAME=dbm_certificate
MSSQL_PRIVATE_ENCRYPTION_PASSWORD="pa'; DROP LOGIN [victim];--"
MAJOR_VERSION=16

DP_log() { :; }
DP_error_log() { :; }
datasafed() {
  if [ "${2:-}" = "-" ]; then
    cat >/dev/null
  fi
}

sqlcmd_mock() {
  local query=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-Q" ]; then
      shift
      query="$1"
    fi
    shift
  done
  case "$query" in
    *ProductMajorVersion*) printf '%s\n' "$MAJOR_VERSION" ;;
    "select * from sys.certificates"*) printf 'certificate-present\n' ;;
    "BACKUP CERTIFICATE"*) printf '%s\n--END--\n' "$query" >> "$TRACE" ;;
  esac
}

sql_cmd=sqlcmd_mock

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

run_format_cases() {
  local source_file="$1" source_label="$2"
  unset -f backup_certificate 2>/dev/null || true
  load_function "$source_file" backup_certificate

  MAJOR_VERSION=16
  : > "$TRACE"
  backup_certificate
  cat > "$TMP/expected-${source_label}-pfx" <<EXPECTED
BACKUP CERTIFICATE [dbm_certificate] TO FILE = N'$BACKUP_DIR/set''o/dbm_certificate.pfx'
WITH
    FORMAT = 'PFX',
    PRIVATE KEY (
ENCRYPTION BY PASSWORD = N'pa''; DROP LOGIN [victim];--',
ALGORITHM = 'AES_256'
    )
--END--
EXPECTED
  check_sql "$source_label PFX quotes identifier, path, and password" "$TMP/expected-${source_label}-pfx"

  MAJOR_VERSION=15
  : > "$TRACE"
  backup_certificate
  cat > "$TMP/expected-${source_label}-legacy" <<EXPECTED
BACKUP CERTIFICATE [dbm_certificate] TO FILE = N'$BACKUP_DIR/set''o/dbm_certificate.cer'
WITH PRIVATE KEY (
    FILE = N'$BACKUP_DIR/set''o/dbm_certificate.pvk',
    ENCRYPTION BY PASSWORD = N'pa''; DROP LOGIN [victim];--'
)
--END--
EXPECTED
  check_sql "$source_label PVK/CER quotes identifier, paths, and password" "$TMP/expected-${source_label}-legacy"
}

run_format_cases "$COMMON" common
run_format_cases "$ARCHIVE" archive

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
