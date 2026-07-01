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

  It "fails closed when STOP SLAVE cleanup fails"
    When call grep -F "memberLeave: STOP SLAVE failed; refusing to report cleanup success" "${ADDON_ROOT}/scripts/replication-member-leave.sh"
    The status should be success
    The output should not include "not fatal"
  End

  It "fails closed when RESET SLAVE ALL cleanup fails"
    When call grep -F "memberLeave: RESET SLAVE ALL failed; refusing to report cleanup success" "${ADDON_ROOT}/scripts/replication-member-leave.sh"
    The status should be success
    The output should not include "not fatal"
  End

  It "uses internal admin credentials for cleanup when they are available"
    When call grep -F 'MEMBER_LEAVE_SQL_USER="${MYSQL_ADMIN_USER:-${MARIADB_ROOT_USER}}"' "${ADDON_ROOT}/scripts/replication-member-leave.sh"
    The status should be success
    The output should equal 'MEMBER_LEAVE_SQL_USER="${MYSQL_ADMIN_USER:-${MARIADB_ROOT_USER}}"'
  End

  It "injects MYSQL_ADMIN_USER into the kbagent memberLeave action env"
    When call member_leave_block_contains 'name: MYSQL_ADMIN_USER'
    The status should be success
  End

  It "sets memberLeave MYSQL_ADMIN_USER to kb_internal_root"
    When call member_leave_block_contains 'value: "kb_internal_root"'
    The status should be success
  End

  It "injects MYSQL_ADMIN_PASSWORD into the kbagent memberLeave action env"
    When call member_leave_block_contains 'name: MYSQL_ADMIN_PASSWORD'
    The status should be success
  End

  It "sets memberLeave MYSQL_ADMIN_PASSWORD from the root password secret"
    When call member_leave_block_contains 'value: "$(MARIADB_ROOT_PASSWORD)"'
    The status should be success
  End

  It "passes the selected memberLeave cleanup credential to the local SQL client"
    When call grep -F '"-u${MEMBER_LEAVE_SQL_USER}" "-p${MEMBER_LEAVE_SQL_PASSWORD}"' "${ADDON_ROOT}/scripts/replication-member-leave.sh"
    The status should be success
    The output should include '"-u${MEMBER_LEAVE_SQL_USER}" "-p${MEMBER_LEAVE_SQL_PASSWORD}"'
  End

  It "does not silently ignore STOP SLAVE or RESET SLAVE ALL with || true"
    When call grep -E 'STOP SLAVE|RESET SLAVE ALL' "${ADDON_ROOT}/scripts/replication-member-leave.sh"
    The output should not include "|| true"
  End

  It "returns the cleanup failure rc after attempting both statements"
    When call grep -F 'exit "${cleanup_rc}"' "${ADDON_ROOT}/scripts/replication-member-leave.sh"
    The status should be success
    The output should equal '  exit "${cleanup_rc}"'
  End
End
