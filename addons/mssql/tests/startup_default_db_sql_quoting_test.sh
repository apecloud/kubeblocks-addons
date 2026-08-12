#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: the startup default database and its
# initial backup path must remain T-SQL identifiers or literals as appropriate.

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
  create_default_db; do
  extract_function "$function_name" "$TMP/${function_name}.sh"
  if [ ! -s "$TMP/${function_name}.sh" ]; then
    echo "FAIL  could not extract production function $function_name"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$TMP/${function_name}.sh"
done

TRACE="$TMP/sql.trace"
DEFAULT_DB_NAME="db]o'hare"
ROOT_DIR="$TMP/root'o"

log() { :; }
conn_local() {
  printf '%s\n' "$1" > "$TRACE"
}

create_default_db

cat > "$TMP/expected" <<EXPECTED
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = N'db]o''hare')
BEGIN
  CREATE DATABASE [db]]o'hare];

  ALTER DATABASE [db]]o'hare]
  SET RECOVERY FULL;

  BACKUP DATABASE [db]]o'hare]
  TO DISK = N'$TMP/root''o/data/db]o''hare.bak';
END
EXPECTED

if diff -u "$TMP/expected" "$TRACE"; then
  echo "PASS  startup default database SQL quotes identifier, catalog value, and backup path"
else
  echo "FAIL  startup default database SQL quotes identifier, catalog value, and backup path"
  exit 1
fi
