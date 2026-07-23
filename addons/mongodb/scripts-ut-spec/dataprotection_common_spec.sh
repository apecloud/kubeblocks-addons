# shellcheck shell=bash

Describe "MongoDB dataprotection common script"
  Include ../dataprotection/common-scripts.sh

  setup_polling() {
    POLL_STATE_FILE="$(mktemp)"
    echo 0 > "$POLL_STATE_FILE"
    export SYNCER_PBM_WAIT_MAX_ATTEMPTS=3
    export SYNCER_RESTORE_WAIT_MAX_ATTEMPTS=3
    export SYNCER_PBM_WAIT_INTERVAL_SECONDS=0
    export SYNCER_RESTORE_WAIT_INTERVAL_SECONDS=0
    POLL_MODE=eventual
    unset DP_DB_HOST DP_TARGET_POD_NAME POD_NAME CLUSTER_COMPONENT_NAME
    unset KB_CLUSTER_COMP_NAME CLUSTER_NAMESPACE KB_NAMESPACE POD_NAMESPACE
    unset KUBERNETES_CLUSTER_DOMAIN
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
      case "$POLL_MODE" in
        backup-running)
          echo '{"found":true,"status":"running"}'
          ;;
        backup-missing)
          echo '{"found":false}'
          ;;
        backup-empty)
          echo '{}'
          ;;
        *)
          if [ "$count" -lt 3 ]; then
            echo '{"found":true,"status":"running"}'
          else
            echo '{"found":true,"status":"done"}'
          fi
          ;;
      esac
      return
    fi

    case "$POLL_MODE" in
      restore-error)
        echo "status endpoint unavailable" >&2
        return 17
        ;;
      restore-running)
        echo '{"status":"running","phase":"in-restore"}'
        ;;
      *)
        if [ "$count" -lt 3 ]; then
          echo '{"status":"running","phase":"in-restore"}'
        else
          echo '{"status":"done","phase":"done"}'
        fi
        ;;
    esac
  }

  It "waits for backup completion within the configured attempt budget"
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be success
    The output should include "Backup backup-1 status: found=true status=done"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End

  It "fails a persistently running backup at the configured ceiling"
    POLL_MODE=backup-running
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be failure
    The output should include "Backup backup-1 did not complete after 3 attempts"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End

  It "fails a backup that remains undiscoverable at the configured ceiling"
    POLL_MODE=backup-missing
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be failure
    The output should include "Backup backup-1 did not complete after 3 attempts"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End

  It "fails an empty backup status at the configured ceiling"
    POLL_MODE=backup-empty
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be failure
    The output should include "Backup backup-1 did not complete after 3 attempts"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End

  It "waits for restore completion within the configured attempt budget"
    When call wait_for_syncer_restore_completion "request-1"
    The status should be success
    The output should include "Restore request request-1 phase=done"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End

  It "fails a persistently running restore at the configured ceiling"
    POLL_MODE=restore-running
    When call wait_for_syncer_restore_completion "request-1"
    The status should be failure
    The output should include "Restore request request-1 did not complete after 3 attempts"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End

  It "fails persistent restore status errors at the configured ceiling"
    POLL_MODE=restore-error
    When call wait_for_syncer_restore_completion "request-1"
    The status should be failure
    The output should include "status endpoint unavailable"
    The output should include "Restore request request-1 did not complete after 3 attempts"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End

  It "rejects an invalid polling attempt budget before polling"
    SYNCER_PBM_WAIT_MAX_ATTEMPTS=0
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be failure
    The output should include "SYNCER_PBM_WAIT_MAX_ATTEMPTS must be an integer in range 1..9999999"
    The contents of file "$POLL_STATE_FILE" should equal 0
  End

  It "rejects an oversized backup attempt budget before polling"
    SYNCER_PBM_WAIT_MAX_ATTEMPTS=999999999999999999999999999999999999
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be failure
    The output should include "SYNCER_PBM_WAIT_MAX_ATTEMPTS must be an integer in range 1..9999999"
    The contents of file "$POLL_STATE_FILE" should equal 0
  End

  It "rejects an invalid restore attempt budget before polling"
    SYNCER_RESTORE_WAIT_MAX_ATTEMPTS=invalid
    When call wait_for_syncer_restore_completion "request-1"
    The status should be failure
    The output should include "SYNCER_RESTORE_WAIT_MAX_ATTEMPTS must be an integer in range 1..9999999"
    The contents of file "$POLL_STATE_FILE" should equal 0
  End

  It "rejects an oversized restore attempt budget before polling"
    SYNCER_RESTORE_WAIT_MAX_ATTEMPTS=999999999999999999999999999999999999
    When call wait_for_syncer_restore_completion "request-1"
    The status should be failure
    The output should include "SYNCER_RESTORE_WAIT_MAX_ATTEMPTS must be an integer in range 1..9999999"
    The contents of file "$POLL_STATE_FILE" should equal 0
  End

  It "accepts the maximum shell-safe polling attempt budget"
    When call require_poll_attempt_budget "TEST_WAIT_MAX_ATTEMPTS" 9999999
    The status should be success
    The output should equal ""
  End

  It "prefers the API-provided target host even when a target Pod name is present"
    export DP_DB_HOST="mongo-0.custom-subdomain.example"
    export DP_TARGET_POD_NAME="mongo-0"
    export CLUSTER_COMPONENT_NAME="mongodb"
    export CLUSTER_NAMESPACE="demo"
    When call target_syncer_host
    The status should be success
    The output should equal "mongo-0.custom-subdomain.example"
  End

  It "constructs a conventional target host only when the API host is absent"
    export DP_TARGET_POD_NAME="mongo-0"
    export CLUSTER_COMPONENT_NAME="mongodb"
    export CLUSTER_NAMESPACE="demo"
    export KUBERNETES_CLUSTER_DOMAIN="cluster.example"
    When call target_syncer_host
    The status should be success
    The output should equal "mongo-0.mongodb-headless.demo.svc.cluster.example"
  End
End
