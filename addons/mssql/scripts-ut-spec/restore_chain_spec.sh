# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# shellcheck shell=bash
# shellcheck disable=SC2034

ut_mode="true"

Describe "SQL Server restore chain functions"
  Include ../scripts/entrypoint.sh

  setup() {
    TEST_TMP_DIR=$(mktemp -d)
    BACKUP_DIR="${TEST_TMP_DIR}/backup dir"
    TRACE="${TEST_TMP_DIR}/trace"
    mkdir -p "$BACKUP_DIR/INIT_BACKUPS" "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS"
    : > "$TRACE"
    use_text_trace_stubs
  }

  cleanup() {
    rm -rf "$TEST_TMP_DIR"
  }

  log() { :; }

  use_text_trace_stubs() {
    restore_database() { printf 'RECOVERY|%s|%s\n' "$1" "$2" >> "$TRACE"; }
    restore_database_with_no_recovery() {
      printf 'NORECOVERY|%s|%s\n' "$1" "$2" >> "$TRACE"
    }
    restore_from_archive_backup() {
      printf 'ARCHIVE|%s|%s\n' "$1" "$2" >> "$TRACE"
    }
    add_db_to_ag() { printf 'ADD|%s\n' "$1" >> "$TRACE"; }
    join_secondary_database_to_ag() { printf 'JOIN|%s\n' "$1" >> "$TRACE"; }
  }

  use_exact_trace_stubs() {
    restore_database() { printf 'RECOVERY\0%s\0%s\0' "$1" "$2" >> "$TRACE"; }
    restore_database_with_no_recovery() {
      printf 'NORECOVERY\0%s\0%s\0' "$1" "$2" >> "$TRACE"
    }
    restore_from_archive_backup() {
      printf 'ARCHIVE\0%s\0%s\0' "$1" "$2" >> "$TRACE"
    }
    add_db_to_ag() { printf 'ADD\0%s\0' "$1" >> "$TRACE"; }
    join_secondary_database_to_ag() { printf 'JOIN\0%s\0' "$1" >> "$TRACE"; }
  }

  read_chain_count() {
    read_chain_entries "$1"
    printf '%s\n' "${#CHAIN_ENTRIES[@]}"
  }

  nul_manifest_is_exact() {
    read_chain_entries "$1"
    [ "${#CHAIN_ENTRIES[@]}" -eq 3 ] &&
      [ "${CHAIN_ENTRIES[0]}" = 'full backup.bak' ] &&
      [ "${CHAIN_ENTRIES[1]}" = $'line\nlog.trn' ] &&
      [ "${CHAIN_ENTRIES[2]}" = $'tail\n' ]
  }

  lacks_snapshot_restore_support() {
    ! declare -F snapshot_restore_chain_files >/dev/null
  }

  expect_restore_failure_without_trace() {
    : > "$TRACE"
    if "$@" 2>/dev/null; then
      return 1
    fi
    [ ! -s "$TRACE" ]
  }

  run_space_dispatch_case() {
    use_exact_trace_stubs
    rm -rf "$BACKUP_DIR/INIT_BACKUPS"
    mkdir -p "$BACKUP_DIR/INIT_BACKUPS"
    printf '%s\0' 'full backup.bak' \
      > "$BACKUP_DIR/INIT_BACKUPS/customer west.chain"
    printf '%s\0' ignored \
      > "$BACKUP_DIR/INIT_BACKUPS/ignored.chain.tmp"

    restore_databases false || return
    printf 'RECOVERY\0customer west\0full backup.bak\0ADD\0customer west\0' \
      > "$TEST_TMP_DIR/expected"
    cmp -s "$TEST_TMP_DIR/expected" "$TRACE"
  }

  run_newline_dispatch_case() {
    use_exact_trace_stubs
    local database_name=$'customer\nwest'
    local media_name=$'full\nbackup.bak'
    rm -rf "$BACKUP_DIR/INIT_BACKUPS"
    mkdir -p "$BACKUP_DIR/INIT_BACKUPS"
    printf '%s\0' "$media_name" \
      > "$BACKUP_DIR/INIT_BACKUPS/${database_name}.chain"

    restore_databases false || return
    printf 'RECOVERY\0%s\0%s\0ADD\0%s\0' \
      "$database_name" "$media_name" "$database_name" \
      > "$TEST_TMP_DIR/expected"
    cmp -s "$TEST_TMP_DIR/expected" "$TRACE"
  }

  run_archive_newline_dispatch_case() {
    use_exact_trace_stubs
    local database_name=$'customer\nwest'
    rm -rf "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS"
    mkdir -p "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS"
    printf '%s\0' ignored \
      > "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS/${database_name}.chain"
    printf '%s\0' ignored \
      > "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS/ignored.chain.tmp"

    restore_archive_backups false || return
    printf 'ARCHIVE\0%s\0false\0ADD\0%s\0' \
      "$database_name" "$database_name" > "$TEST_TMP_DIR/expected"
    cmp -s "$TEST_TMP_DIR/expected" "$TRACE"
  }

  run_partial_producer_failure_case() {
    local restore_kind="$1"
    printf '%s\0' full.bak > "$BACKUP_DIR/INIT_BACKUPS/db.chain"
    printf '%s\0' ignored > "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS/db.chain"
    find() {
      case "$1" in
        */INIT_ARCHIVE_BACKUPS)
          printf '%s\0' "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS/db.chain"
          ;;
        *)
          printf '%s\0' "$BACKUP_DIR/INIT_BACKUPS/db.chain"
          ;;
      esac
      return 73
    }

    local status=0
    case "$restore_kind" in
      normal)
        expect_restore_failure_without_trace restore_databases false || status=$?
        ;;
      archive)
        expect_restore_failure_without_trace restore_archive_backups false || status=$?
        ;;
    esac
    unset -f find
    return "$status"
  }

  BeforeEach "setup"
  AfterEach "cleanup"

  It "reads every entry when the manifest has a trailing newline"
    printf 'full.bak\nlog1.trn\nlog2.trn\n' > "$TEST_TMP_DIR/db.chain"

    When call read_chain_count "$TEST_TMP_DIR/db.chain"
    The status should be success
    The output should equal "3"
  End

  It "reads every entry when the final line has no newline"
    printf 'full.bak\nlog1.trn\nlog2.trn' > "$TEST_TMP_DIR/db.chain"

    When call read_chain_count "$TEST_TMP_DIR/db.chain"
    The status should be success
    The output should equal "3"
  End

  It "ignores empty and whitespace-only manifest lines"
    printf 'full.bak\n\n  \t\nlog1.trn\n\n' > "$TEST_TMP_DIR/db.chain"

    When call read_chain_count "$TEST_TMP_DIR/db.chain"
    The status should be success
    The output should equal "2"
  End

  It "reads a single entry without a trailing newline"
    printf 'full.bak' > "$TEST_TMP_DIR/db.chain"

    When call read_chain_count "$TEST_TMP_DIR/db.chain"
    The status should be success
    The output should equal "1"
  End

  It "restores the true final primary entry with recovery"
    printf 'full.bak\n\nlog1.trn\nlog2.trn' \
      > "$BACKUP_DIR/INIT_BACKUPS/db.chain"

    When call restore_databases false
    The status should be success
    The contents of file "$TRACE" should equal "NORECOVERY|db|full.bak
