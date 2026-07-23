# shellcheck shell=bash

Describe "MongoDB dataprotection common script"
  Include ../dataprotection/common-scripts.sh

  setup_polling() {
    POLL_STATE_FILE="$(mktemp)"
    TERM_IGNORING_CHILD_PID_FILE="$(mktemp)"
    SHELLSPEC_RUNNER_PGID=$(ps -o pgid= -p "$$" | tr -d " ")
    echo 0 > "$POLL_STATE_FILE"
    export TERM_IGNORING_CHILD_PID_FILE SHELLSPEC_RUNNER_PGID
    export SYNCER_PBM_WAIT_MAX_ATTEMPTS=3
    export SYNCER_RESTORE_WAIT_MAX_ATTEMPTS=3
    export SYNCER_STATUS_REQUEST_TIMEOUT_SECONDS=1
    export SYNCER_PBM_WAIT_INTERVAL_SECONDS=0
    export SYNCER_RESTORE_WAIT_INTERVAL_SECONDS=0
    POLL_MODE=eventual
    unset DP_DB_HOST DP_TARGET_POD_NAME POD_NAME CLUSTER_COMPONENT_NAME
    unset KB_CLUSTER_COMP_NAME CLUSTER_NAMESPACE KB_NAMESPACE POD_NAMESPACE
    unset KUBERNETES_CLUSTER_DOMAIN
  }
  BeforeEach 'setup_polling'

  is_canonical_process_id() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
  }

  cleanup_polling() {
    local child_pid=""
    local child_pgid=""
    local live_child_pgid=""
    if [ -s "$TERM_IGNORING_CHILD_PID_FILE" ]; then
      read -r child_pid child_pgid <"$TERM_IGNORING_CHILD_PID_FILE" || true
      if is_canonical_process_id "$child_pid" &&
        [ "$child_pid" != "$$" ] &&
        is_canonical_process_id "$child_pgid" &&
        is_canonical_process_id "$SHELLSPEC_RUNNER_PGID" &&
        [ "$child_pgid" != "$SHELLSPEC_RUNNER_PGID" ]; then
        live_child_pgid=$(ps -o pgid= -p "$child_pid" 2>/dev/null | tr -d " ")
        if [ "$live_child_pgid" = "$child_pgid" ]; then
          kill -KILL -- "-$child_pgid" 2>/dev/null ||
            kill -KILL "$child_pid" 2>/dev/null ||
            true
        fi
      fi
    fi
    rm -f "$POLL_STATE_FILE" "$TERM_IGNORING_CHILD_PID_FILE"
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
        backup-hang)
          command sleep 2
          echo '{"found":true,"status":"running"}'
          ;;
        backup-ignore-term)
          trap "" TERM
          "$BASH" -c 'trap "" TERM; pgid=$(ps -o pgid= -p "$$" | tr -d " "); echo "$$ $pgid" > "$1"; command sleep 8' \
            ignored-term-child "$TERM_IGNORING_CHILD_PID_FILE"
          echo '{"found":true,"status":"running"}'
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
      restore-hang)
        command sleep 2
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

  It "bounds a single backup status request by wall-clock time"
    POLL_MODE=backup-hang
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be failure
    The output should include "syncerctl status request timed out after 1 seconds"
    The contents of file "$POLL_STATE_FILE" should equal 1
  End

  wait_for_backup_and_report_forced_kill() {
    local started_at
    local finished_at
    local elapsed
    local child_pid
    local child_pgid
    local request_rc
    local recorded_identity_valid=false
    local dedicated_process_group=false
    local child_reaped=false
    local process_group_reaped=false
    local reap_checks=0

    started_at=$(date +%s)
    wait_for_syncer_backup_completion "backup-1"
    request_rc=$?
    finished_at=$(date +%s)
    elapsed=$((finished_at - started_at))
    read -r child_pid child_pgid <"$TERM_IGNORING_CHILD_PID_FILE"
    if is_canonical_process_id "$child_pid" &&
      [ "$child_pid" != "$$" ] &&
      is_canonical_process_id "$child_pgid"; then
      recorded_identity_valid=true
      if is_canonical_process_id "$SHELLSPEC_RUNNER_PGID" &&
        [ "$child_pgid" != "$SHELLSPEC_RUNNER_PGID" ]; then
        dedicated_process_group=true
      fi
    fi
    while [ "$reap_checks" -lt 20 ]; do
      if [ "$recorded_identity_valid" = "true" ] &&
        ! kill -0 "$child_pid" 2>/dev/null; then
        child_reaped=true
      fi
      if [ "$dedicated_process_group" = "true" ] &&
        ! kill -0 -- "-$child_pgid" 2>/dev/null; then
        process_group_reaped=true
      fi
      if [ "$child_reaped" = "true" ] && [ "$process_group_reaped" = "true" ]; then
        break
      fi
      command sleep 0.1
      reap_checks=$((reap_checks + 1))
    done
    echo "forced_kill_within_6_seconds=$([ "$elapsed" -lt 6 ] && echo true || echo false)"
    echo "recorded_process_identity_valid=$recorded_identity_valid"
    echo "dedicated_process_group=$dedicated_process_group"
    echo "term_ignoring_child_reaped=$child_reaped"
    echo "term_ignoring_process_group_reaped=$process_group_reaped"
    return "$request_rc"
  }

  It "kills and reaps a status child that ignores TERM"
    POLL_MODE=backup-ignore-term
    When call wait_for_backup_and_report_forced_kill
    The status should be failure
    The output should include "syncerctl status request timed out after 1 seconds"
    The output should include "forced_kill_within_6_seconds=true"
    The output should include "recorded_process_identity_valid=true"
    The output should include "dedicated_process_group=true"
    The output should include "term_ignoring_child_reaped=true"
    The output should include "term_ignoring_process_group_reaped=true"
    The contents of file "$POLL_STATE_FILE" should equal 1
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

  It "bounds each restore status request by wall-clock time"
    POLL_MODE=restore-hang
    When call wait_for_syncer_restore_completion "request-1"
    The status should be failure
    The output should include "syncerctl status request timed out after 1 seconds"
    The output should include "Failed to read restore request request-1 status"
    The contents of file "$POLL_STATE_FILE" should equal 1
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

  It "rejects an invalid request timeout before polling"
    SYNCER_STATUS_REQUEST_TIMEOUT_SECONDS=0
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be failure
    The output should include "SYNCER_STATUS_REQUEST_TIMEOUT_SECONDS must be an integer in range 1..300"
    The contents of file "$POLL_STATE_FILE" should equal 0
  End

  It "rejects an invalid restore request timeout before polling"
    SYNCER_STATUS_REQUEST_TIMEOUT_SECONDS=invalid
    When call wait_for_syncer_restore_completion "request-1"
    The status should be failure
    The output should include "SYNCER_STATUS_REQUEST_TIMEOUT_SECONDS must be an integer in range 1..300"
    The contents of file "$POLL_STATE_FILE" should equal 0
  End

  It "accepts the maximum request timeout"
    When call require_status_request_timeout 300
    The status should be success
    The output should equal ""
  End

  It "rejects a request timeout above the maximum"
    SYNCER_STATUS_REQUEST_TIMEOUT_SECONDS=301
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be failure
    The output should include "SYNCER_STATUS_REQUEST_TIMEOUT_SECONDS must be an integer in range 1..300"
    The contents of file "$POLL_STATE_FILE" should equal 0
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
