# shellcheck shell=bash

Describe "replication primary-write commit linearization"
  entrypoint_file() {
    printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "${SHELLSPEC_CWD:?}"
  }

  prestop_file() {
    printf "%s/addons/mariadb/scripts/replication-prestop.sh" "${SHELLSPEC_CWD:?}"
  }

  extract_function_from() {
    source_file="$1"
    function_name="$2"
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
    ' "${source_file}"
  }

  run_accept_then_prestop_interleaving() {
    work_dir="$(mktemp -d)"
    harness="${work_dir}/harness.sh"
    trace="${work_dir}/trace"
    data_dir="${work_dir}/data"
    mkdir -p "${data_dir}"
    printf '%s\n' NO_LOCK_NO_ADMIN > "${data_dir}/global"
    touch "${data_dir}/local-locked" "${data_dir}/remote-locked"

    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -u'
      extract_function_from "$(entrypoint_file)" try_acquire_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" release_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" set_primary_read_write
      extract_function_from "$(prestop_file)" acquire_primary_write_commit_lock_for_prestop
      cat <<'HARNESS'
PRIMARY_WRITE_COMMIT_LOCK_DIR="${DATA_DIR}/.primary-write-commit-lock"
PRIMARY_WRITE_ACCEPT_PENDING_FILE="${DATA_DIR}/.primary-write-accept-pending"
trace_event() { printf '%s\n' "$1" >> "${TRACE_FILE}"; }
prestop_watchdog_log() { trace_event "accept:$*"; }
prestop_log() { trace_event "prestop:$*"; }
mark_replication_pending() {
  rm -f "${DATA_DIR}/.primary-read-write-ready" "${DATA_DIR}/.replication-ready"
  touch "${DATA_DIR}/.replication-pending"
}
mark_replication_ready() {
  touch "${DATA_DIR}/.replication-ready"
  rm -f "${DATA_DIR}/.replication-pending"
  trace_event replication-ready-published
}
read_only_is_fail_closed() { return 0; }
primary_write_gates_ready() { trace_event required-gates-pass; }
rollback_locked_primary_accept() { trace_event unexpected-rollback; return 2; }
rollback_fenced_primary_accept() { trace_event unexpected-rollback; return 0; }
unlock_local_root_writes() { rm -f "${DATA_DIR}/local-locked"; trace_event local-unlocked; }
unlock_remote_root_writes() { rm -f "${DATA_DIR}/remote-locked"; trace_event remote-unlocked; }
authoritative_primary_write_commit() {
  trace_event syncer-first-open-entered
  i=0
  while [ ! -f "${ALLOW_COMMIT}" ] && [ "${i}" -lt 50 ]; do
    sleep 0.05
    i=$((i + 1))
  done
  [ -f "${ALLOW_COMMIT}" ] || return 1
  printf '%s\n' OFF > "${DATA_DIR}/global"
  trace_event syncer-authority-commit-pass
}
authoritative_primary_write_publish() {
  rm -f "${PRIMARY_WRITE_ACCEPT_PENDING_FILE}"
  trace_event syncer-publication-commit-pass
}

run_accept() {
  set_primary_read_write linearization require-dcs-primary
  printf '%s\n' "$?" > "${ACCEPT_RC}"
}
run_prestop() {
  acquire_primary_write_commit_lock_for_prestop || return 1
  touch "${DATA_DIR}/.prestop-fence-started" "${DATA_DIR}/.replication-pending"
  rm -f "${DATA_DIR}/.replication-ready" "${DATA_DIR}/.primary-read-write-ready"
  printf '%s\n' NO_LOCK_NO_ADMIN > "${DATA_DIR}/global"
  touch "${DATA_DIR}/local-locked" "${DATA_DIR}/remote-locked"
  trace_event prestop-strongest-fence-complete
}

run_accept &
accept_pid=$!
i=0
while ! grep -q '^syncer-first-open-entered$' "${TRACE_FILE}" 2>/dev/null && [ "${i}" -lt 50 ]; do
  sleep 0.05
  i=$((i + 1))
done
grep -q '^syncer-first-open-entered$' "${TRACE_FILE}"

run_prestop &
prestop_pid=$!
sleep 0.2
# preStop cannot publish its marker or fence while acceptance owns the commit.
[ ! -f "${DATA_DIR}/.prestop-fence-started" ]
! grep -q '^prestop-strongest-fence-complete$' "${TRACE_FILE}"

touch "${ALLOW_COMMIT}"
wait "${accept_pid}"
wait "${prestop_pid}"

[ "$(cat "${ACCEPT_RC}")" -eq 0 ]
[ "$(cat "${DATA_DIR}/global")" = NO_LOCK_NO_ADMIN ]
[ -f "${DATA_DIR}/local-locked" ]
[ -f "${DATA_DIR}/remote-locked" ]
[ ! -f "${DATA_DIR}/.primary-read-write-ready" ]
[ -f "${DATA_DIR}/.prestop-fence-started" ]
commit_line="$(grep -n '^syncer-authority-commit-pass$' "${TRACE_FILE}" | cut -d: -f1)"
accept_line="$(grep -n 'primary-write-accept label=linearization rc=0' "${TRACE_FILE}" | cut -d: -f1)"
prestop_line="$(grep -n '^prestop-strongest-fence-complete$' "${TRACE_FILE}" | cut -d: -f1)"
[ -n "${commit_line}" ]
[ -n "${accept_line}" ]
[ -n "${prestop_line}" ]
[ "${commit_line}" -lt "${accept_line}" ]
[ "${commit_line}" -lt "${prestop_line}" ]
cat "${TRACE_FILE}"
HARNESS
    } > "${harness}"

    TRACE_FILE="${trace}" DATA_DIR="${data_dir}" \
      ALLOW_COMMIT="${work_dir}/allow" ACCEPT_RC="${work_dir}/accept-rc" \
      bash "${harness}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  run_authoritative_success_then_publish_markers() {
    work_dir="$(mktemp -d)"
    harness="${work_dir}/harness.sh"
    trace="${work_dir}/trace"
    data_dir="${work_dir}/data"
    mkdir -p "${data_dir}"
    printf '%s\n' NO_LOCK_NO_ADMIN > "${data_dir}/global"
    touch "${data_dir}/local-locked" "${data_dir}/remote-locked"

    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -u'
      extract_function_from "$(entrypoint_file)" try_acquire_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" release_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" set_primary_read_write
      cat <<'HARNESS'
