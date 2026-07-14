# shellcheck shell=bash

Describe 'Redis physical restore bootstrap authorization'
  setup_restore_fixture() {
    export RESTORE_FIXTURE_ROOT='./redis-restore-fixture'
    export RESTORE_FIXTURE_ARCHIVE="$RESTORE_FIXTURE_ROOT/backup.tar.gz"
    export DATA_DIR="$RESTORE_FIXTURE_ROOT/data"
    export DP_DATASAFED_BIN_PATH="$RESTORE_FIXTURE_ROOT/bin"
    export DP_BACKUP_BASE_PATH='fixture'
    export DP_BACKUP_NAME='backup'
    export REDIS_RESTORE_BOOTSTRAP_MARKER="$DATA_DIR/.kb-redis-restore-bootstrap-authorized"

    mkdir -p "$RESTORE_FIXTURE_ROOT/bin" "$RESTORE_FIXTURE_ROOT/source"
    printf 'restored-data\n' > "$RESTORE_FIXTURE_ROOT/source/dump.rdb"
    tar -czf "$RESTORE_FIXTURE_ARCHIVE" -C "$RESTORE_FIXTURE_ROOT/source" dump.rdb
    printf '%s\n' \
      '#!/bin/sh' \
      'case "$1" in' \
      '  list) exit 0 ;;' \
      '  pull)' \
      '    [ "${RESTORE_FIXTURE_FAIL:-false}" = true ] && exit 1' \
      '    cat "$RESTORE_FIXTURE_ARCHIVE"' \
      '    ;;' \
      'esac' > "$DP_DATASAFED_BIN_PATH/datasafed"
    chmod +x "$DP_DATASAFED_BIN_PATH/datasafed"
  }
  Before 'setup_restore_fixture'

  cleanup_restore_fixture() {
    unset RESTORE_FIXTURE_ROOT RESTORE_FIXTURE_ARCHIVE RESTORE_FIXTURE_FAIL
    unset DATA_DIR DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH DP_BACKUP_NAME
    unset REDIS_RESTORE_BOOTSTRAP_MARKER
    rm -rf ./redis-restore-fixture
  }
  After 'cleanup_restore_fixture'

  It 'creates authorization only after a successful archive extraction'
    When run sh -c 'bash ../dataprotection/restore.sh 2>/dev/null'
    The status should be success
    The path "$DATA_DIR/dump.rdb" should be file
    The path "$DATA_DIR/.kb-data-protection" should not be exist
    The path "$REDIS_RESTORE_BOOTSTRAP_MARKER" should be file
  End

  It 'does not authorize bootstrap when the archive pull fails'
    export RESTORE_FIXTURE_FAIL=true
    When run sh -c 'bash ../dataprotection/restore.sh 2>/dev/null'
    The status should be failure
    The path "$REDIS_RESTORE_BOOTSTRAP_MARKER" should not be exist
  End
End
