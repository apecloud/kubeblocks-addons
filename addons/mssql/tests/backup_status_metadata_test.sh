#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: Backup status metadata must preserve legal
# SQL Server database names without shifting the adjacent LSN/type fields.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rm -f /tmp/result.json /tmp/stop_time.kb' EXIT

COMMON="${MSSQL_COMMON_UNDER_TEST:-$ROOT/dataprotection/common.sh}"

extract_function() {
  local source_file="$1" name="$2" output="$3"
  awk -v name="$name" \
    '$0 ~ "^function " name "([ (]|$)" { found=1 } found { print } found && /^}/ { exit }' \
    "$source_file" > "$output"
}

extract_function "$COMMON" buildJsonString "$TMP/build_json_string.sh"
extract_function "$COMMON" save_backup_status "$TMP/save_backup_status.sh"
# shellcheck disable=SC1090
source "$TMP/build_json_string.sh"
# shellcheck disable=SC1090
source "$TMP/save_backup_status.sh"

to_utf16le_hex() {
  perl -MEncode=encode,FB_CROAK -e \
    'print uc unpack("H*", encode("UTF-16LE", $ARGV[0], FB_CROAK))' "$1"
}

emit_status_row() {
  local name="$1" database_lsn="$2" differential_lsn="$3"
  local checkpoint_lsn="$4" first_lsn="$5" last_lsn="$6" type="$7" finish="$8"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(to_utf16le_hex "$name")" "$database_lsn" "$differential_lsn" \
    "$checkpoint_lsn" "$first_lsn" "$last_lsn" "$type" "$finish"
}

setup_case() {
  local case_name="$1"
  BACKUP_DIR="$TMP/$case_name/backups"
  DP_BACKUP_NAME=fixture
  DP_BACKUP_INFO_FILE="$TMP/$case_name/backup-info.json"
  ERROR_LOG="$TMP/$case_name/errors.log"
  DATASAFED_FIXTURE=valid
  mkdir -p "$BACKUP_DIR/$DP_BACKUP_NAME"
  rm -f /tmp/result.json /tmp/stop_time.kb "$DP_BACKUP_INFO_FILE" "$ERROR_LOG"
}

DP_error_log() {
  printf '%s\n' "$1" >> "$ERROR_LOG"
}

datasafed() {
  [ "$#" -eq 3 ] && [ "$1" = stat ] && [ "$2" = --json ] && [ "$3" = / ] || return 90
  case "${DATASAFED_FIXTURE:-valid}" in
    valid)
      printf '{"total_size":12345,"entries":8,"dirs":1,"files":7}\n'
      ;;
    command-failure)
      return 91
      ;;
    text-output)
      printf 'TotalSize: 12345\n'
      ;;
    malformed-json)
      printf '{not-json}\n'
      ;;
    missing-size)
      printf '{"entries":8,"dirs":1,"files":7}\n'
      ;;
    negative-size)
      printf '{"total_size":-1}\n'
      ;;
    fractional-size)
      printf '{"total_size":1.5}\n'
      ;;
    string-size)
      printf '{"total_size":"12345"}\n'
      ;;
    object-size)
      printf '{"total_size":{"value":12345}}\n'
      ;;
  esac
}

date() {
  if [ "$1" = -u ]; then
    printf '2026-07-15T18:19:00Z\n'
    return 0
  fi
  if [ "$1" = -d ] && [ "$2" = 2026-07-15T18:19:23 ]; then
    printf '1752603563\n'
    return 0
  fi
  if [ "$1" = -d ] && [ "$2" = @1752603564 ]; then
    printf '2026-07-15T18:19:24Z\n'
    return 0
  fi
  return 1
}