PRIMARY_WRITE_COMMIT_LOCK_DIR="${DATA_DIR}/.primary-write-commit-lock"
PRIMARY_WRITE_ACCEPT_PENDING_FILE="${DATA_DIR}/.primary-write-accept-pending"
trace_event() { printf '%s\n' "$1" >> "${TRACE_FILE}"; }
prestop_watchdog_log() { trace_event "accept:$*"; }
mark_replication_pending() {
  rm -f "${DATA_DIR}/.primary-read-write-ready" "${DATA_DIR}/.replication-ready"
  touch "${DATA_DIR}/.replication-pending"
}
mark_replication_ready() {
  touch "${DATA_DIR}/.replication-ready"
  rm -f "${DATA_DIR}/.replication-pending"
  trace_event replication-ready-published-by-caller
}
read_only_is_fail_closed() { return 0; }
primary_write_gates_ready() { return 0; }
rollback_locked_primary_accept() { trace_event unexpected-rollback; return 2; }
rollback_fenced_primary_accept() { trace_event unexpected-rollback; return 0; }
unlock_local_root_writes() { rm -f "${DATA_DIR}/local-locked"; }
unlock_remote_root_writes() { rm -f "${DATA_DIR}/remote-locked"; }
authoritative_primary_write_commit() {
  printf '%s\n' OFF > "${DATA_DIR}/global"
  trace_event syncer-terminal-success-received
  return 0
}
authoritative_primary_write_publish() {
  rm -f "${PRIMARY_WRITE_ACCEPT_PENDING_FILE}"
  trace_event syncer-publication-commit-pass
}

