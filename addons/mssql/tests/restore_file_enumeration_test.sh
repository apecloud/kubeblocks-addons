#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: restore inputs must survive DataSafed and
# local filesystem enumeration without shell word splitting.

if [ "${BASH_VERSINFO[0]}" -lt 4 ] && [ -x /opt/homebrew/bin/bash ]; then
  exec /opt/homebrew/bin/bash "$0" "$@"
fi

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

COMMON_RESTORE="$ROOT/dataprotection/common-restore.sh"
RESTORE="$ROOT/dataprotection/restore.sh"
INCREMENTAL_RESTORE="$ROOT/dataprotection/incremental-restore.sh"

# shellcheck disable=SC1090
source "$COMMON_RESTORE"

SPACE_NAME="customer west"
NEWLINE_NAME=$'line\nbreak'
TRAILING_NEWLINE_NAME=$'tail\n'
UNICODE_NAME="雪 db"
NAMES=("$SPACE_NAME" "$NEWLINE_NAME" "$TRAILING_NEWLINE_NAME" "$UNICODE_NAME")
MALFORMED=false
LISTING_FORMAT=stream
PULL_SOURCES=()
PULL_TARGETS=()

emit_listing_json() {
  if [ "$MALFORMED" = true ]; then
    printf '{not-json}\n'
    return 0
  fi
  perl -MJSON::PP=encode_json -MEncode=decode,FB_CROAK -e '
    my $format = shift @ARGV;
    my @paths = map { decode("UTF-8", $_, FB_CROAK) } @ARGV;
    if ($format eq "array") {
      print encode_json([map { +{path => $_} } @paths]), "\n";
    } else {
      print encode_json({path => $_}), "\n" for @paths;
    }
  ' "$LISTING_FORMAT" "$@"
}

datasafed() {
  local operation=${1-}
  shift || true
  case "$operation" in
    list)
      emit_listing_json \
        "/${SPACE_NAME}.full.bak.zst" \
        "/${NEWLINE_NAME}.full.bak.zst" \
        "/${TRAILING_NEWLINE_NAME}.full.bak.zst" \
        "/${UNICODE_NAME}.full.bak.zst" \
        "/server_login_names.sql" \
        "/dbm_certificate.pfx" \
        "/dbm_certificate.password"
      ;;
    pull)
      if [ "${1-}" = -d ]; then
        shift 2
      fi
      PULL_SOURCES+=("$1")
      PULL_TARGETS+=("$2")
      ;;
    *)
      return 1
      ;;
  esac
}

assert_array_equals() {
  local actual_name=$1 expected_name=$2
  local -n actual_ref=$actual_name expected_ref=$expected_name
  [ "${#actual_ref[@]}" -eq "${#expected_ref[@]}" ] || return 1
  local index
  for index in "${!expected_ref[@]}"; do
    [ "${actual_ref[$index]}" = "${expected_ref[$index]}" ] || return 1
  done
}

case_json_codec() (
  declare -F load_datasafed_paths >/dev/null || return 1
  MALFORMED=false
  LISTING_FORMAT=stream
  load_datasafed_paths -r -f / || return 1
  local expected=(
    "/${SPACE_NAME}.full.bak.zst"
    "/${NEWLINE_NAME}.full.bak.zst"
    "/${TRAILING_NEWLINE_NAME}.full.bak.zst"
    "/${UNICODE_NAME}.full.bak.zst"
    "/server_login_names.sql"
    "/dbm_certificate.pfx"
    "/dbm_certificate.password"
  )
  assert_array_equals DP_DATASAFED_PATHS expected || return 1
  LISTING_FORMAT=array
  load_datasafed_paths -r -f / || return 1
  assert_array_equals DP_DATASAFED_PATHS expected
)

case_malformed_fails_closed() (
  declare -F load_datasafed_paths >/dev/null || return 1
  MALFORMED=true
  DP_DATASAFED_PATHS=(stale)
  ! load_datasafed_paths -r -f / 2>/dev/null && [ "${#DP_DATASAFED_PATHS[@]}" -eq 0 ]
)

