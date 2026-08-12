#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: restore postReady audit repair must preserve
# catalog database names and quote identifier and literal positions separately.

if [ "${BASH_VERSINFO[0]}" -lt 4 ] && [ -x /opt/homebrew/bin/bash ]; then
  exec /opt/homebrew/bin/bash "$0" "$@"
fi

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SCRIPT="$ROOT/dataprotection/restore-audit-config.sh"

extract_function() {
  local source_file=$1 name=$2 output=$3
  awk -v name="$name" \
    '$0 ~ "^function " name "([ (]|$)" { found=1 } found { print } found && /^}/ { exit }' \
    "$source_file" > "$output"
}

extract_from_marker() {
  local source_file=$1 marker=$2 output=$3
  awk -v marker="$marker" '$0 == marker { found=1 } found { print }' "$source_file" > "$output"
}

for name in conn_execute quote_tsql_identifier quote_tsql_literal load_database_names re_enable_audit; do
  extract_function "$SCRIPT" "$name" "$TMP/${name}.sh"
  if [ -s "$TMP/${name}.sh" ]; then
    # shellcheck disable=SC1090
    source "$TMP/${name}.sh"
  fi
done
extract_from_marker "$SCRIPT" "# Get database list from current primary node" "$TMP/main.sh"

SPACE_NAME="customer west"
NEWLINE_NAME=$'line\nbreak'
TRAILING_NEWLINE_NAME=$'tail\n'
ADVERSARIAL_NAME=$'o\047hare] db\nnext'
UNICODE_NAME="雪 db"
NAMES=("$SPACE_NAME" "$NEWLINE_NAME" "$TRAILING_NEWLINE_NAME" "$ADVERSARIAL_NAME" "$UNICODE_NAME")
MALFORMED=false

hex_utf16le() {
  perl -MEncode=decode,encode,FB_CROAK -e '
    my $value = decode("UTF-8", $ARGV[0], FB_CROAK);
    print unpack("H*", encode("UTF-16LE", $value, FB_CROAK));
  ' "$1"
}

sqlcmd_mock() {
  if [ "$MALFORMED" = true ]; then
    printf 'not-hex\n'
    return 0
  fi
  local name
  for name in "${NAMES[@]}"; do
    hex_utf16le "$name"
    printf '\n'
  done
}

assert_names() {
  local actual_name=$1
  local -n actual=$actual_name
  [ "${#actual[@]}" -eq "${#NAMES[@]}" ] || return 1
  local index
  for index in "${!NAMES[@]}"; do
    [ "${actual[$index]}" = "${NAMES[$index]}" ] || return 1
  done
}

case_catalog_codec() (
  declare -F load_database_names >/dev/null || return 1
  SQLCMD=sqlcmd_mock
  DP_DB_HOST=host
  MSSQL_SA_USER=user
  MSSQL_SA_PASSWORD=password
  MALFORMED=false
  load_database_names || return 1
  assert_names DP_DATABASE_NAMES
)

case_malformed_fails_closed() (
  declare -F load_database_names >/dev/null || return 1
  SQLCMD=sqlcmd_mock
  DP_DB_HOST=host
  MSSQL_SA_USER=user
  MSSQL_SA_PASSWORD=password
  MALFORMED=true
  DP_DATABASE_NAMES=(stale)
  ! load_database_names && [ "${#DP_DATABASE_NAMES[@]}" -eq 0 ]
)

case_sqlcmd_substitution_disabled() (
  declare -F conn_execute >/dev/null || return 1
  CAPTURE="$TMP/sqlcmd-args"
  : > "$CAPTURE"
  sqlcmd_mock() { printf '%s\0' "$@" > "$CAPTURE"; }
  SQLCMD=sqlcmd_mock
  MSSQL_SA_USER=user
  MSSQL_SA_PASSWORD=password
  conn_execute host "SELECT N'\$(MSSQL_SA_PASSWORD)'" >/dev/null || return 1
  local args=() arg found=false
  while IFS= read -r -d '' arg; do
    args+=("$arg")
    [ "$arg" = -x ] && found=true
  done < "$CAPTURE"
  [ "$found" = true ]
)

case_audit_sql_quoting() (
  declare -F quote_tsql_identifier >/dev/null || return 1
  declare -F quote_tsql_literal >/dev/null || return 1
  declare -F re_enable_audit >/dev/null || return 1
  CAPTURE="$TMP/audit-queries"
  : > "$CAPTURE"
  conn_execute() {
    local query=$2
    printf '%s\0' "$query" >> "$CAPTURE"
    if [[ "$query" == *"SELECT is_state_enabled"* ]]; then
      printf 'header\nseparator\n1\n'
    fi
  }
  DP_DB_HOST=host
  re_enable_audit "$ADVERSARIAL_NAME" >/dev/null || return 1
  local queries=() query
  while IFS= read -r -d '' query; do
    queries+=("$query")
  done < "$CAPTURE"
  [ "${#queries[@]}" -eq 2 ] || return 1
  local database_sql audit_identifier audit_literal
  database_sql=$(quote_tsql_identifier "$ADVERSARIAL_NAME")
  audit_identifier=$(quote_tsql_identifier "${ADVERSARIAL_NAME}DatabaseAudit")
  audit_literal=$(quote_tsql_literal "${ADVERSARIAL_NAME}DatabaseAudit")
  [[ "${queries[0]}" == *"USE ${database_sql};"* ]] || return 1
  [[ "${queries[0]}" == *"WHERE name = ${audit_literal};"* ]] || return 1
  [[ "${queries[1]}" == *"USE ${database_sql};"* ]] || return 1
  [[ "${queries[1]}" == *"ALTER DATABASE AUDIT SPECIFICATION ${audit_identifier} WITH (STATE = OFF);"* ]] || return 1
  [[ "${queries[1]}" == *"ALTER DATABASE AUDIT SPECIFICATION ${audit_identifier} FOR SERVER AUDIT [kbAuditLog];"* ]] || return 1
)

case_main_consumer() (
  [ -s "$TMP/main.sh" ] || return 1
  SEEN=()
  load_database_names() { DP_DATABASE_NAMES=("${NAMES[@]}"); }
  re_enable_audit() { SEEN+=("$1"); }
  conn_execute() { printf '%s\n' "${NAMES[@]}"; }
  DP_DB_HOST=host
  # shellcheck disable=SC1090
  source "$TMP/main.sh" >/dev/null || return 1
  assert_names SEEN
)

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

run_case "catalog codec preserves exact database names" case_catalog_codec
run_case "malformed catalog transport fails closed" case_malformed_fails_closed
run_case "sqlcmd client substitution is disabled" case_sqlcmd_substitution_disabled
run_case "audit repair quotes identifiers and catalog literal" case_audit_sql_quoting
run_case "postReady main iterates exact database names" case_main_consumer

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
