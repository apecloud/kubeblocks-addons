#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-function contract test for archive/PITR repository paths and the
# basefull.info metadata that connects a full backup to its log chain.

# Functions and fixture globals below are invoked indirectly after extracting
# production functions, so ShellCheck cannot see every reference.
# shellcheck disable=SC2034,SC2329

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

COMMON="$ROOT/dataprotection/common.sh"
ARCHIVE_BACKUP="$ROOT/dataprotection/archive-backup.sh"
ARCHIVE_RESTORE="$ROOT/dataprotection/archive-restore.sh"
ENTRYPOINT="$ROOT/scripts/entrypoint.sh"

DP_DB_HOST=mock
DP_DB_USER=mock
DP_DB_PASSWORD=mock
DP_BACKUP_INFO_FILE="$TMP/backup-info"
clean_backup_after_failure=false
# shellcheck disable=SC1090
source "$COMMON"
trap - EXIT
trap 'rm -rf "$TMP"' EXIT

extract_function() {
  local source_file="$1" name="$2" output="$3"
  awk -v name="$name" \
    '$0 ~ "^function " name "([ (]|$)" { found=1 } found { print } found && /^}/ { exit }' \
    "$source_file" > "$output"
}

extract_function "$ARCHIVE_RESTORE" prepare_archive_restore_chains "$TMP/prepare_archive_restore_chains.sh"
if [ -s "$TMP/prepare_archive_restore_chains.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$TMP/prepare_archive_restore_chains.sh"
fi
for function_name in find_full_backup_path archive_has_pitr_basefull init_basefull_info update_basefull_info backup_database_log; do
  extract_function "$ARCHIVE_BACKUP" "$function_name" "$TMP/${function_name}.sh"
  if [ -s "$TMP/${function_name}.sh" ]; then
    # shellcheck disable=SC1090
    source "$TMP/${function_name}.sh"
  fi
done
extract_function "$ENTRYPOINT" read_chain_entries "$TMP/read_chain_entries.sh"
if [ -s "$TMP/read_chain_entries.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$TMP/read_chain_entries.sh"
fi

SPACE_PATH="customer west/customer west.full.bak.zst"
NEWLINE_PATH=$'line\nbreak/line\nbreak.full.bak.zst'
UNICODE_PATH="雪 db/雪 db.full.bak.zst"
TRAILING_NEWLINE_PATH=$'tail\n/tail\n.full.bak.zst'

datasafed() {
  if [ "${1-}" != list ]; then
    return 1
  fi
  if [ "${DATASAFED_JSON_MODE:-valid}" = malformed ]; then
    printf '{not-json}\n'
    return 0
  fi
  if [ "${DATASAFED_JSON_MODE:-valid}" = empty ]; then
    printf '[{"path":""}]\n'
    return 0
  fi
  perl -MJSON::PP -MEncode=decode,FB_CROAK -e '
    print encode_json([
      map { +{ path => decode("UTF-8", $_, FB_CROAK), mtime => 1 } } @ARGV
    ]), "\n";
  ' "$SPACE_PATH" "$NEWLINE_PATH" "$UNICODE_PATH" "$TRAILING_NEWLINE_PATH"
}

read_nul_file() {
  local file="$1"
  NUL_VALUES=()
  while IFS= read -r -d '' value; do
    NUL_VALUES+=("$value")
  done < "$file"
}

case_datasafed_json_transport() (
  declare -F datasafed_list_paths_to_file >/dev/null || return 1
  local output="$TMP/list-paths.nul"
  DATASAFED_JSON_MODE=valid
  datasafed_list_paths_to_file "$output" -f --recursive / || return 1
  read_nul_file "$output"
  local expected=("$SPACE_PATH" "$NEWLINE_PATH" "$UNICODE_PATH" "$TRAILING_NEWLINE_PATH")
  [ "${#NUL_VALUES[@]}" -eq "${#expected[@]}" ] || return 1
  local index
  for index in "${!expected[@]}"; do
    [ "${NUL_VALUES[$index]}" = "${expected[$index]}" ] || return 1
  done
)

case_datasafed_json_fails_atomically() (
  declare -F datasafed_list_paths_to_file >/dev/null || return 1
  local output="$TMP/malformed-list.nul"
  printf 'sentinel' > "$output"
  DATASAFED_JSON_MODE=malformed
  ! datasafed_list_paths_to_file "$output" -f / 2> "$TMP/malformed-json.err" || return 1
  [ -s "$TMP/malformed-json.err" ] || return 1
  [ "$(cat "$output")" = sentinel ] || return 1

  DATASAFED_JSON_MODE=empty
  ! datasafed_list_paths_to_file "$output" -f / 2> "$TMP/empty-path.err" || return 1
  [ -s "$TMP/empty-path.err" ] || return 1
  [ "$(cat "$output")" = sentinel ]
)

case_metadata_mixed_format_round_trip() (
  declare -F archive_metadata_write_single_record >/dev/null || return 1
  declare -F archive_metadata_append_record >/dev/null || return 1
  declare -F archive_metadata_load_file >/dev/null || return 1
  declare -F archive_metadata_set_last_next >/dev/null || return 1

  local file="$TMP/basefull.info"
  local unsafe_path=$'pitr/customer west/line\nbreak.full.bak.zst'
  archive_metadata_write_single_record "$file" "legacy/db.full.bak.zst" 100 110 || return 1
  archive_metadata_append_record "$file" "$unsafe_path" 200 NEXT_LOG_BACKUP_PLACEHOLDER || return 1

  [ "$(head -n 1 "$file")" = "legacy/db.full.bak.zst 100 110" ] || return 1
  sed -n '2p' "$file" | grep -q $'^v2\t[0-9a-f][0-9a-f]*\t200\tNEXT_LOG_BACKUP_PLACEHOLDER$' || return 1

  archive_metadata_load_file "$file" || return 1
  [ "${#ARCHIVE_METADATA_PATHS[@]}" -eq 2 ] || return 1
  [ "${ARCHIVE_METADATA_PATHS[0]}" = "legacy/db.full.bak.zst" ] || return 1
  [ "${ARCHIVE_METADATA_PATHS[1]}" = "$unsafe_path" ] || return 1
  [ "${ARCHIVE_METADATA_FULL_TIMESTAMPS[1]}" = 200 ] || return 1
  [ "${ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS[1]}" = NEXT_LOG_BACKUP_PLACEHOLDER ] || return 1

  archive_metadata_set_last_next "$file" 210 || return 1
  archive_metadata_load_file "$file" || return 1
  [ "${ARCHIVE_METADATA_PATHS[1]}" = "$unsafe_path" ] || return 1
  [ "${ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS[1]}" = 210 ] || return 1
  sed -n '2p' "$file" | grep -q $'^v2\t[0-9a-f][0-9a-f]*\t200\t210$'
)

case_metadata_rejects_ambiguous_or_invalid_rows() (
  declare -F archive_metadata_load_file >/dev/null || return 1
  local file="$TMP/bad-basefull.info"

  printf 'path with spaces 100 110\n' > "$file"
  ! archive_metadata_load_file "$file" || return 1
  [ "${#ARCHIVE_METADATA_PATHS[@]}" -eq 0 ] || return 1

  printf 'v2\txyz\t100\t110\n' > "$file"
  ! archive_metadata_load_file "$file" || return 1
  [ "${#ARCHIVE_METADATA_PATHS[@]}" -eq 0 ] || return 1

  printf 'legacy/path 100 not-a-time\n' > "$file"
  ! archive_metadata_load_file "$file" || return 1
  [ "${#ARCHIVE_METADATA_PATHS[@]}" -eq 0 ]
)

case_chain_manifest_round_trip() (
  declare -F archive_chain_format_entry >/dev/null || return 1
  declare -F read_chain_entries >/dev/null || return 1
  local file="$TMP/archive.chain"
  local newline_path=$'customer west\n雪/customer west\n雪.110.bak.zst'
  archive_chain_format_entry 'legacy/path.100.bak.zst' > "$file" || return 1
  archive_chain_format_entry "$newline_path" >> "$file" || return 1
  sed -n '2p' "$file" | grep -q $'^v2\t[0-9a-f][0-9a-f]*$' || return 1
  read_chain_entries "$file" || return 1
  [ "${#CHAIN_ENTRIES[@]}" -eq 2 ] || return 1
  [ "${CHAIN_ENTRIES[0]}" = 'legacy/path.100.bak.zst' ] || return 1
  [ "${CHAIN_ENTRIES[1]}" = "$newline_path" ] || return 1

  printf 'v2\txyz\n' > "$file"
  ! read_chain_entries "$file" || return 1
  [ "${#CHAIN_ENTRIES[@]}" -eq 0 ]
)

case_archive_backup_discovers_exact_paths() (
  declare -F find_full_backup_path >/dev/null || return 1
  declare -F archive_has_pitr_basefull >/dev/null || return 1
  local database_name=$'customer west\n雪.v1'
  local oldest="backup-20260101010101/${database_name}.full.bak.zst"
  local newest="backup-20260202020202/${database_name}.full.bak.zst"
  DP_BACKUP_NAME=pitr-backup
  datasafed() {
    if printf '%s\n' "$@" | grep -q '/pitr-backup'; then
      perl -MJSON::PP -MEncode=decode,FB_CROAK -e '
        my $name = decode("UTF-8", $ARGV[0], FB_CROAK);
        print encode_json([{path => "pitr-backup/$name/$name.basefull.150.bak.zst", mtime => 1}]), "\n";
      ' "$database_name"
    else
      perl -MJSON::PP -MEncode=decode,FB_CROAK -e '
        print encode_json([map { +{path => decode("UTF-8", $_, FB_CROAK), mtime => 1} } @ARGV]), "\n";
      ' "$newest" "$oldest"
    fi
  }
  [ "$(find_full_backup_path "$database_name" oldest)" = "$oldest" ] || return 1
  [ "$(find_full_backup_path "$database_name" newest)" = "$newest" ] || return 1
  archive_has_pitr_basefull "$database_name"
)

case_archive_backup_writes_and_advances_v2_metadata() (
  declare -F init_basefull_info >/dev/null || return 1
  declare -F backup_database_log >/dev/null || return 1
  local database_name=$'customer west\n雪.v1'
  local full_path="external-20260101010101/${database_name}.full.bak.zst"
  BACKUP_DIR="$TMP/archive-producer"
  DP_BACKUP_NAME=pitr-backup
  NEXT_LOG_BACKUP_PLACEHOLDER=NEXT_LOG_BACKUP_PLACEHOLDER
  BACKUP_INTERVAL=600
  GLOBAL_END_TIME=0
  mkdir -p "$BACKUP_DIR/$DP_BACKUP_NAME"

  get_full_backup_timestamp() { printf '100\n'; }
  init_basefull_info "$database_name" "$full_path" || return 1
  local metadata="$BACKUP_DIR/$DP_BACKUP_NAME/$database_name.basefull.info"
  archive_metadata_load_file "$metadata" || return 1
  [ "${ARCHIVE_METADATA_PATHS[0]}" = "$full_path" ] || return 1
  [ "${ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS[0]}" = NEXT_LOG_BACKUP_PLACEHOLDER ] || return 1

  PUSHED_REMOTES=()
  datasafed() {
    [ "$1" = push ] || return 1
    PUSHED_REMOTES+=("${!#}")
  }
  backup_login_names() { :; }
  check_fullbackup_dir() { :; }
  do_log_backup() {
    : > "$BACKUP_DIR/$DP_BACKUP_NAME/$1.log.bak"
  }
  get_log_backup_timestamp() { printf '110\n'; }
  date() { printf '120\n'; }
  backup_database_log "$database_name" || return 1

  archive_metadata_load_file "$metadata" || return 1
  [ "${ARCHIVE_METADATA_PATHS[0]}" = "$full_path" ] || return 1
  [ "${ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS[0]}" = 110 ] || return 1
  [ "$GLOBAL_END_TIME" -eq 110 ] || return 1
  [ "${#PUSHED_REMOTES[@]}" -eq 2 ] || return 1
  [ "${PUSHED_REMOTES[0]}" = "$database_name/$database_name.110.bak.zst" ] || return 1
  [ "${PUSHED_REMOTES[1]}" = "$database_name.basefull.info" ] || return 1
  [ ! -e "$BACKUP_DIR/$DP_BACKUP_NAME/$database_name.log.bak" ]
)

case_archive_backup_trims_metadata_by_exact_path() (
  declare -F update_basefull_info >/dev/null || return 1
  local database_name="customer west"
  local old_path="backup-20250101010101/$database_name.full.bak.zst"
  local oldest_path="backup-20260101010101/$database_name.full.bak.zst"
  local newest_path="backup-20260202020202/$database_name.full.bak.zst"
  BACKUP_DIR="$TMP/archive-trim"
  DP_BACKUP_NAME=pitr-backup
  DP_BACKUP_BASE_PATH=/repo/pitr-backup
  NEXT_LOG_BACKUP_PLACEHOLDER=NEXT_LOG_BACKUP_PLACEHOLDER
  local metadata="$BACKUP_DIR/$DP_BACKUP_NAME/$database_name.basefull.info"
  mkdir -p "$(dirname "$metadata")"
  archive_metadata_write_single_record "$metadata" "$old_path" 10 11 || return 1
  archive_metadata_append_record "$metadata" "$oldest_path" 20 21 || return 1
  archive_metadata_append_record "$metadata" "$newest_path" 30 31 || return 1

  find_full_backup_path() { printf '%s' "$oldest_path"; }
  PUSHED_REMOTES=()
  REMOVED_REMOTES=()
  datasafed() {
    case "$1" in
      list)
        perl -MJSON::PP -e 'print encode_json([{path => "customer west/customer west.15.bak.zst", mtime => 15},{path => "customer west/customer west.25.bak.zst", mtime => 25}]), "\n"'
        ;;
      push)
        PUSHED_REMOTES+=("${!#}")
        ;;
      rm)
        REMOVED_REMOTES+=("$2")
        ;;
      *) return 1 ;;
    esac
  }
  update_basefull_info "$database_name" "$newest_path" || return 1
  archive_metadata_load_file "$metadata" || return 1
  [ "${#ARCHIVE_METADATA_PATHS[@]}" -eq 2 ] || return 1
  [ "${ARCHIVE_METADATA_PATHS[0]}" = "$oldest_path" ] || return 1
  [ "${ARCHIVE_METADATA_PATHS[1]}" = "$newest_path" ] || return 1
  [ "${PUSHED_REMOTES[0]}" = "$database_name.basefull.info" ] || return 1
  [ "${#REMOVED_REMOTES[@]}" -eq 1 ] || return 1
  [ "${REMOVED_REMOTES[0]}" = "$database_name/$database_name.15.bak.zst" ] || return 1
  [ "$DATASAFED_BACKEND_BASE_PATH" = "$DP_BACKUP_BASE_PATH" ] || return 1

  find_full_backup_path() { return 1; }
  ! update_basefull_info "$database_name" "$newest_path" || return 1
  [ "$DATASAFED_BACKEND_BASE_PATH" = "$DP_BACKUP_BASE_PATH" ]
)

