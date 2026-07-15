# shellcheck shell=bash

Describe "replication full-primary acceptance user fence"
  entrypoint_file() {
    printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "${SHELLSPEC_CWD:?}"
  }

  extract_function() {
    function_name="$1"
    awk -v function_name="${function_name}" '
      $0 ~ "^[[:space:]]*" function_name "\\(\\)[[:space:]]*\\{" { inside = 1 }
      inside {
        print
        line = $0
        opens = gsub(/\{/, "", line)
        closes = gsub(/\}/, "", line)
        depth += opens - closes
        if (depth == 0) exit
      }
      END { if (!inside) exit 1 }
    ' "$(entrypoint_file)"
  }

  run_accept_case() {
    mode="$1"
    work_dir="$(mktemp -d)"
    harness="${work_dir}/harness.sh"
    trace="${work_dir}/trace"
    data_dir="${work_dir}/data"
    mkdir -p "${data_dir}"

    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -u'
      extract_function user_facing_root_read_only_bypass_is_absent
      extract_function read_only_internal_admin_gate_is_active
      extract_function set_internal_admin_gate_read_only
      extract_function primary_write_gates_ready
      extract_function read_only_is_strongest_fail_closed
      extract_function rollback_fenced_primary_accept
      extract_function rollback_locked_primary_accept
      extract_function set_primary_read_write
      cat <<'HARNESS'
if [ "${MODE}" = "entry-not-fenced" ]; then
  GLOBAL_READ_ONLY=0
  READ_ONLY_MODE=OFF
else
  GLOBAL_READ_ONLY=1
  READ_ONLY_MODE=NO_LOCK_NO_ADMIN
fi
LOCAL_ROOT_LOCKED=1
REMOTE_ROOT_LOCKED=1
REQUIRED_GATES_PASSED=0
POST_COMMIT_RETURNED=0
DEMOTED_AFTER_COMMIT=0

trace_event() {
  printf '%s\n' "$1" >> "${TRACE_FILE}"
}
ordinary_business_can_write() {
  [ "${GLOBAL_READ_ONLY}" -eq 0 ]
}
local_root_can_write() {
  [ "${GLOBAL_READ_ONLY}" -eq 0 ] && [ "${LOCAL_ROOT_LOCKED}" -eq 0 ]
}
remote_root_can_write() {
  [ "${GLOBAL_READ_ONLY}" -eq 0 ] && [ "${REMOTE_ROOT_LOCKED}" -eq 0 ]
}
assert_all_user_writers_rejected() {
  ! ordinary_business_can_write && ! local_root_can_write && ! remote_root_can_write
}
sample_pre_gate_user_inserts() {
  if ordinary_business_can_write; then
    trace_event ordinary-business-insert-committed-before-required-gates
  else
    trace_event ordinary-business-insert-rejected-before-required-gates
  fi
  if local_root_can_write; then
    trace_event local-root-insert-committed-before-required-gates
  else
    trace_event local-root-insert-rejected-before-required-gates
  fi
  if remote_root_can_write; then
    trace_event remote-root-insert-committed-before-required-gates
  else
    trace_event remote-root-insert-rejected-before-required-gates
  fi
}
read_only_is_fail_closed() {
  [ "${GLOBAL_READ_ONLY}" -eq 1 ]
}
read_only_value() {
  printf '%s\n' "${READ_ONLY_MODE}"
}
sql_quote() {
  printf '%s\n' "$1"
}
primary_internal_root_write_ready() {
  trace_event required-gate-begin
  sample_pre_gate_user_inserts
  if ! assert_all_user_writers_rejected; then
    trace_event user-write-open-before-required-gates
    return 1
  fi
  if [ "${MODE}" = "gate-failure" ]; then
    trace_event required-gate-failed
    return 1
  fi
  if [ "${MODE}" = "gate-prestop" ]; then
    command touch "${DATA_DIR}/.prestop-fence-started"
    trace_event prestop-started-inside-required-gate
  fi
  REQUIRED_GATES_PASSED=1
  trace_event required-gate-pass
}
query_local_syncer_role() {
  if [ "${MODE}" = "role-drift" ] || [ "${MODE}" = "role-drift-rollback-failure" ] || [ "${MODE}" = "role-drift-strongest-failure" ]; then
    printf '%s\n' secondary
  else
    printf '%s\n' primary
  fi
}
try_acquire_primary_write_commit_lock() {
  trace_event commit-lock-acquired
  return 0
}
release_primary_write_commit_lock() {
  inject_demote_after_commit_return
  trace_event commit-lock-released
  return 0
}
inject_demote_after_commit_return() {
  if [ "${MODE}" = "post-commit-demote" ] && [ "${POST_COMMIT_RETURNED}" -eq 1 ] && [ "${DEMOTED_AFTER_COMMIT}" -eq 0 ]; then
    GLOBAL_READ_ONLY=1
    READ_ONLY_MODE=ON
    command rm -f "${DATA_DIR}/.primary-read-write-ready" "${DATA_DIR}/.replication-ready"
    DEMOTED_AFTER_COMMIT=1
    trace_event run-cycle-demote-after-authority-commit
  fi
}
authoritative_primary_write_commit() {
  trace_event syncer-authority-commit-begin
  if [ "${MODE}" = "authority-lost" ] || [ "${MODE}" = "role-drift" ] || \
     [ "${MODE}" = "role-drift-rollback-failure" ] || [ "${MODE}" = "role-drift-strongest-failure" ]; then
    trace_event syncer-authority-commit-rejected
    return 1
  fi
  if [ "${MODE}" = "open-failure" ]; then
    trace_event global-read-only-open-failed
    return 1
  fi
  if [ "${LOCAL_ROOT_LOCKED}" -ne 0 ] || [ "${REMOTE_ROOT_LOCKED}" -ne 0 ]; then
    trace_event syncer-commit-before-root-unlocks
    return 1
  fi
  GLOBAL_READ_ONLY=0
  READ_ONLY_MODE=OFF
  trace_event global-read-only-off
  if [ "${MODE}" = "ready-publish-failure" ]; then
    trace_event ready-publish-failed-after-global-open
    return 1
  fi
  command touch "${DATA_DIR}/.primary-read-write-ready" "${DATA_DIR}/.replication-ready"
  trace_event ready-published
  trace_event replication-ready-published
  trace_event syncer-authority-commit-pass
  POST_COMMIT_RETURNED=1
}
local_sql() {
  case "$*" in
    *"SHOW GRANTS FOR"*)
      case "${MODE}" in
        bypass-failure) printf '%s\n' 'GRANT READ_ONLY ADMIN ON *.* TO root' ;;
        bypass-super) printf '%s\n' 'GRANT SUPER ON *.* TO root' ;;
        bypass-all) printf '%s\n' 'GRANT ALL PRIVILEGES ON *.* TO root' ;;
        *) printf '%s\n' 'GRANT SELECT ON *.* TO root' ;;
      esac
      ;;
    *"SET GLOBAL read_only = ON;"*|*"SET GLOBAL read_only = 1;"*)
      if [ "${MODE}" = "gate-mode-failure" ]; then
        trace_event internal-admin-gate-read-only-failed
        return 1
      fi
      GLOBAL_READ_ONLY=1
      READ_ONLY_MODE=ON
      trace_event internal-admin-gate-read-only-on
      ;;
    *"SET GLOBAL read_only = 0;"*|*"SET GLOBAL read_only = 'OFF';"*)
      if [ "${MODE}" = "open-failure" ]; then
        trace_event global-read-only-open-failed
        return 1
      fi
      [ "${REQUIRED_GATES_PASSED}" -eq 1 ] || trace_event global-open-before-required-gates
      GLOBAL_READ_ONLY=0
      trace_event global-read-only-off
      ;;
  esac
}
unlock_local_root_writes() {
  inject_demote_after_commit_return
  [ "${DEMOTED_AFTER_COMMIT}" -eq 0 ] || trace_event visible-transition-after-demote
  [ "${REQUIRED_GATES_PASSED}" -eq 1 ] || trace_event local-root-open-before-required-gates
  if [ "${MODE}" = "local-unlock-failure" ]; then
    trace_event local-root-unlock-failed
    return 1
  fi
  LOCAL_ROOT_LOCKED=0
  trace_event local-root-unlocked
}
unlock_remote_root_writes() {
  inject_demote_after_commit_return
  [ "${DEMOTED_AFTER_COMMIT}" -eq 0 ] || trace_event visible-transition-after-demote
  [ "${REQUIRED_GATES_PASSED}" -eq 1 ] || trace_event remote-root-open-before-required-gates
  if [ "${MODE}" = "remote-unlock-failure" ] || [ "${MODE}" = "rollback-failure" ]; then
    trace_event remote-root-unlock-failed
    return 1
  fi
  REMOTE_ROOT_LOCKED=0
  trace_event remote-root-unlocked
}
lock_local_root_writes() {
  LOCAL_ROOT_LOCKED=1
  trace_event local-root-locked
}
lock_remote_root_writes() {
  if [ "${MODE}" = "rollback-failure" ] || [ "${MODE}" = "role-drift-rollback-failure" ]; then
    trace_event remote-root-relock-failed
    return 1
  fi
  REMOTE_ROOT_LOCKED=1
  trace_event remote-root-locked
}
set_fail_closed_read_only() {
  GLOBAL_READ_ONLY=1
  if [ "${MODE}" = "role-drift-strongest-failure" ]; then
    READ_ONLY_MODE=ON
    trace_event global-read-only-fallback-on
  else
    READ_ONLY_MODE=NO_LOCK_NO_ADMIN
    trace_event global-read-only-strongest
  fi
}
mark_replication_pending() {
  rm -f "${DATA_DIR}/.primary-read-write-ready"
  trace_event replication-pending
}
mark_replication_ready() { trace_event unexpected-addon-ready-publication; return 1; }
prestop_watchdog_log() {
  trace_event "log:$*"
}

