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

  It "invokes the external member-leave script"
    When call member_leave_block_contains '/scripts/replication-member-leave.sh'
    The status should be success
  End
End