write_mock_tools() {
  local mockbin="$1" fixture="$2"
  mkdir -p "$mockbin"
  cat > "$mockbin/date" <<'MOCKDATE'
#!/usr/bin/env bash
if [ "${1-}" = -d ]; then
  if [ "${3-}" = +%s ]; then
    printf '115\n'
  else
    printf '1970-01-01 00:01:55\n'
  fi
  exit 0
fi
exec /bin/date "$@"
MOCKDATE
  chmod +x "$mockbin/date"

  cat > "$mockbin/datasafed" <<'MOCKDATASAFED'
#!/usr/bin/env bash
set -eu
command="$1"
shift
case "$command" in
  list)
    json=false
    for arg in "$@"; do
      [ "$arg" = -o ] && json=true
    done
    if printf '%s\n' "$@" | grep -qx -- -d; then
      if [ "$json" = true ]; then
        printf '[{"path":"customer.v1 west/","mtime":1}]\n'
      else
        printf 'customer.v1 west/\n'
      fi
    else
      if [ "$json" = true ]; then
        printf '[{"path":"customer.v1 west/customer.v1 west.basefull.100.bak.zst","mtime":100},{"path":"customer.v1 west/customer.v1 west.110.bak.zst","mtime":110},{"path":"customer.v1 west/customer.v1 west.120.bak.zst","mtime":120}]\n'
      else
        printf 'customer.v1 west/customer.v1 west.basefull.100.bak.zst\n'
        printf 'customer.v1 west/customer.v1 west.110.bak.zst\n'
        printf 'customer.v1 west/customer.v1 west.120.bak.zst\n'
      fi
    fi
    ;;
  pull)
    if [ "${1-}" = -d ]; then
      shift 2
    fi
    remote="$1"
    local_path="$2"
    printf '%s\0' "$remote" >> "$DATASAFED_PULLS"
    mkdir -p "$(dirname "$local_path")"
    if [ "$remote" = 'customer.v1 west.basefull.info' ]; then
      cp "$BASEFULL_FIXTURE" "$local_path"
    else
      : > "$local_path"
    fi
    ;;
  *)
    exit 1
    ;;
