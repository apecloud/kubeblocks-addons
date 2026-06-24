# shellcheck shell=sh

Describe "replication memberLeave lifecycle action"
  ADDON_ROOT="${SHELLSPEC_CWD:?}/addons/mariadb"
  CMPD_REPLICATION="${ADDON_ROOT}/templates/cmpd-replication.yaml"

  member_leave_block() {
    awk '
      /^[[:space:]]*memberLeave:[[:space:]]*$/ { in_block = 1 }
      in_block && /^[[:space:]]*switchover:[[:space:]]*$/ { exit }
      in_block { print }
    ' "${CMPD_REPLICATION}"
  }

  member_leave_block_contains() {
    member_leave_block | grep -F -- "$1" >/dev/null
  }

  member_leave_block_not_contains() {
    if member_leave_block | grep -F -- "$1" >/dev/null; then
      return 1
    fi
    return 0
  }

  It "declares a lifecycle timeout below kbagent's 60s action cap"
    When call member_leave_block_contains "timeoutSeconds: 50"
    The status should be success
  End

  It "wraps syncerctl leave in a command timeout below the lifecycle budget"
    When call member_leave_block_contains 'timeout 30 /tools/syncerctl leave --instance "$KB_LEAVE_MEMBER_POD_NAME"'
    The status should be success
  End

  It "does not retain an unbounded syncerctl leave command"
    When call member_leave_block_not_contains '- /tools/syncerctl leave --instance "$KB_LEAVE_MEMBER_POD_NAME"'
    The status should be success
  End
End