set_primary_read_write caller-publication require-dcs-primary
[ "$?" -eq 0 ]
[ -f "${DATA_DIR}/.primary-read-write-ready" ]
[ -f "${DATA_DIR}/.replication-ready" ]
[ ! -f "${DATA_DIR}/.replication-pending" ]
[ ! -f "${PRIMARY_WRITE_ACCEPT_PENDING_FILE}" ]
syncer_line="$(grep -n '^syncer-terminal-success-received$' "${TRACE_FILE}" | cut -d: -f1)"
replication_line="$(grep -n '^replication-ready-published-by-caller$' "${TRACE_FILE}" | cut -d: -f1)"
[ -n "${syncer_line}" ]
[ -n "${replication_line}" ]
[ "${syncer_line}" -lt "${replication_line}" ]
cat "${TRACE_FILE}"
HARNESS
    } > "${harness}"

    TRACE_FILE="${trace}" DATA_DIR="${data_dir}" bash "${harness}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  run_authoritative_failure_after_writer_open_rolls_back() {
    work_dir="$(mktemp -d)"
    harness="${work_dir}/harness.sh"
    trace="${work_dir}/trace"
    data_dir="${work_dir}/data"
    mkdir -p "${data_dir}"
    printf '%s\n' NO_LOCK_NO_ADMIN > "${data_dir}/global"
    touch "${data_dir}/local-locked" "${data_dir}/remote-locked"

    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -u'
      extract_function_from "$(entrypoint_file)" try_acquire_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" release_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" force_release_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" set_primary_read_write
      cat <<'HARNESS'
PRIMARY_WRITE_COMMIT_LOCK_DIR="${DATA_DIR}/.primary-write-commit-lock"
PRIMARY_WRITE_ACCEPT_PENDING_FILE="${DATA_DIR}/.primary-write-accept-pending"
trace_event() { printf '%s\n' "$1" >> "${TRACE_FILE}"; }
prestop_watchdog_log() { trace_event "accept:$*"; }
mark_replication_pending() {
  rm -f "${DATA_DIR}/.primary-read-write-ready" "${DATA_DIR}/.replication-ready"
  touch "${DATA_DIR}/.replication-pending"
}
mark_replication_ready() {
  touch "${DATA_DIR}/.replication-ready"
  rm -f "${DATA_DIR}/.replication-pending"
  trace_event unexpected-ready-publication
}
read_only_is_fail_closed() { return 0; }
primary_write_gates_ready() { return 0; }
unlock_local_root_writes() { rm -f "${DATA_DIR}/local-locked"; }
unlock_remote_root_writes() { rm -f "${DATA_DIR}/remote-locked"; }
authoritative_primary_write_commit() {
  printf '%s\n' OFF > "${DATA_DIR}/global"
  trace_event syncer-opened-writers-before-error
  return 1
}
rollback_fenced_primary_accept() {
  mark_replication_pending
  printf '%s\n' NO_LOCK_NO_ADMIN > "${DATA_DIR}/global"
  touch "${DATA_DIR}/local-locked" "${DATA_DIR}/remote-locked"
  trace_event caller-rollback-strongest-fence
  return 0
}
rollback_locked_primary_accept() {
  rollback_fenced_primary_accept "$1" "$2"
  release_primary_write_commit_lock
  return 2
}

