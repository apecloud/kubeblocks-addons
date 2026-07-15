# shellcheck shell=bash

Describe "replication runtime role promotion race"
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

  run_secondary_fence_promotion_race() {
    work_dir="$(mktemp -d)"
    harness="${work_dir}/race-harness.sh"
    trace="${work_dir}/trace"
    role_counter="${work_dir}/role-counter"
    data_dir="${work_dir}/data"
    mkdir -p "${data_dir}"
    printf '0\n' > "${role_counter}"

    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -u'
      extract_function set_replica_read_only
      extract_function replica_lock_abort_if_syncer_primary
      extract_function accept_syncer_primary_promotion_from_replica_path
      extract_function reconcile_sql_listener_for_syncer_secondary_once
      cat <<'HARNESS'
trace_event() {
  printf '%s\n' "$1" >> "${TRACE_FILE}"
}
query_local_syncer_role() {
  local call
  call=$(( $(cat "${ROLE_COUNTER}") + 1 ))
  printf '%s\n' "${call}" > "${ROLE_COUNTER}"
  if [ "${call}" -le 3 ]; then
    printf '%s\n' secondary
  else
    printf '%s\n' primary
  fi
}
lock_remote_root_writes() {
  trace_event remote-root-fenced
}
set_fail_closed_read_only() {
  trace_event read-only-on
}
lock_local_root_writes() {
  trace_event local-root-fenced
}
ensure_semisync_replica_role() {
  trace_event semisync-secondary
}
internal_sql() {
  case "$*" in
    *"SET GLOBAL read_only = 0;"*) trace_event primary-internal-writable ;;
  esac
}
prestop_watchdog_log() {
  :
}
expose_sql_listener_for_primary_role() {
  trace_event full-primary-accept
}
mark_replication_ready() {
  trace_event primary-ready
}
mark_replication_pending() {
  trace_event replication-pending
}
query_slave_status_verbose() {
  return 1
}
slave_status_is_healthy() {
  return 1
}
publish_replica_after_rejoin_ready() {
  return 1
}
configure_replication_from_primary_service_once() {
  return 1
}

INTERNAL_LOCAL=(internal_sql)
reconcile_sql_listener_for_syncer_secondary_once

cat "${TRACE_FILE}"
read_only_line="$(grep -n '^read-only-on$' "${TRACE_FILE}" | cut -d: -f1)"
internal_open_line="$(grep -n '^primary-internal-writable$' "${TRACE_FILE}" | cut -d: -f1)"
full_accept_line="$(grep -n '^full-primary-accept$' "${TRACE_FILE}" | cut -d: -f1)"
[ -n "${read_only_line}" ]
[ -n "${full_accept_line}" ]
[ -z "${internal_open_line}" ]
[ "${read_only_line}" -lt "${full_accept_line}" ]
HARNESS
    } > "${harness}"

    TRACE_FILE="${trace}" ROLE_COUNTER="${role_counter}" DATA_DIR="${data_dir}" \
      bash "${harness}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  run_business_writer_during_primary_accept() {
    work_dir="$(mktemp -d)"
    harness="${work_dir}/business-writer-harness.sh"
    trace="${work_dir}/trace"

    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -u'
      extract_function accept_syncer_primary_promotion_from_replica_path
      cat <<'HARNESS'
GLOBAL_READ_ONLY=1
trace_event() {
  printf '%s\n' "$1" >> "${TRACE_FILE}"
}
query_local_syncer_role() {
  printf '%s\n' primary
}
internal_sql() {
  case "$*" in
    *"SET GLOBAL read_only = 0;"*) GLOBAL_READ_ONLY=0 ;;
    *"SET GLOBAL read_only = ON;"*) GLOBAL_READ_ONLY=1 ;;
  esac
}
prestop_watchdog_log() {
  trace_event "log:$*"
}
expose_sql_listener_for_primary_role() {
  if [ "${GLOBAL_READ_ONLY}" -eq 0 ]; then
    trace_event business-write-committed
  else
    trace_event business-write-rejected
  fi
}
mark_replication_ready() {
  trace_event primary-ready
}
set_fail_closed_read_only() {
  if [ "${MODE:-}" = "rollback-failure" ]; then
    trace_event read-only-fail-closed-failed
    return 1
  fi
  GLOBAL_READ_ONLY=1
  trace_event read-only-fail-closed
}

