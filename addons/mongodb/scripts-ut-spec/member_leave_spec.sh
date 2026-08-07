# shellcheck shell=bash

Describe "MongoDB member leave script"
  setup() {
    CALL_LOG="$(mktemp)"
    export CALL_LOG
    export KB_LEAVE_MEMBER_POD_NAME="mongodb-1"
    export SYNCERCTL_BIN="syncerctl"
    export PBM_LEAVE_RESULT="success"

    timeout() {
      shift
      "$@"
    }

    syncerctl() {
      local port=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--port" ]; then
          port="$2"
          break
        fi
        shift
      done
      echo "$port" >> "$CALL_LOG"
      if [ "$port" = "3361" ] && [ "$PBM_LEAVE_RESULT" = "failure" ]; then
        echo "leave member failed: PBM backup task is active"
        return 1
      fi
      echo "leave member success"
    }
  }
  Before "setup"

  cleanup() {
    rm -f "$CALL_LOG"
    unset CALL_LOG KB_LEAVE_MEMBER_POD_NAME SYNCERCTL_BIN PBM_LEAVE_RESULT
    unset -f timeout syncerctl
  }
  After "cleanup"

  It "checks and stops the PBM agent before removing the MongoDB member"
    When run source ../scripts/mongodb-member-leave.sh

    The status should be success
    The contents of file "$CALL_LOG" should equal "3361
3601"
    The output should include "calling pbm-agent memberLeave"
    The output should include "calling mongodb memberLeave"
  End

  It "does not remove the MongoDB member when the PBM guard fails"
    PBM_LEAVE_RESULT="failure"

    When run source ../scripts/mongodb-member-leave.sh

    The status should be failure
    The contents of file "$CALL_LOG" should equal "3361"
    The output should include "PBM backup task is active"
    The stderr should include "pbm-agent memberLeave command failed"
  End
End