accept_rc=0
set_primary_read_write caller-rollback require-dcs-primary || accept_rc=$?
failure=0
[ "${accept_rc}" -eq 2 ] || failure=1
[ "$(cat "${DATA_DIR}/global")" = NO_LOCK_NO_ADMIN ] || failure=1
[ -f "${DATA_DIR}/local-locked" ] || failure=1
[ -f "${DATA_DIR}/remote-locked" ] || failure=1
[ -f "${DATA_DIR}/.replication-pending" ] || failure=1
[ -f "${DATA_DIR}/.primary-write-accept-pending" ] || failure=1
[ ! -f "${DATA_DIR}/.replication-ready" ] || failure=1
[ ! -f "${DATA_DIR}/.primary-read-write-ready" ] || failure=1
cat "${TRACE_FILE}"
exit "${failure}"
HARNESS
    } > "${harness}"

    TRACE_FILE="${trace}" DATA_DIR="${data_dir}" bash "${harness}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  run_authority_drift_after_marker_stage_before_publication_commit() {
    work_dir="$(mktemp -d)"
    harness="${work_dir}/harness.sh"
    trace="${work_dir}/trace"
    data_dir="${work_dir}/data"
    mkdir -p "${data_dir}"
    printf '%s\n' NO_LOCK_NO_ADMIN > "${data_dir}/global"
    printf '%s\n' primary > "${data_dir}/authority"
    touch "${data_dir}/local-locked" "${data_dir}/remote-locked"

    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -u'
      extract_function_from "$(entrypoint_file)" try_acquire_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" release_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" force_release_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" set_primary_read_write
      cat <<'HARNESS'
PRIMARY_WRITE_COMMIT_LOCK_DIR="${DATA_DIR}/.primary-write-commit-lock"
PRIMARY_WRITE_ACCEPT_PENDING_FILE="${DATA_DIR}/.primary-write-accept-pending"
trace_event() { printf '%s\n' "$1" >> "${TRACE_FILE}"; }
prestop_watchdog_log() { trace_event "accept:$*"; }
mark_replication_pending() {
  rm -f "${DATA_DIR}/.primary-read-write-ready" "${DATA_DIR}/.replication-ready"
  touch "${DATA_DIR}/.replication-pending"
}
mark_replication_ready() {
  touch "${DATA_DIR}/.replication-ready"
  rm -f "${DATA_DIR}/.replication-pending"
  trace_event caller-markers-staged
}
read_only_is_fail_closed() { return 0; }
primary_write_gates_ready() { return 0; }
unlock_local_root_writes() { rm -f "${DATA_DIR}/local-locked"; }
unlock_remote_root_writes() { rm -f "${DATA_DIR}/remote-locked"; }
authoritative_primary_write_commit() {
  printf '%s\n' OFF > "${DATA_DIR}/global"
  trace_event syncer-writer-open-committed
  return 0
}
authoritative_primary_write_publish() {
  # Model RunCycle winning the HA mutex after the writer-open receipt but
  # before publication. The production finalize operation must refresh
  # authority and reject without deleting the durable guard.
  printf '%s\n' secondary > "${DATA_DIR}/authority"
  trace_event run-cycle-demoted-before-publication-commit
  return 1
}
rollback_fenced_primary_accept() {
  mark_replication_pending
  printf '%s\n' NO_LOCK_NO_ADMIN > "${DATA_DIR}/global"
  touch "${DATA_DIR}/local-locked" "${DATA_DIR}/remote-locked"
  trace_event caller-rollback-strongest-fence
  return 0
}
rollback_locked_primary_accept() {
  rollback_fenced_primary_accept "$1" "$2"
  release_primary_write_commit_lock
  return 2
}