INTERNAL_LOCAL=(internal_sql)
accept_syncer_primary_promotion_from_replica_path business-writer-window
cat "${TRACE_FILE}"
grep -q '^business-write-rejected$' "${TRACE_FILE}"
! grep -q '^business-write-committed$' "${TRACE_FILE}"
HARNESS
    } > "${harness}"

    TRACE_FILE="${trace}" bash "${harness}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  run_primary_accept_safety_case() {
    mode="$1"
    work_dir="$(mktemp -d)"
    harness="${work_dir}/accept-harness.sh"
    trace="${work_dir}/trace"
    role_counter="${work_dir}/role-counter"
    printf '0\n' > "${role_counter}"

    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -u'
      extract_function accept_syncer_primary_promotion_from_replica_path
      cat <<'HARNESS'
trace_event() {
  printf '%s\n' "$1" >> "${TRACE_FILE}"
}
query_local_syncer_role() {
  local call
  call=$(( $(cat "${ROLE_COUNTER}") + 1 ))
  printf '%s\n' "${call}" > "${ROLE_COUNTER}"
  if [ "${MODE}" = "role-change" ] && [ "${call}" -gt 1 ]; then
    printf '%s\n' secondary
  else
    printf '%s\n' primary
  fi
}
internal_sql() {
  case "$*" in
    *"SET GLOBAL read_only = 0;"*) trace_event primary-internal-writable ;;
    *"SET GLOBAL read_only = ON;"*) trace_event read-only-rollback ;;
  esac
}
prestop_watchdog_log() {
  trace_event "log:$*"
}
expose_sql_listener_for_primary_role() {
  trace_event full-primary-accept
  [ "${MODE}" != "accept-failure" ] && [ "${MODE}" != "rollback-failure" ]
}
mark_replication_ready() {
  trace_event primary-ready
}

INTERNAL_LOCAL=(internal_sql)
set_fail_closed_read_only() {
  if [ "${MODE}" = "rollback-failure" ]; then
    trace_event read-only-rollback-failed
    return 1
  fi
  trace_event read-only-rollback
}
accept_syncer_primary_promotion_from_replica_path safety-case
accept_rc=$?
cat "${TRACE_FILE}"

case "${MODE}" in
  role-change)
    [ "${accept_rc}" -eq 1 ]
    ! grep -q '^primary-internal-writable$' "${TRACE_FILE}"
    grep -q 'reason=dcs-primary-changed global-read-only=held' "${TRACE_FILE}"
    ! grep -q '^full-primary-accept$' "${TRACE_FILE}"
    ;;
  accept-failure)
    [ "${accept_rc}" -eq 2 ]
    accept_line="$(grep -n '^full-primary-accept$' "${TRACE_FILE}" | cut -d: -f1)"
    rollback_line="$(grep -n '^read-only-rollback$' "${TRACE_FILE}" | cut -d: -f1)"
    ! grep -q '^primary-internal-writable$' "${TRACE_FILE}"
    [ "${accept_line}" -lt "${rollback_line}" ]
    ;;
  rollback-failure)
    [ "${accept_rc}" -eq 3 ]
    grep -q '^full-primary-accept$' "${TRACE_FILE}"
    grep -q '^read-only-rollback-failed$' "${TRACE_FILE}"
    grep -q 'fail_closed=false' "${TRACE_FILE}"
    ;;
esac
HARNESS
    } > "${harness}"

    TRACE_FILE="${trace}" ROLE_COUNTER="${role_counter}" MODE="${mode}" \
      bash "${harness}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  It "keeps the global read-only fence before full-primary acceptance after promotion interrupts a secondary fence"
    When call run_secondary_fence_promotion_race
    The status should be success
    The output should include "read-only-on"
    The output should not include "primary-internal-writable"
    The output should include "full-primary-accept"
  End

  It "keeps an ordinary business writer fenced before full-primary acceptance"
    When call run_business_writer_during_primary_accept
    The status should be success
    The output should include "business-write-rejected"
    The output should not include "business-write-committed"
  End

  It "preserves fail-closed read-only and skips full acceptance when the DCS primary changes"
    When call run_primary_accept_safety_case role-change
    The status should be success
    The output should include "global-read-only=held"
    The output should not include "primary-internal-writable"
    The output should not include "full-primary-accept"
  End

  It "restores fail-closed read-only when the full-primary acceptance fails"
    When call run_primary_accept_safety_case accept-failure
    The status should be success
    The output should include "full-primary-accept"
    The output should include "read-only-rollback"
    The output should not include "primary-internal-writable"
  End

  It "reports a rollback failure instead of claiming fail-closed success"
    When call run_primary_accept_safety_case rollback-failure
    The status should be success
    The output should include "read-only-rollback-failed"
    The output should include "fail_closed=false"
  End
End