INTERNAL_LOCAL=(local_sql)
MARIADB_ROOT_USER=root
MARIADB_ROOT_HOST=%
[ "${MODE}" = "prestop" ] && command touch "${DATA_DIR}/.prestop-fence-started"
set_primary_read_write "test-${MODE}" "require-dcs-primary"
accept_rc=$?
[ -f "${DATA_DIR}/.primary-read-write-ready" ] && trace_event ready-observed-after-return
if ordinary_business_can_write; then trace_event ordinary-business-writable; else trace_event ordinary-business-rejected; fi
if local_root_can_write; then trace_event local-root-writable; else trace_event local-root-rejected; fi
if remote_root_can_write; then trace_event remote-root-writable; else trace_event remote-root-rejected; fi
cat "${TRACE_FILE}"

case "${MODE}" in
  success)
    [ "${accept_rc}" -eq 0 ]
    gate_line="$(grep -n '^required-gate-pass$' "${TRACE_FILE}" | cut -d: -f1)"
    global_line="$(grep -n '^global-read-only-off$' "${TRACE_FILE}" | cut -d: -f1)"
    local_line="$(grep -n '^local-root-unlocked$' "${TRACE_FILE}" | cut -d: -f1)"
    remote_line="$(grep -n '^remote-root-unlocked$' "${TRACE_FILE}" | cut -d: -f1)"
    ready_line="$(grep -n '^ready-published$' "${TRACE_FILE}" | cut -d: -f1)"
    [ "${gate_line}" -lt "${local_line}" ]
    [ "${gate_line}" -lt "${remote_line}" ]
    [ "${local_line}" -lt "${global_line}" ]
    [ "${remote_line}" -lt "${global_line}" ]
    [ "${global_line}" -lt "${ready_line}" ]
    [ "${local_line}" -lt "${ready_line}" ]
    [ "${remote_line}" -lt "${ready_line}" ]
    replication_ready_line="$(grep -n '^replication-ready-published$' "${TRACE_FILE}" | cut -d: -f1)"
    commit_lock_line="$(grep -n '^commit-lock-acquired$' "${TRACE_FILE}" | cut -d: -f1)"
    syncer_commit_line="$(grep -n '^syncer-authority-commit-pass$' "${TRACE_FILE}" | cut -d: -f1)"
    commit_unlock_line="$(grep -n '^commit-lock-released$' "${TRACE_FILE}" | cut -d: -f1)"
    [ "${commit_lock_line}" -lt "${local_line}" ]
    [ "${remote_line}" -lt "${syncer_commit_line}" ]
    [ "${remote_line}" -lt "${commit_unlock_line}" ]
    [ "${ready_line}" -lt "${commit_unlock_line}" ]
    [ "${remote_line}" -lt "${replication_ready_line}" ]
    [ "${replication_ready_line}" -lt "${commit_unlock_line}" ]
    grep -q '^ready-observed-after-return$' "${TRACE_FILE}"
    ! grep -q '^unexpected-addon-ready-publication$' "${TRACE_FILE}"
    ! grep -q 'open-before-required-gates' "${TRACE_FILE}"
    grep -q '^ordinary-business-writable$' "${TRACE_FILE}"
    grep -q '^local-root-writable$' "${TRACE_FILE}"
    grep -q '^remote-root-writable$' "${TRACE_FILE}"
    ;;
  prestop|gate-prestop|entry-not-fenced|bypass-failure|bypass-super|bypass-all|gate-mode-failure|gate-failure|authority-lost|open-failure|local-unlock-failure|remote-unlock-failure|ready-publish-failure|role-drift)
    [ "${accept_rc}" -eq 2 ]
    grep -q '^ordinary-business-rejected$' "${TRACE_FILE}"
    grep -q '^local-root-rejected$' "${TRACE_FILE}"
    grep -q '^remote-root-rejected$' "${TRACE_FILE}"
    [ "${READ_ONLY_MODE}" = "NO_LOCK_NO_ADMIN" ]
    [ "${LOCAL_ROOT_LOCKED}" -eq 1 ]
    [ "${REMOTE_ROOT_LOCKED}" -eq 1 ]
    ! grep -q '^ready-published$' "${TRACE_FILE}"
    ;;
  rollback-failure|role-drift-rollback-failure|role-drift-strongest-failure)
    [ "${accept_rc}" -eq 3 ]
    grep -q 'fail_closed=false' "${TRACE_FILE}"
    ! grep -q '^ready-published$' "${TRACE_FILE}"
    ;;
  post-commit-demote)
    [ "${accept_rc}" -eq 0 ]
    [ "${READ_ONLY_MODE}" = "ON" ]
    grep -q '^run-cycle-demote-after-authority-commit$' "${TRACE_FILE}"
    grep -q '^ordinary-business-rejected$' "${TRACE_FILE}"
    grep -q '^local-root-rejected$' "${TRACE_FILE}"
    grep -q '^remote-root-rejected$' "${TRACE_FILE}"
    [ ! -f "${DATA_DIR}/.primary-read-write-ready" ]
    [ ! -f "${DATA_DIR}/.replication-ready" ]
    ! grep -q '^visible-transition-after-demote$' "${TRACE_FILE}"
    ! grep -q '^unexpected-addon-ready-publication$' "${TRACE_FILE}"
    ;;
