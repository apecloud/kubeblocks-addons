# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329

Describe "ORC memberLeave script tests"
  Include ../scripts/orc-member-leave.sh

  setup_member_leave() {
    export KB_LEAVE_MEMBER_POD_NAME="mysql-2"
    export MYSQL_ORC_MEMBER_LEAVE_CLIENT_TIMEOUT_SECONDS=10
    export MYSQL_ORC_MEMBER_LEAVE_SETTLE_SECONDS=0
  }

  cleanup_member_leave() {
    unset KB_LEAVE_MEMBER_POD_NAME
    unset KB_AGENT_POD_NAME
    unset MYSQL_ORC_MEMBER_LEAVE_CLIENT_TIMEOUT_SECONDS
    unset MYSQL_ORC_MEMBER_LEAVE_SETTLE_SECONDS
  }

  Before 'setup_member_leave'
  After 'cleanup_member_leave'

  It "closes only after all bounded calls prove the instance is absent"
    run_orchestrator_client_with_budget() {
      case "$3" in
        forget|clusters) return 0 ;;
        all-instances) printf '%s\n' 'mysql-0:3306' 'mysql-1:3306' ; return 0 ;;
      esac
      return 1
    }

    When call run_member_leave
    The status should be success
    The output should include "successfully removed"
  End

  It "fails when the bounded forget call times out"
    run_orchestrator_client_with_budget() {
      [ "$3" = "forget" ] && return 124
      return 0
    }

    When call run_member_leave
    The status should be failure
    The error should include "phase: forget-command-failed"
    The error should include "rc: 124"
  End

  It "fails when the bounded reachability call times out"
    run_orchestrator_client_with_budget() {
      case "$3" in
        forget) return 0 ;;
        clusters) return 124 ;;
      esac
      return 0
    }

    When call run_member_leave
    The status should be failure
    The output should include "Forget command executed"
    The error should include "phase: orchestrator-unreachable"
    The error should include "rc: 124"
  End

  It "fails when the bounded instance verification call times out"
    run_orchestrator_client_with_budget() {
      case "$3" in
        forget|clusters) return 0 ;;
        all-instances) return 124 ;;
      esac
      return 1
    }

    When call run_member_leave
    The status should be failure
    The output should include "Forget command executed"
    The error should include "phase: instance-verification-failed"
    The error should include "rc: 124"
  End

  It "fails while the instance remains present"
    run_orchestrator_client_with_budget() {
      case "$3" in
        forget|clusters) return 0 ;;
        all-instances) printf '%s\n' 'mysql-0:3306' 'mysql-2:3306' ; return 0 ;;
      esac
      return 1
    }

    When call run_member_leave
    The status should be failure
    The output should include "Forget command executed"
    The error should include "phase: instance-still-present"
    The error should include "next-retry-safe: yes"
  End

  It "rejects a missing leaving-member identity"
    unset KB_LEAVE_MEMBER_POD_NAME
    unset KB_AGENT_POD_NAME

    When call run_member_leave
    The status should be failure
    The error should include "phase: leaving-member-missing"
    The error should include "next-retry-safe: no"
  End
End
