#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: catalog database names must survive shell
# transport without whitespace splitting, including embedded/trailing newlines.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

COMMON="$ROOT/dataprotection/common.sh"
FULL="$ROOT/dataprotection/backup.sh"
INCREMENTAL="$ROOT/dataprotection/incremental-backup.sh"
ARCHIVE="$ROOT/dataprotection/archive-backup.sh"

extract_function() {
  local source_file="$1" name="$2" output="$3"
  awk -v name="$name" \
    '$0 ~ "^function " name "([ (]|$)" { found=1 } found { print } found && /^}/ { exit }' \
    "$source_file" > "$output"
}

extract_from_marker() {
  local source_file="$1" marker="$2" output="$3"
  awk -v marker="$marker" '$0 == marker { found=1 } found { print }' "$source_file" > "$output"
}

extract_function "$COMMON" load_database_names "$TMP/load_database_names.sh"
if [ -s "$TMP/load_database_names.sh" ]; then
  # shellcheck disable=SC1090
  source "$TMP/load_database_names.sh"
fi
extract_function "$ARCHIVE" backup_all_databases_log "$TMP/backup_all_databases_log.sh"
# shellcheck disable=SC1090
source "$TMP/backup_all_databases_log.sh"
extract_from_marker "$INCREMENTAL" "# create backup directory" "$TMP/incremental-main.sh"

MASTER_NAME=master
SPACE_NAME="customer west"
NEWLINE_NAME=$'line\nbreak'
TRAILING_NEWLINE_NAME=$'tail\n'
UNICODE_NAME="雪 db"
MALFORMED=false

hex_utf16le() {
  perl -MEncode=decode,encode,FB_CROAK -e '
    my $value = decode("UTF-8", $ARGV[0], FB_CROAK);
    print unpack("H*", encode("UTF-16LE", $value, FB_CROAK));
  ' "$1"
}

emit_names() {
  local query="$1"
  local names=("$MASTER_NAME" "$SPACE_NAME" "$NEWLINE_NAME" "$TRAILING_NEWLINE_NAME" "$UNICODE_NAME")
  if [[ "$query" == *"msdb','master"* ]]; then
    names=("$SPACE_NAME" "$NEWLINE_NAME" "$TRAILING_NEWLINE_NAME" "$UNICODE_NAME")
  fi

  if [[ "$query" == *"CONVERT(varchar(max)"* ]]; then
    if [ "$MALFORMED" = true ]; then
      printf 'not-hex\n'
      return 0
    fi
    local name
    for name in "${names[@]}"; do
      hex_utf16le "$name"
      printf '\n'
    done
  else
    printf '%s\n' "${names[@]}"
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
  emit_names "$query"
}

assert_names() {
  local expected_scope="$1"
  local expected=("$MASTER_NAME" "$SPACE_NAME" "$NEWLINE_NAME" "$TRAILING_NEWLINE_NAME" "$UNICODE_NAME")
  if [ "$expected_scope" = user-only ]; then
    expected=("$SPACE_NAME" "$NEWLINE_NAME" "$TRAILING_NEWLINE_NAME" "$UNICODE_NAME")
  fi
  [ "${#SEEN[@]}" -eq "${#expected[@]}" ] || return 1
  local index
  for index in "${!expected[@]}"; do
    [ "${SEEN[$index]}" = "${expected[$index]}" ] || return 1
  done
}

case_catalog_codec() (
  declare -F load_database_names >/dev/null || return 1
  sql_cmd=sqlcmd_mock
  MALFORMED=false
  load_database_names include-master || return 1
  SEEN=("${DP_DATABASE_NAMES[@]}")
  assert_names include-master
)

case_malformed_fails_closed() (
  declare -F load_database_names >/dev/null || return 1
  sql_cmd=sqlcmd_mock
  MALFORMED=true
  DP_DATABASE_NAMES=(stale)
  ! load_database_names include-master && [ "${#DP_DATABASE_NAMES[@]}" -eq 0 ]
)

case_full_consumer() (
  SEEN=()
  sql_cmd=sqlcmd_mock
  MALFORMED=false
  DP_DATASAFED_BIN_PATH=""
  DP_BACKUP_BASE_PATH=""
  BACKUP_DIR="$TMP/full"
  DP_BACKUP_NAME=backup
  DP_log() { :; }
  DP_error_log() { :; }
  backup_database_with_full() { SEEN+=("$1"); }
  push_backups() { :; }
  save_backup_status() { :; }
  # shellcheck disable=SC1090
  source "$FULL"
  assert_names include-master
)

case_incremental_consumer() (
  SEEN=()
  sql_cmd=sqlcmd_mock
  MALFORMED=false
  DP_DATASAFED_BIN_PATH=""
  DP_BACKUP_BASE_PATH=""
  BACKUP_DIR="$TMP/incremental"
  DP_BACKUP_NAME=backup
  DP_log() { :; }
  DP_error_log() { :; }
  need_full_backup() { return 1; }
  backup_database() { SEEN+=("$1"); }
  backup_database_with_full() { SEEN+=("$1"); }
  push_backups() { :; }
  save_backup_status() { :; }
  # shellcheck disable=SC1090
  source "$TMP/incremental-main.sh"
  assert_names include-master
)

case_archive_consumer() (
  SEEN=()
  sql_cmd=sqlcmd_mock
  MALFORMED=false
  backup_database_log() { SEEN+=("$1"); }
  backup_all_databases_log
  assert_names user-only
)

pass=0
fail=0
run_case() {
  local label="$1" function_name="$2"
  if "$function_name"; then
    echo "PASS  $label"
    pass=$((pass + 1))
  else
    echo "FAIL  $label"
    fail=$((fail + 1))
  fi
}

run_case "catalog codec preserves whitespace, newline, and Unicode names" case_catalog_codec
run_case "catalog codec rejects malformed transport before iteration" case_malformed_fails_closed
run_case "full backup enumerates exact database names" case_full_consumer
run_case "incremental backup enumerates exact database names" case_incremental_consumer
run_case "archive-log backup enumerates exact database names" case_archive_consumer

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