esac
HARNESS
    } > "${harness}"

    TRACE_FILE="${trace}" DATA_DIR="${data_dir}" MODE="${mode}" bash "${harness}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  It "keeps ordinary, local-root, and remote-root writers fenced until all required gates pass"
    When call run_accept_case success
    The status should be success
    The output should include "required-gate-pass"
    The output should include "ready-published"
    The output should not include "open-before-required-gates"
  End

  It "has no addon-visible transition after the authority commit returns"
    When call run_accept_case post-commit-demote
    The status should be success
    The output should include "run-cycle-demote-after-authority-commit"
    The output should not include "visible-transition-after-demote"
  End

  It "keeps every user writer fenced when an internal required gate fails"
    When call run_accept_case gate-failure
    The status should be success
    The output should include "required-gate-failed"
    The output should not include "global-read-only-off"
  End

  It "refuses the internal-admin gate when a user-facing root has read-only bypass"
    When call run_accept_case bypass-failure
    The status should be success
    The output should include "reason=admin-bypass-present"
    The output should not include "global-read-only-off"
    The output should not include "ready-published"
  End

  It "refuses the internal-admin gate when a user-facing root retains SUPER"
    When call run_accept_case bypass-super
    The status should be success
    The output should include "reason=admin-bypass-present"
    The output should not include "global-read-only-off"
  End

  It "refuses the internal-admin gate when a user-facing root retains ALL PRIVILEGES"
    When call run_accept_case bypass-all
    The status should be success
    The output should include "reason=admin-bypass-present"
    The output should not include "global-read-only-off"
  End

  It "fails closed when the server cannot enter internal-admin-only gate mode"
    When call run_accept_case gate-mode-failure
    The status should be success
    The output should include "internal-admin-gate-read-only-failed"
    The output should include "global-read-only-strongest"
    The output should not include "ready-published"
  End

  It "repairs and rejects an entry state that is not fail-closed before running a gate"
    When call run_accept_case entry-not-fenced
    The status should be success
    The output should include "global-read-only-strongest"
    The output should not include "required-gate-begin"
    The output should not include "ready-published"
  End

  It "keeps every user writer fenced when preStop interrupts acceptance"
    When call run_accept_case prestop
    The status should be success
    The output should include "global-read-only-strongest"
    The output should not include "required-gate-begin"
    The output should not include "ready-published"
  End

  It "freshly rechecks preStop after the internal gate and rolls back the narrowed fence"
    When call run_accept_case gate-prestop
    The status should be success
    The output should include "prestop-started-inside-required-gate"
    The output should include "global-read-only-strongest"
    The output should include "local-root-locked"
    The output should include "remote-root-locked"
    The output should not include "global-read-only-off"
    The output should not include "ready-published"
  End

  It "rolls the narrowed fence back to strongest when DCS leadership drifts after the internal gate"
    When call run_accept_case role-drift
    The status should be success
    The output should include "global-read-only-strongest"
    The output should include "local-root-locked"
    The output should include "remote-root-locked"
    The output should include "ordinary-business-rejected"
    The output should not include "global-read-only-off"
  End

  It "surfaces rollback failure after post-gate DCS drift as rc3"
    When call run_accept_case role-drift-rollback-failure
    The status should be success
    The output should include "remote-root-relock-failed"
    The output should include "fail_closed=false"
    The output should not include "global-read-only-off"
    The output should not include "ready-published"
  End

  It "surfaces failure to restore NO_LOCK_NO_ADMIN after DCS drift as rc3"
    When call run_accept_case role-drift-strongest-failure
    The status should be success
    The output should include "global-read-only-fallback-on"
    The output should include "fail_closed=false"
    The output should not include "global-read-only-off"
    The output should not include "ready-published"
  End

  It "rolls all user writers back when remote-root unlock fails before the authority commit"
    When call run_accept_case remote-unlock-failure
    The status should be success
    The output should include "global-read-only-strongest"
    The output should include "ordinary-business-rejected"
    The output should include "local-root-rejected"
    The output should include "remote-root-rejected"
  End

  It "rolls all user writers back when global read-only cannot be opened"
    When call run_accept_case open-failure
    The status should be success
    The output should include "global-read-only-open-failed"
    The output should include "global-read-only-strongest"
    The output should not include "ready-published"
  End

  It "uses the syncer lease-CAS commit and rolls back when authority is lost"
    When call run_accept_case authority-lost
    The status should be success
    The output should include "syncer-authority-commit-rejected"
    The output should include "global-read-only-strongest"
    The output should not include "ready-published"
  End

  It "rolls all user writers back when local-root unlock fails before the authority commit"
    When call run_accept_case local-unlock-failure
    The status should be success
    The output should include "local-root-unlock-failed"
    The output should include "global-read-only-strongest"
    The output should not include "ready-published"
  End

  It "rolls all user writers back when ready publication fails"
    When call run_accept_case ready-publish-failure
    The status should be success
    The output should include "ready-publish-failed-after-global-open"
    The output should include "global-read-only-strongest"
    The output should not include "ready-published"
  End

  It "surfaces rollback failure instead of publishing a false fail-closed state"
    When call run_accept_case rollback-failure
    The status should be success
    The output should include "remote-root-relock-failed"
    The output should include "fail_closed=false"
    The output should not include "ready-published"
  End
End