accept_rc=0
set_primary_read_write post-marker-drift require-dcs-primary || accept_rc=$?
failure=0
[ "${accept_rc}" -eq 2 ] || failure=1
[ "$(cat "${DATA_DIR}/authority")" = secondary ] || failure=1
[ "$(cat "${DATA_DIR}/global")" = NO_LOCK_NO_ADMIN ] || failure=1
[ -f "${DATA_DIR}/local-locked" ] || failure=1
[ -f "${DATA_DIR}/remote-locked" ] || failure=1
[ -f "${DATA_DIR}/.replication-pending" ] || failure=1
[ -f "${DATA_DIR}/.primary-write-accept-pending" ] || failure=1
[ ! -f "${DATA_DIR}/.replication-ready" ] || failure=1
[ ! -f "${DATA_DIR}/.primary-read-write-ready" ] || failure=1
cat "${TRACE_FILE}"
exit "${failure}"
HARNESS
    } > "${harness}"

    TRACE_FILE="${trace}" DATA_DIR="${data_dir}" bash "${harness}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  run_accept_held_past_prestop_lock_budget() {
    work_dir="$(mktemp -d)"
    harness="${work_dir}/harness.sh"
    trace="${work_dir}/trace"
    data_dir="${work_dir}/data"
    mkdir -p "${data_dir}"
    printf '%s\n' NO_LOCK_NO_ADMIN > "${data_dir}/global"
    touch "${data_dir}/local-locked" "${data_dir}/remote-locked"

    {
      printf '%s\n' '#!/usr/bin/env bash' 'set -u'
      extract_function_from "$(entrypoint_file)" try_acquire_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" release_primary_write_commit_lock
      extract_function_from "$(entrypoint_file)" set_primary_read_write
      extract_function_from "$(prestop_file)" acquire_primary_write_commit_lock_for_prestop
      cat <<'HARNESS'
PRIMARY_WRITE_COMMIT_LOCK_DIR="${DATA_DIR}/.primary-write-commit-lock"
PRIMARY_WRITE_ACCEPT_PENDING_FILE="${DATA_DIR}/.primary-write-accept-pending"
trace_event() { printf '%s\n' "$1" >> "${TRACE_FILE}"; }
prestop_watchdog_log() { trace_event "accept:$*"; }
prestop_log() { trace_event "prestop:$*"; }
# Scale only preStop's production 400 x 0.1s lock budget down for a fast unit
# harness. The number of attempts and timeout branch remain production-exact.
sleep() { command sleep 0.001; }
mark_replication_pending() {
  rm -f "${DATA_DIR}/.primary-read-write-ready" "${DATA_DIR}/.replication-ready"
  touch "${DATA_DIR}/.replication-pending"
}
mark_replication_ready() {
  touch "${DATA_DIR}/.replication-ready"
  rm -f "${DATA_DIR}/.replication-pending"
  trace_event replication-ready-published
}
read_only_is_fail_closed() { return 0; }
primary_write_gates_ready() { trace_event required-gates-pass; }
rollback_locked_primary_accept() { trace_event unexpected-rollback; return 2; }
rollback_fenced_primary_accept() { trace_event unexpected-rollback; return 0; }
unlock_local_root_writes() { rm -f "${DATA_DIR}/local-locked"; trace_event local-unlocked; }
unlock_remote_root_writes() { rm -f "${DATA_DIR}/remote-locked"; trace_event remote-unlocked; }
authoritative_primary_write_commit() {
  trace_event syncer-first-open-entered
  while [ ! -f "${ALLOW_COMMIT}" ]; do
    command sleep 0.005
  done
  printf '%s\n' OFF > "${DATA_DIR}/global"
  trace_event syncer-authority-commit-pass
}
query_local_syncer_role() { printf '%s\n' primary; }

run_accept() {
  accept_rc=0
  set_primary_read_write linearization-timeout require-dcs-primary || accept_rc=$?
  printf '%s\n' "${accept_rc}" > "${ACCEPT_RC}"
  return 0
}
run_prestop_timeout_branch() {
  # The production hook must fail before any marker/SQL mutation when it
  # cannot own the commit. Kubelet then terminates the whole container; model
  # that external fail-close boundary by terminating the in-flight accept.
  if ! acquire_primary_write_commit_lock_for_prestop; then
    trace_event prestop-hook-failed-before-mutation
    kill "${accept_pid}" 2>/dev/null || true
    wait "${accept_pid}" 2>/dev/null || true
    return 1
  fi
  touch "${DATA_DIR}/.prestop-fence-started" "${DATA_DIR}/.replication-pending"
  rm -f "${DATA_DIR}/.replication-ready" "${DATA_DIR}/.primary-read-write-ready"
  printf '%s\n' NO_LOCK_NO_ADMIN > "${DATA_DIR}/global"
  touch "${DATA_DIR}/local-locked" "${DATA_DIR}/remote-locked"
  trace_event prestop-timeout-fence-complete
}

run_accept &
accept_pid=$!
while ! grep -q '^syncer-first-open-entered$' "${TRACE_FILE}" 2>/dev/null; do
  command sleep 0.005
done

run_prestop_timeout_branch || true
grep -q 'reason=accept-owner-timeout' "${TRACE_FILE}"

cat "${TRACE_FILE}"
failure=0
[ ! -f "${ACCEPT_RC}" ] || failure=1
[ ! -f "${DATA_DIR}/.prestop-fence-started" ] || failure=1
[ ! -f "${DATA_DIR}/.primary-read-write-ready" ] || failure=1
[ ! -f "${DATA_DIR}/.replication-ready" ] || failure=1
exit "${failure}"
HARNESS
    } > "${harness}"

    TRACE_FILE="${trace}" DATA_DIR="${data_dir}" \
      ALLOW_COMMIT="${work_dir}/allow" ACCEPT_RC="${work_dir}/accept-rc" \
      bash "${harness}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  startup_clears_only_stale_commit_lock() {
    awk '
      /^if \[ ! -f "\$\{LIFECYCLE_MARKER\}" \]; then$/ { startup = 1 }
      startup && /^elif \[ -f "\$\{DATA_DIR\}\/\.prestop-fence-started" \]; then$/ { startup = 0 }
      startup && index($0, "rm -rf \"${PRIMARY_WRITE_COMMIT_LOCK_DIR}\"") { print; found++ }
      END { exit(found == 1 ? 0 : 1) }
    ' "$(entrypoint_file)"
  }

  prestop_acquires_commit_lock_before_marker() {
    lock_line="$(grep -n '^if ! acquire_primary_write_commit_lock_for_prestop; then$' "$(prestop_file)" | cut -d: -f1)"
    marker_line="$(grep -n '^touch "${DATA_DIR}/.prestop-fence-started"' "$(prestop_file)" | cut -d: -f1)"
    [ -n "${lock_line}" ]
    [ -n "${marker_line}" ]
    [ "${lock_line}" -lt "${marker_line}" ]
  }

  It "serializes first-open and preStop so the later preStop leaves the final state strongest-fenced"
    When call run_accept_then_prestop_interleaving
    The status should be success
    The output should include "syncer-authority-commit-pass"
    The output should include "prestop-strongest-fence-complete"
    The output should not include "unexpected-rollback"
  End

  It "publishes primary and replication readiness only after terminal syncer success"
    When call run_authoritative_success_then_publish_markers
    The status should be success
    The output should include "syncer-terminal-success-received"
    The output should include "replication-ready-published-by-caller"
    The output should not include "unexpected-rollback"
  End

  It "restores the strongest fence when syncer errors after opening writers"
    When call run_authoritative_failure_after_writer_open_rolls_back
    The status should be success
    The output should include "syncer-opened-writers-before-error"
    The output should include "caller-rollback-strongest-fence"
    The output should not include "unexpected-ready-publication"
  End

  It "rejects authority drift after marker staging before the mutex-linearized publication commit"
    When call run_authority_drift_after_marker_stage_before_publication_commit
    The status should be success
    The output should include "run-cycle-demoted-before-publication-commit"
    The output should include "caller-rollback-strongest-fence"
  End

  It "does not let an accept publish ready after preStop exhausts its commit-lock budget"
    When call run_accept_held_past_prestop_lock_budget
    The status should be success
    The output should include "accept-owner-timeout"
    The output should not include "replication-ready-published"
  End

  It "clears a stale commit owner only on a fresh container lifecycle"
    When call startup_clears_only_stale_commit_lock
    The status should be success
    The output should include 'PRIMARY_WRITE_COMMIT_LOCK_DIR'
  End

  It "makes preStop own the commit lock before publishing its fence marker"
    When call prestop_acquires_commit_lock_before_marker
    The status should be success
  End
End
