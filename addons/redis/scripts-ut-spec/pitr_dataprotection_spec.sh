# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "pitr_dataprotection_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis PITR dataprotection scripts"
  setup_pitr_env() {
    PITR_REPO_ROOT=$(git rev-parse --show-toplevel)
    PITR_TMP=$(mktemp -d)
    PITR_WORKDIR="$PITR_TMP/work"
    PITR_BIN="$PITR_TMP/bin"
    PITR_DATASAFED_LOG="$PITR_TMP/datasafed.log"
    PITR_RM_MARKER="$PITR_TMP/datasafed-rm.marker"

    mkdir -p "$PITR_WORKDIR" "$PITR_BIN" "$PITR_TMP/data/appendonlydir"
    export PATH="$PITR_BIN:$PATH"
    export DATA_DIR="$PITR_TMP/data"
    export DP_DATASAFED_BIN_PATH="$PITR_BIN"
    export DP_BACKUP_BASE_PATH="/"
    export DP_DB_HOST="127.0.0.1"
    export DP_DB_PORT="6379"
    export DP_DB_PASSWORD=""
    export REDIS_CLI_TLS_CMD=""
    export DP_BACKUP_INFO_FILE="$PITR_TMP/backup-info.json"
    export LOG_ARCHIVE_SECONDS="600"
    export DP_RESTORE_TIME="1970-01-01T00:20:00Z"
    export PITR_DATASAFED_LOG PITR_RM_MARKER

    cat >"$PITR_BIN/date" <<'EOF'
#!/bin/sh
if [ "$1" = "-d" ]; then
  case "$2" in
    *00:20:00*) echo 1200 ;;
    *) echo 2000 ;;
  esac
  exit 0
fi
if [ "$1" = "+%s" ]; then
  echo 2000
  exit 0
fi
if [ "$1" = "-u" ]; then
  echo "1970-01-01 00:00:00"
  exit 0
fi
echo 2000
EOF

    cat >"$PITR_BIN/redis-cli" <<'EOF'
#!/bin/sh
case "$*" in
  *"CONFIG GET appenddirname"*) printf 'appenddirname\nappendonlydir\n' ;;
  *"CONFIG GET appendfilename"*) printf 'appendfilename\nappendonly.aof\n' ;;
  *"CONFIG GET aof-use-rdb-preamble"*) printf 'aof-use-rdb-preamble\nyes\n' ;;
  *"CONFIG GET aof-timestamp-enabled"*) printf 'aof-timestamp-enabled\nyes\n' ;;
  *"CONFIG GET aof-disable-auto-gc"*) printf 'aof-disable-auto-gc\nyes\n' ;;
  *) echo "OK" ;;
esac
EOF

    cat >"$PITR_BIN/redis-check-rdb" <<'EOF'
#!/bin/sh
echo "ctime '1000'"
EOF

    cat >"$PITR_BIN/datasafed" <<'EOF'
#!/bin/sh
case "$1" in
  list)
    case "$PITR_DATASAFED_LIST_MODE" in
      tar) echo "1000.1.tar.zst" ;;
      unknown) echo "1000.1.bad" ;;
      *) : ;;
    esac
    ;;
  push)
    echo "push $*" >> "$PITR_DATASAFED_LOG"
    exit "${PITR_PUSH_STATUS:-0}"
    ;;
  pull)
    echo "pull $*" >> "$PITR_DATASAFED_LOG"
    printf 'not-a-tar'
    exit "${PITR_PULL_STATUS:-0}"
    ;;
  rm)
    echo "rm $*" >> "$PITR_DATASAFED_LOG"
    touch "$PITR_RM_MARKER"
    ;;
  stat)
    echo "TotalSize 0"
    ;;
esac
EOF

    chmod +x "$PITR_BIN/date" "$PITR_BIN/redis-cli" "$PITR_BIN/redis-check-rdb" "$PITR_BIN/datasafed"
  }

  cleanup_pitr_env() {
    rm -rf "$PITR_TMP"
  }

  BeforeEach "setup_pitr_env"
  AfterEach "cleanup_pitr_env"

  run_pitr_backup() {
    (
      cd "$PITR_WORKDIR" || exit 1
      . "$PITR_REPO_ROOT/addons/redis/dataprotection/common-scripts.sh"
      . "$PITR_REPO_ROOT/addons/redis/dataprotection/pitr-backup.sh"
    )
  }

  run_pitr_restore() {
    (
      cd "$PITR_WORKDIR" || exit 1
      . "$PITR_REPO_ROOT/addons/redis/dataprotection/common-scripts.sh"
      . "$PITR_REPO_ROOT/addons/redis/dataprotection/pitr-restore.sh"
    )
  }

  prepare_archive_pair() {
    echo "file appendonly.aof.2.incr.aof seq 2 type i" > "$DATA_DIR/appendonlydir/appendonly.aof.manifest"
    echo "base" > "$DATA_DIR/appendonlydir/appendonly.aof.1.base.rdb"
    echo "incr" > "$DATA_DIR/appendonlydir/appendonly.aof.1.incr.aof"
    echo "user default on nopass ~* +@all" > "$DATA_DIR/users.acl"
    BACKUP_BASE_FILE="$DATA_DIR/appendonlydir/appendonly.aof.1.base.rdb"
    BACKUP_INCR_FILE="$DATA_DIR/appendonlydir/appendonly.aof.1.incr.aof"
    export PITR_DATASAFED_LIST_MODE="empty"
    export PITR_PUSH_STATUS="42"
  }

  It "does not delete tracked PITR files when archive upload fails"
    prepare_archive_pair

    When run run_pitr_backup
    The status should be failure
    The stdout should include "INFO: start to backup"
    The stderr should include "appendonly.aof.1.incr.aof"
    The path "$BACKUP_BASE_FILE" should be exist
    The path "$BACKUP_INCR_FILE" should be exist
    The path "$PITR_RM_MARKER" should not be exist
  End

  It "fails restore when no PITR archive matches the requested restore time"
    export PITR_DATASAFED_LIST_MODE="empty"

    When run run_pitr_restore
    The status should be failure
    The output should include "ERROR: No backup found for the given restore time"
    The path "$DATA_DIR/.kb-data-protection" should be exist
    The output should not include "Restore complete."
  End

  It "fails restore when archive pull or extraction fails"
    export PITR_DATASAFED_LIST_MODE="tar"
    export PITR_PULL_STATUS="42"

    When run run_pitr_restore
    The status should be failure
    The stderr should include "tar:"
    The path "$DATA_DIR/.kb-data-protection" should be exist
    The output should not include "Restore complete."
  End

  It "fails restore when the selected PITR object has an unknown type"
    export PITR_DATASAFED_LIST_MODE="unknown"

    When run run_pitr_restore
    The status should be failure
    The output should include "ERROR: Unknown aof_file type: 1000.1.bad"
    The output should not include "Restore complete."
  End
End
