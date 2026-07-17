# shellcheck shell=bash

Describe "MongoDB dataprotection common script"
  Include ../dataprotection/common-scripts.sh

  setup_polling() {
    POLL_STATE_FILE="$(mktemp)"
    echo 0 > "$POLL_STATE_FILE"
    export SYNCER_PBM_WAIT_INTERVAL_SECONDS=0
    export SYNCER_RESTORE_WAIT_INTERVAL_SECONDS=0
  }
  BeforeEach 'setup_polling'

  cleanup_polling() {
    rm -f "$POLL_STATE_FILE"
  }
  AfterEach 'cleanup_polling'

  sleep() { :; }

  syncerctl_cmd() {
    local count
    count=$(cat "$POLL_STATE_FILE")
    count=$((count + 1))
    echo "$count" > "$POLL_STATE_FILE"

    if [ "$1 $2" = "backup status" ]; then
      if [ "$count" -lt 3 ]; then
        echo '{"found":true,"status":"running"}'
      else
        echo '{"found":true,"status":"done"}'
      fi
      return
    fi

    if [ "$count" -lt 3 ]; then
      echo '{"status":"running","phase":"in-restore"}'
    else
      echo '{"status":"done","phase":"done"}'
    fi
  }

  It "waits for backup completion without a retry limit"
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be success
    The output should include "Backup backup-1 status: found=true status=done"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End

  It "waits for restore completion without a retry limit"
    When call wait_for_syncer_restore_completion "request-1"
    The status should be success
    The output should include "Restore request request-1 phase=done"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End
End
