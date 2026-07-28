# shellcheck shell=bash

Describe "mongodb-member-leave.sh role safety"

  script_path() {
    printf "%s/addons/mongodb/scripts/mongodb-member-leave.sh" "${SHELLSPEC_CWD:?}"
  }

  run_member_leave() (
    timeout() {
      printf '%s' "${ROLE_STDOUT-}"
      return "${ROLE_RC:-0}"
    }

    function /tools/syncerctl {
      printf 'SYNCER_CALL:%s\n' "$*"
      return "${LEAVE_RC:-0}"
    }

    export KB_LEAVE_MEMBER_POD_NAME="mongodb-1"
    # shellcheck disable=SC1090
    . "$(script_path)"
  )

  BeforeEach 'ROLE_STDOUT=""; ROLE_RC=0; LEAVE_RC=0'

  It "rejects leaving the current primary"
    ROLE_STDOUT="primary"
    When call run_member_leave
    The status should equal 1
    The output should include "current member role is primary."
    The output should not include "SYNCER_CALL:leave"
  End

  It "leaves an observed non-primary member"
    ROLE_STDOUT="secondary"
    When call run_member_leave
    The status should be success
    The output should include "SYNCER_CALL:leave --instance mongodb-1"
  End

  It "fails closed when the role probe times out"
    ROLE_RC=124
    When call run_member_leave
    The status should equal 124
    The error should include "failed to determine current member role"
    The output should not include "SYNCER_CALL:leave"
  End

  It "fails closed even if a failed role probe emitted stale output"
    ROLE_STDOUT="secondary"
    ROLE_RC=7
    When call run_member_leave
    The status should equal 7
    The error should include "failed to determine current member role"
    The output should not include "SYNCER_CALL:leave"
  End

End
