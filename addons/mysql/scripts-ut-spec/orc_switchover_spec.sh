# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329

Describe "ORC switchover script tests"
  Include ../scripts/orc-switchover.sh

  Describe "MySQL read flag parsing"
    It "recognizes writable flags after mysql client stderr noise"
      output=$(printf '%s\n%s\n' \
        'mysql: [Warning] Using a password on the command line interface can be insecure.' \
        '0	0')

      When call is_writable_mysql "$output"
      The status should be success
    End

    It "recognizes read-only flags after mysql client stderr noise"
      output=$(printf '%s\n%s\n' \
        'mysql: [Warning] Using a password on the command line interface can be insecure.' \
        '1	1')

      When call is_readonly_mysql "$output"
      The status should be success
    End

    It "rejects output without a read_only/super_read_only row"
      output='mysql: [Warning] Using a password on the command line interface can be insecure.'

      When call is_writable_mysql "$output"
      The status should be failure
    End
  End

  Describe "Switchover closure verification"
    setup_switchover_verify() {
      export KB_SWITCHOVER_CURRENT_NAME="mysql-0"
      export KB_SWITCHOVER_CANDIDATE_NAME="mysql-1"
      export MYSQL_ORC_SWITCHOVER_VERIFY_ATTEMPTS=20
      export MYSQL_ORC_SWITCHOVER_VERIFY_INTERVAL_SECONDS=0
      export MYSQL_ORC_SWITCHOVER_PRECHECK_TIMEOUT_SECONDS=3
      export MYSQL_ORC_SWITCHOVER_CLIENT_TIMEOUT_SECONDS=40
      export MYSQL_ORC_SWITCHOVER_MYSQL_TIMEOUT_SECONDS=1
      export MYSQL_ORC_SWITCHOVER_MYSQL_CONNECT_TIMEOUT_SECONDS=1
      VERIFY_COUNTER_FILE=$(mktemp)
      export VERIFY_COUNTER_FILE
      printf '0\n' > "$VERIFY_COUNTER_FILE"
    }

    cleanup_switchover_verify() {
      rm -f "${VERIFY_COUNTER_FILE:-}"
      unset KB_SWITCHOVER_CURRENT_NAME
      unset KB_SWITCHOVER_CANDIDATE_NAME
      unset MYSQL_ORC_SWITCHOVER_VERIFY_ATTEMPTS
      unset MYSQL_ORC_SWITCHOVER_VERIFY_INTERVAL_SECONDS
      unset MYSQL_ORC_SWITCHOVER_PRECHECK_TIMEOUT_SECONDS
      unset MYSQL_ORC_SWITCHOVER_CLIENT_TIMEOUT_SECONDS
      unset MYSQL_ORC_SWITCHOVER_MYSQL_TIMEOUT_SECONDS
      unset MYSQL_ORC_SWITCHOVER_MYSQL_CONNECT_TIMEOUT_SECONDS
      unset VERIFY_COUNTER_FILE
      unset ORC_SWITCHOVER_CLIENT_PID
      unset ORC_SWITCHOVER_CLIENT_OUTPUT_FILE
      unset ORC_SWITCHOVER_CLIENT_RC_FILE
      unset ORC_SWITCHOVER_CLIENT_TEMP_DIR
      unset ORC_SWITCHOVER_CLIENT_RC
      unset ORC_SWITCHOVER_CLIENT_OUTPUT
    }

    Before 'setup_switchover_verify'
    After 'cleanup_switchover_verify'

    It "succeeds when readback converges inside the bounded verify window"
      mysql_read_flags() {
        local host="$1"
        local count
        if [ "$host" = "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
          count=$(cat "$VERIFY_COUNTER_FILE")
          count=$((count + 1))
          printf '%s\n' "$count" > "$VERIFY_COUNTER_FILE"
          if [ "$count" -lt 3 ]; then
            printf '1 1\n'
            return 0
          fi
          printf '0 0\n'
          return 0
        fi
        printf '1 1\n'
      }

      When call verify_switchover_closed_or_defer
      The status should be success
      The output should include "Switchover verified"
    End

    It "uses raw parallel readback output for closure checks"
      mysql_read_flags() {
        local host="$1"
        printf '%s\n' 'mysql: [Warning] Using a password on the command line interface can be insecure.'
        if [ "$host" = "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
          printf '0 0\n'
          return 0
        fi
        printf '1 1\n'
      }

      When call verify_switchover_closed_once
      The status should be success
    End

    It "classifies an unclosed readback window as retry-safe"
      mysql_read_flags() {
        local host="$1"
        if [ "$host" = "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
          printf '1 1\n'
          return 0
        fi
        printf '1 1\n'
      }

      When call verify_switchover_closed_or_defer
      The status should be failure
      The error should include "phase: post-switchover-not-converged"
      The error should include "next-retry-safe: yes"
      The error should include "verify-history:"
    End

    It "accepts a non-zero orchestrator client result when same invocation verifies closure"
      run_orchestrator_client_with_budget() {
        printf 'client timed out\n'
        return 124
      }

      mysql_read_flags() {
        local host="$1"
        if [ "$host" = "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
          printf '0 0\n'
          return 0
        fi
        printf '1 1\n'
      }

      When call run_switchover_client_and_verify 40 -c graceful-master-takeover-auto -i "$KB_SWITCHOVER_CURRENT_NAME" -d "$KB_SWITCHOVER_CANDIDATE_NAME"
      The status should be success
      The output should include "Switchover command returned non-zero (124) but post-check observed the target topology."
      The output should include "client timed out"
    End

    It "keeps unclosed readback retry-safe with orchestrator client diagnostics"
      run_orchestrator_client_with_budget() {
        printf 'client timed out\n'
        return 124
      }

      mysql_read_flags() {
        local host="$1"
        if [ "$host" = "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
          printf '1 1\n'
          return 0
        fi
        printf '1 1\n'
      }

      When call run_switchover_client_and_verify 40 -c graceful-master-takeover-auto -i "$KB_SWITCHOVER_CURRENT_NAME" -d "$KB_SWITCHOVER_CANDIDATE_NAME"
      The status should be failure
      The error should include "phase: post-switchover-not-converged"
      The error should include "orchestrator-client-rc: 124"
      The error should include "client timed out"
      The error should include "phase: orchestrator-command-failed"
    End

    It "fails explicitly when the orchestrator client background wrapper cannot start"
      start_orchestrator_client_background() {
        ORC_SWITCHOVER_CLIENT_RC=1
        ORC_SWITCHOVER_CLIENT_OUTPUT="failed to create orchestrator client temp directory"
        return 1
      }

      When call run_switchover_client_and_verify 40 -c graceful-master-takeover-auto -i "$KB_SWITCHOVER_CURRENT_NAME" -d "$KB_SWITCHOVER_CANDIDATE_NAME"
      The status should be failure
      The error should include "phase: orchestrator-client-start-failed"
      The error should include "failed to create orchestrator client temp directory"
    End

    It "does not reuse stale readback flags when its temp directory cannot be created"
      SWITCHOVER_VERIFY_CANDIDATE_RAW="0 0"
      SWITCHOVER_VERIFY_CURRENT_RAW="1 1"
      mktemp() {
        return 1
      }

      When call read_mysql_flags_pair "$KB_SWITCHOVER_CANDIDATE_NAME" "$KB_SWITCHOVER_CURRENT_NAME"
      The status should be failure
      The variable SWITCHOVER_VERIFY_CANDIDATE_RAW should equal ""
      The variable SWITCHOVER_VERIFY_CURRENT_RAW should equal ""
      The variable SWITCHOVER_VERIFY_CANDIDATE_FLAGS should include "failed to create readback temp directory"
    End
  End
End