status_sqlcmd() {
  local args="$*"
  [[ "$args" == *'CONVERT(varbinary(max), b.name)'* ]] || return 90
  case "${STATUS_FIXTURE:-valid}" in
    valid)
      emit_status_row 'plain' 101 NULL 201 301 401 D 2026-07-15T18:19:19
      emit_status_row 'customer west' 102 NULL 202 302 402 D 2026-07-15T18:19:20
      emit_status_row $'line\nbreak' 103 NULL 203 303 403 D 2026-07-15T18:19:21
      emit_status_row $'tail\n' 104 NULL 204 304 404 D 2026-07-15T18:19:22
      emit_status_row $'tab\t"quote"\\雪 db' 105 NULL 205 305 405 D 2026-07-15T18:19:23
      ;;
    sqlcmd-failure)
      return 91
      ;;
    malformed-hex)
      printf 'NOT-HEX\t101\tNULL\t201\t301\t401\tD\t2026-07-15T18:19:23\n'
      ;;
    invalid-utf16)
      printf '00D8\t101\tNULL\t201\t301\t401\tD\t2026-07-15T18:19:23\n'
      ;;
    missing-field)
      printf '%s\t101\tNULL\t201\t301\t401\tD\n' "$(to_utf16le_hex plain)"
      ;;
    invalid-lsn)
      printf '%s\tnot-an-lsn\tNULL\t201\t301\t401\tD\t2026-07-15T18:19:23\n' \
        "$(to_utf16le_hex plain)"
      ;;
  esac
}

sql_cmd=status_sqlcmd

case_exact_metadata_round_trip() (
  setup_case exact
  STATUS_FIXTURE=valid
  save_backup_status || return 1

  perl -MJSON::PP=decode_json -MEncode=encode,FB_CROAK -e '
    open my $fh, "<:raw", $ARGV[0] or die $!;
    local $/;
    my $doc = decode_json(<$fh>);
    die "totalSize" unless $doc->{totalSize} eq "12345";
    die "timeRange" unless $doc->{timeRange}{end} eq "2026-07-15T18:19:24Z";
    my @expected = (
      ["plain", "101", "NULL", "201", "301", "401", "D"],
      ["customer west", "102", "NULL", "202", "302", "402", "D"],
      ["line\nbreak", "103", "NULL", "203", "303", "403", "D"],
      ["tail\n", "104", "NULL", "204", "304", "404", "D"],
      ["tab\t\"quote\"\\雪 db", "105", "NULL", "205", "305", "405", "D"],
    );
    die "extras count" unless @{$doc->{extras}} == @expected;
    for my $i (0 .. $#expected) {
      my $row = $doc->{extras}[$i];
      my @actual = @{$row}{qw(name databaseBackupLSN differentialBaseLSN checkpointLSN firstLSN lastLSN type)};
      for my $field (0 .. $#actual) {
        die "row $i field $field" unless $actual[$field] eq $expected[$i][$field];
      }
    }
  ' "$DP_BACKUP_INFO_FILE"
)

case_failure_is_fail_closed() (
  local fixture
  for fixture in sqlcmd-failure malformed-hex invalid-utf16 missing-field invalid-lsn; do
    setup_case "fail-$fixture"
    STATUS_FIXTURE="$fixture"
    if save_backup_status; then
      return 1
    fi
    [ ! -s "$DP_BACKUP_INFO_FILE" ] || return 1
  done
)

case_datasafed_contract_failure_is_fail_closed() (
  local fixture expected_error
  for fixture in command-failure text-output malformed-json missing-size negative-size \
    fractional-size string-size object-size; do
    setup_case "fail-datasafed-$fixture"
    STATUS_FIXTURE=valid
    DATASAFED_FIXTURE="$fixture"
    if save_backup_status; then
      return 1
    fi
    [ ! -s "$DP_BACKUP_INFO_FILE" ] || return 1
    if [ "$fixture" = command-failure ]; then
      expected_error="failed to stat backup repository with DataSafed JSON output"
    else
      expected_error="failed to parse DataSafed total_size from JSON output"
    fi
    grep -Fxq "$expected_error" "$ERROR_LOG" || return 1
  done
)

case_backup_info_write_failure_is_diagnostic() (
  setup_case fail-info-write
  STATUS_FIXTURE=valid
  DP_BACKUP_INFO_FILE="$TMP/fail-info-write/missing/backup-info.json"
  if save_backup_status 2>/dev/null; then
    return 1
  fi
  [ ! -e "$DP_BACKUP_INFO_FILE" ] || return 1
  grep -Fxq "failed to write backup status info atomically" "$ERROR_LOG"
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

run_case "status metadata preserves exact names and adjacent fields" case_exact_metadata_round_trip
run_case "transport and validation failures remain fail-closed" case_failure_is_fail_closed
run_case "DataSafed JSON contract failures remain fail-closed" case_datasafed_contract_failure_is_fail_closed
run_case "backup info write failure is fail-closed and diagnostic" case_backup_info_write_failure_is_diagnostic

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