case_download_backups() (
  declare -F load_datasafed_paths >/dev/null || return 1
  MALFORMED=false
  LISTING_FORMAT=stream
  PULL_SOURCES=()
  PULL_TARGETS=()
  BACKUP_DIR="$TMP/download"
  download_backups backup || return 1
  local expected_sources=(
    "/${SPACE_NAME}.full.bak.zst"
    "/${NEWLINE_NAME}.full.bak.zst"
    "/${TRAILING_NEWLINE_NAME}.full.bak.zst"
    "/${UNICODE_NAME}.full.bak.zst"
    "/server_login_names.sql"
  )
  assert_array_equals PULL_SOURCES expected_sources || return 1
  local expected_targets=()
  local source file_name
  for source in "${expected_sources[@]}"; do
    file_name=${source#/}
    file_name=${file_name%.zst}
    expected_targets+=("${BACKUP_DIR}/INIT_BACKUPS/backup/${file_name}")
  done
  assert_array_equals PULL_TARGETS expected_targets
)

create_backup_files() {
  local directory=$1 suffix=$2 name
  mkdir -p "$directory"
  for name in "${NAMES[@]}"; do
    : > "${directory}/${name}.${suffix}.bak"
  done
}

assert_chains() {
  local root=$1 backup_name=$2 name chain expected entry
  for name in "${NAMES[@]}"; do
    chain="${root}/${name}.chain"
    expected="${backup_name}/${name}.full.bak"
    [ -f "$chain" ] || return 1
    local entries=()
    while IFS= read -r -d '' entry; do
      entries+=("$entry")
    done < "$chain"
    [ "${#entries[@]}" -eq 1 ] || return 1
    [ "${entries[0]}" = "$expected" ] || return 1
  done
}

case_full_restore_local_files() (
  BACKUP_DIR="$TMP/full"
  DP_BACKUP_NAME=backup
  DP_DATASAFED_BIN_PATH=""
  DP_BACKUP_BASE_PATH=""
  REBUILD_INSTANCE=false
  download_backups() { create_backup_files "${BACKUP_DIR}/INIT_BACKUPS/$1" full; }
  download_certificates() { :; }
  # shellcheck disable=SC1090
  source "$RESTORE"
  assert_chains "${BACKUP_DIR}/INIT_BACKUPS" "$DP_BACKUP_NAME"
)

assert_incremental_chains() {
  local root=$1 name chain entry
  for name in "${NAMES[@]}"; do
    chain="${root}/${name}.chain"
    [ -f "$chain" ] || return 1
    local entries=()
    while IFS= read -r -d '' entry; do
      entries+=("$entry")
    done < "$chain"
    [ "${#entries[@]}" -eq 2 ] || return 1
    [ "${entries[0]}" = "base/${name}.full.bak" ] || return 1
    [ "${entries[1]}" = "current/${name}.incremental.bak" ] || return 1
  done
}

case_incremental_restore_local_files() (
  BACKUP_DIR="$TMP/incremental"
  DP_BACKUP_NAME=current
  DP_BASE_BACKUP_NAME=base
  DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES=ancestor
  DP_BACKUP_ROOT_PATH=/repo
  DP_TARGET_RELATIVE_PATH=data
  DP_DATASAFED_BIN_PATH=""
  DP_BACKUP_BASE_PATH=""
  REBUILD_INSTANCE=false
  download_backups() {
    mkdir -p "${BACKUP_DIR}/INIT_BACKUPS/$1"
    if [ "$1" = current ]; then
      create_backup_files "${BACKUP_DIR}/INIT_BACKUPS/$1" incremental
    elif [ "$1" = base ]; then
      create_backup_files "${BACKUP_DIR}/INIT_BACKUPS/$1" full
    fi
  }
  download_certificates() { :; }
  # shellcheck disable=SC1090
  source "$INCREMENTAL_RESTORE"
  assert_incremental_chains "${BACKUP_DIR}/INIT_BACKUPS"
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

run_case "DataSafed JSON codec preserves exact paths" case_json_codec
run_case "malformed DataSafed JSON fails closed" case_malformed_fails_closed
run_case "download_backups pulls exact paths" case_download_backups
run_case "full restore enumerates exact local filenames" case_full_restore_local_files
run_case "incremental restore enumerates exact local filenames" case_incremental_restore_local_files

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
