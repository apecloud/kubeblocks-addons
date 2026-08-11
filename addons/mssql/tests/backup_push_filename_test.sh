#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test: backup artifact paths must survive shell
# transport without whitespace splitting before they are pushed to DataSafed.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

COMMON="${MSSQL_COMMON_UNDER_TEST:-$ROOT/dataprotection/common.sh}"

extract_function() {
  local source_file="$1" name="$2" output="$3"
  awk -v name="$name" \
    '$0 ~ "^function " name "([ (]|$)" { found=1 } found { print } found && /^}/ { exit }' \
    "$source_file" > "$output"
}

extract_function "$COMMON" push_backups "$TMP/push_backups.sh"
# shellcheck disable=SC1090
source "$TMP/push_backups.sh"

case_exact_artifact_names() (
  local backup_root="$TMP/artifacts"
  local names=(
    "plain.full.bak"
    "customer west.full.bak"
    $'line\nbreak.full.bak'
    $'tab\tname.full.bak'
    "雪 db.full.bak"
  )

  mkdir -p "$backup_root/backup"
  local name
  for name in "${names[@]}"; do
    : > "$backup_root/backup/$name"
  done
  : > "$backup_root/backup/excluded.pfx"

  backup_server_roles_and_login_name() { :; }
  backup_certificate() { :; }
  DP_log() { :; }
  local invalid_call=false
  local seen=()
  datasafed() {
    if [ "$#" -ne 5 ] || [ "$1" != push ] || [ "$2" != -z ] || [ "$3" != zstd-fastest ]; then
      invalid_call=true
      return 0
    fi
    local source_path="$4" target_path="$5"
    [ -f "$source_path" ] || invalid_call=true
    [ "$target_path" = "/${source_path#./}.zst" ] || invalid_call=true
    seen+=("$source_path")
  }

  BACKUP_DIR="$backup_root"
  DP_BACKUP_NAME=backup
  push_backups

  [ "$invalid_call" = false ] || return 1
  [ "${#seen[@]}" -eq "${#names[@]}" ] || return 1
  for name in "${names[@]}"; do
    local found=false actual
    for actual in "${seen[@]}"; do
      if [ "$actual" = "./$name" ]; then
        found=true
        break
      fi
    done
    [ "$found" = true ] || return 1
  done
)

case_datasafed_failure_is_not_swallowed() {
  local backup_root="$TMP/failure-artifacts"
  local driver="$TMP/failure-driver.sh"
  mkdir -p "$backup_root/backup"
  : > "$backup_root/backup/fail.full.bak"

  cat > "$driver" <<EOF
set -e
source "$TMP/push_backups.sh"
backup_server_roles_and_login_name() { :; }
backup_certificate() { :; }
DP_log() { :; }
datasafed() { return 42; }
BACKUP_DIR=$(printf '%q' "$backup_root")
DP_BACKUP_NAME=backup
push_backups
EOF

  ! bash "$driver"
}

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

run_case "artifact filenames reach DataSafed byte-for-byte" case_exact_artifact_names
run_case "DataSafed failure remains fail-closed" case_datasafed_failure_is_not_swallowed

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