NORECOVERY|db|log1.trn
RECOVERY|db|log2.trn
ADD|db"
  End

  It "keeps every secondary entry in no-recovery before joining"
    printf 'full.bak\nlog1.trn\nlog2.trn' \
      > "$BACKUP_DIR/INIT_BACKUPS/db.chain"

    When call restore_databases true
    The status should be success
    The contents of file "$TRACE" should equal "NORECOVERY|db|full.bak
NORECOVERY|db|log1.trn
NORECOVERY|db|log2.trn
JOIN|db"
  End

  It "discovers only exact chain manifests for normal restores"
    printf 'full.bak\n' > "$BACKUP_DIR/INIT_BACKUPS/valid.chain"
    printf 'decoy.bak\n' > "$BACKUP_DIR/INIT_BACKUPS/decoy.chain.tmp"
    printf 'decoy.bak\n' > "$BACKUP_DIR/INIT_BACKUPS/plainchain"

    When call restore_databases false
    The status should be success
    The contents of file "$TRACE" should equal "RECOVERY|valid|full.bak
ADD|valid"
  End

  It "discovers only exact chain manifests for archive restores"
    printf 'archive.bak\n' > "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS/valid.chain"
    printf 'decoy.bak\n' \
      > "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS/decoy.chain.tmp"
    printf 'decoy.bak\n' > "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS/plainchain"

    When call restore_archive_backups false
    The status should be success
    The contents of file "$TRACE" should equal "ARCHIVE|valid|false
ADD|valid"
  End

  Context "with PR1898 NUL and fail-closed discovery support"
    Skip if "requires PR1898 restore support" lacks_snapshot_restore_support

    It "preserves spaces and newlines in a NUL-delimited manifest"
      printf '%s\0' 'full backup.bak' $'line\nlog.trn' $'tail\n' \
        > "$TEST_TMP_DIR/db.chain"

      When call nul_manifest_is_exact "$TEST_TMP_DIR/db.chain"
      The status should be success
    End

    It "preserves a whitespace database and media name in full restore"
      When call run_space_dispatch_case
      The status should be success
    End

    It "preserves newline database and media names in full restore"
      When call run_newline_dispatch_case
      The status should be success
    End

    It "preserves a newline database name in archive restore"
      When call run_archive_newline_dispatch_case
      The status should be success
    End

    It "fails closed when the full restore staging directory is missing"
      rm -rf "$BACKUP_DIR/INIT_BACKUPS"

      When call expect_restore_failure_without_trace restore_databases false
      The status should be success
    End

    It "fails closed when the archive restore staging directory is missing"
      rm -rf "$BACKUP_DIR/INIT_ARCHIVE_BACKUPS"

      When call expect_restore_failure_without_trace restore_archive_backups false
      The status should be success
    End

    It "rejects a partial full-restore manifest from a failed producer"
      When call run_partial_producer_failure_case normal
      The status should be success
    End

    It "rejects a partial archive manifest from a failed producer"
      When call run_partial_producer_failure_case archive
      The status should be success
    End
  End
End