esac
MOCKDATASAFED
  chmod +x "$mockbin/datasafed"

  local path='pitr-backup/customer.v1 west/customer.v1 west.basefull.100.bak.zst'
  local hex
  hex=$(printf '%s' "$path" | perl -e 'local $/; print unpack("H*", <STDIN>)')
  printf 'v2\t%s\t100\t110\n' "$hex" > "$fixture"
}

case_archive_restore_uses_exact_paths() (
  declare -F prepare_archive_restore_chains >/dev/null || return 1
  local root="$TMP/archive-restore" mockbin="$TMP/mockbin" fixture="$TMP/remote.basefull.info"
  mkdir -p "$root"
  write_mock_tools "$mockbin" "$fixture"

  export PATH="$mockbin:$PATH"
  unset -f datasafed
  export DATASAFED_PULLS="$TMP/pulls.nul"
  export BASEFULL_FIXTURE="$fixture"
  : > "$DATASAFED_PULLS"
  BACKUP_DIR="$root"
  DP_BACKUP_NAME=pitr-backup
  DP_BACKUP_BASE_PATH=/repo/pitr-backup
  DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
  INIT_ARCHIVE_PATH="$BACKUP_DIR/INIT_ARCHIVE_BACKUPS"
  restore_time=115
  mkdir -p "$INIT_ARCHIVE_PATH"
  DP_log() { :; }
  DP_error_log() { :; }

  prepare_archive_restore_chains || return 1

  local chain="$INIT_ARCHIVE_PATH/customer.v1 west.chain"
  [ -f "$chain" ] || return 1
  read_chain_entries "$chain" || return 1
  local expected_chain=(
    'customer.v1 west.basefull.bak'
    'customer.v1 west/customer.v1 west.110.bak.zst'
    'customer.v1 west/customer.v1 west.120.bak.zst'
  )
  [ "${#CHAIN_ENTRIES[@]}" -eq "${#expected_chain[@]}" ] || return 1
  local chain_index
  for chain_index in "${!expected_chain[@]}"; do
    [ "${CHAIN_ENTRIES[$chain_index]}" = "${expected_chain[$chain_index]}" ] || return 1
  done

  read_nul_file "$DATASAFED_PULLS"
  local expected_pulls=(
    'customer.v1 west.basefull.info'
    'customer.v1 west/customer.v1 west.basefull.100.bak.zst'
    'customer.v1 west/customer.v1 west.110.bak.zst'
    'customer.v1 west/customer.v1 west.120.bak.zst'
  )
  [ "${#NUL_VALUES[@]}" -eq "${#expected_pulls[@]}" ] || return 1
  local index
  for index in "${!expected_pulls[@]}"; do
    [ "${NUL_VALUES[$index]}" = "${expected_pulls[$index]}" ] || return 1
  done
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

run_case "DataSafed JSON paths survive whitespace, newlines, and Unicode" case_datasafed_json_transport
run_case "malformed DataSafed JSON fails without replacing prior output" case_datasafed_json_fails_atomically
run_case "legacy and v2 basefull metadata round-trip exactly" case_metadata_mixed_format_round_trip
run_case "ambiguous or invalid basefull metadata fails closed" case_metadata_rejects_ambiguous_or_invalid_rows
run_case "archive chain manifest round-trips newline paths" case_chain_manifest_round_trip
run_case "archive backup discovers exact full and PITR base paths" case_archive_backup_discovers_exact_paths
run_case "archive backup writes and advances v2 metadata" case_archive_backup_writes_and_advances_v2_metadata
run_case "archive backup trims metadata and objects by exact path" case_archive_backup_trims_metadata_by_exact_path
run_case "archive restore pulls exact base/log paths and excludes PITR basefull" case_archive_restore_uses_exact_paths

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
