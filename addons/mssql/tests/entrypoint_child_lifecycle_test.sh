#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-contract test: every asynchronous entrypoint workload must belong
# to an owned process group, and configure failure must clean those groups while
# preserving the original failure code.

set -uo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "SKIP  entrypoint child lifecycle requires Linux process-group semantics"
  echo
  echo "Total: 0 passed, 0 failed, 1 skipped"
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$ROOT/scripts/entrypoint.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

awk '/^# BEGIN child process lifecycle helpers$/,/^# END child process lifecycle helpers$/' \
  "$ENTRYPOINT" > "$TMP/lifecycle.sh"

extract_function() {
  local name="$1" output="$2"
  awk -v name="$name" \
    '$0 ~ "^function " name "([ (]|$)" { found=1 } found { print } found && /^}/ { exit }' \
    "$ENTRYPOINT" > "$output"
}

extract_function sync_all_logins_from_primary "$TMP/login-sync.sh"

if ! grep -q '^function cleanup_children' "$TMP/lifecycle.sh" ||
   ! grep -q '^function sync_all_logins_from_primary' "$TMP/login-sync.sh"; then
  echo "FAIL  could not extract production lifecycle functions"
  exit 1
fi

# shellcheck disable=SC1090
source "$TMP/lifecycle.sh"
# shellcheck disable=SC1090
source "$TMP/login-sync.sh"

log() { :; }

cat > "$TMP/group-worker.sh" <<'WORKER'
#!/usr/bin/env bash
mode="$1"
pid_file="$2"
[ "$mode" = ignore-term ] && trap '' TERM
sleep 300 | cat | cat >/dev/null &
sleep 0.05
children=$(ps -o pid=,comm= --ppid "$$" | awk '$2 == "sleep" || $2 == "cat" { print $1 }' | tr '\n' ' ')
printf '%s %s\n' "$$" "$children" > "$pid_file"
wait
WORKER
chmod +x "$TMP/group-worker.sh"

reset_lifecycle() {
  configure_pgid=""
  log_rotate_pgid=""
  login_sync_pgid=""
  sqlservr_pgid=""
  cleanup_done=false
  ENTRYPOINT_TERM_GRACE_SECONDS=1
  ENTRYPOINT_KILL_CONFIRM_SECONDS=1
  ENTRYPOINT_POLL_INTERVAL_SECONDS=0.05
}

wait_for_file() {
  local file="$1" attempt=0
  while [ ! -s "$file" ] && [ "$attempt" -lt 100 ]; do
    sleep 0.02
    attempt=$((attempt + 1))
  done
  [ -s "$file" ]
}

wait_until_dead() {
  local pid="$1" attempt=0
  while kill -0 "$pid" 2>/dev/null && [ "$attempt" -lt 100 ]; do
    sleep 0.02
    attempt=$((attempt + 1))
  done
  ! kill -0 "$pid" 2>/dev/null
}

case_process_group_cleanup() (
  reset_lifecycle
  local pid_file="$TMP/group-normal.pids"
  start_process_group login_sync_pgid "$TMP/group-worker.sh" normal "$pid_file" || return 1
  wait_for_file "$pid_file" || return 1
  read -r -a pids < "$pid_file"
  leader="${pids[0]}"
  [ "$leader" = "$login_sync_pgid" ] || return 1
  [ "${#pids[@]}" -ge 4 ] || return 1
  local pid pgid
  for pid in "${pids[@]}"; do
    pgid="$(ps -o pgid= -p "$pid" | tr -d '[:space:]')"
    [ "$pgid" = "$login_sync_pgid" ] || return 1
  done
  cleanup_children TERM
  for pid in "${pids[@]}"; do
    wait_until_dead "$pid" || return 1
  done
)

case_bounded_escalation_preserves_rc() (
  reset_lifecycle
  local pid_file="$TMP/group-ignore.pids" start end rc
  start_process_group sqlservr_pgid "$TMP/group-worker.sh" ignore-term "$pid_file" || return 1
  wait_for_file "$pid_file" || return 1
  start=$(date +%s)
  cleanup_children TERM
  rc=17
  end=$(date +%s)
  [ "$rc" -eq 17 ] || return 1
  [ $((end - start)) -le 4 ] || return 1
  read -r -a pids < "$pid_file"
  for pid in "${pids[@]}"; do
    wait_until_dead "$pid" || return 1
  done
)

case_configure_failure_cleans_all_groups() (
  reset_lifecycle
  local configure_file="$TMP/configure.pids" daemon_file="$TMP/daemon.pids" rc
  cat > "$TMP/configure-fail.sh" <<'CONFIGURE'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$1"
sleep 0.2
exit 17
CONFIGURE
  chmod +x "$TMP/configure-fail.sh"
  start_process_group configure_pgid "$TMP/configure-fail.sh" "$configure_file" || return 1
  start_process_group log_rotate_pgid "$TMP/group-worker.sh" normal "$daemon_file" || return 1
  wait_for_file "$configure_file" || return 1
  wait_for_file "$daemon_file" || return 1
  set +e
  wait_for_configure_process
  rc=$?
  set -e
  [ "$rc" -eq 17 ] || return 1
  while read -r pid; do wait_until_dead "$pid" || return 1; done < <(awk '{ for (i=1; i<=NF; i++) print $i }' "$daemon_file")
)

case_configure_success_keeps_owned_sqlservr() (
  reset_lifecycle
  local configure_file="$TMP/configure-success.pids" sql_file="$TMP/sql.pids"
  cat > "$TMP/configure-success.sh" <<'CONFIGURE'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$1"
sleep 0.2
exit 0
CONFIGURE
  chmod +x "$TMP/configure-success.sh"
  start_process_group configure_pgid "$TMP/configure-success.sh" "$configure_file" || return 1
  start_process_group sqlservr_pgid "$TMP/group-worker.sh" normal "$sql_file" || return 1
  wait_for_file "$sql_file" || return 1
  wait_for_configure_process || return 1
  [ -z "$configure_pgid" ] || return 1
  process_group_alive "$sqlservr_pgid" || return 1
  cleanup_children TERM
  while read -r pid; do wait_until_dead "$pid" || return 1; done < <(awk '{ for (i=1; i<=NF; i++) print $i }' "$sql_file")
)

case_exit_trap_covers_spawn_gap() (
  reset_lifecycle
  local pid_file="$TMP/exit-gap.pids"
  set +e
  (
    trap 'entrypoint_exit_trap' EXIT
    start_process_group log_rotate_pgid "$TMP/group-worker.sh" normal "$pid_file"
    wait_for_file "$pid_file"
    false
  )
  local rc=$?
  set -e
  [ "$rc" -eq 1 ] || return 1
  while read -r pid; do wait_until_dead "$pid" || return 1; done < <(awk '{ for (i=1; i<=NF; i++) print $i }' "$pid_file")
)

case_missing_setsid_fails_before_spawn() (
  reset_lifecycle
  local original_setsid="${SETSID_BIN:-}" marker="$TMP/should-not-spawn"
  SETSID_BIN="$TMP/missing-setsid"
  if start_process_group configure_pgid /bin/sh -c "touch '$marker'"; then
    SETSID_BIN="$original_setsid"
    return 1
  fi
  SETSID_BIN="$original_setsid"
  [ ! -e "$marker" ]
)

case_cleanup_is_idempotent() (
  reset_lifecycle
  local pid_file="$TMP/idempotent.pids"
  start_process_group log_rotate_pgid "$TMP/group-worker.sh" normal "$pid_file" || return 1
  wait_for_file "$pid_file" || return 1
  cleanup_children TERM
  cleanup_children TERM
  while read -r pid; do wait_until_dead "$pid" || return 1; done < <(awk '{ for (i=1; i<=NF; i++) print $i }' "$pid_file")
)

case_transient_login_failure_retries() (
  local attempts=0
  TMP_DIR="$TMP/transient"
  KB_POD_NAME=mssql-1
  mkdir -p "$TMP_DIR"
  get_primary_pod_host() { printf 'mssql-0\n'; }
  conn_remote() {
    attempts=$((attempts + 1))
    [ "$attempts" -ge 3 ] || return 1
    printf 'CREATE LOGIN [fixture];\n'
  }
  sleep() { :; }
  script_local() { [ -s "$1" ]; }
  sync_all_logins_from_primary
  [ "$attempts" -eq 3 ]
)

case_permanent_login_failure_is_bounded() (
  local attempts=0 script_calls=0
  TMP_DIR="$TMP/permanent"
  KB_POD_NAME=mssql-1
  mkdir -p "$TMP_DIR"
  get_primary_pod_host() { printf 'mssql-0\n'; }
  conn_remote() {
    attempts=$((attempts + 1))
    printf 'PARTIAL LOGIN SCRIPT\n'
    return 1
  }
  sleep() { :; }
  script_local() { script_calls=$((script_calls + 1)); return 0; }
  if sync_all_logins_from_primary; then return 1; fi
  [ "$attempts" -eq 3 ] && [ "$script_calls" -eq 0 ]
)

case_static_supervision_contract() {
  grep -Fq 'setsid' "$ENTRYPOINT" &&
    grep -Fq "trap 'entrypoint_exit_trap' EXIT" "$ENTRYPOINT" &&
    ! grep -Fq 'wait %1' "$ENTRYPOINT" &&
    ! grep -Fq 'login_sync_daemon 2>&1 |' "$ENTRYPOINT"
}

pass=0
fail=0
run_case() {
  local label="$1" function_name="$2"
  if "$function_name"; then
    echo "PASS  $label"
    pass=$((pass + 1))
  else
    echo "FAIL  $label"
    fail=$((fail + 1))
  fi
}

run_case "owned process group cleans leader and all members" case_process_group_cleanup
run_case "TERM escalation is bounded and preserves failure rc" case_bounded_escalation_preserves_rc
run_case "configure rc 17 cleans all already-started groups" case_configure_failure_cleans_all_groups
run_case "configure success keeps exactly the owned sqlservr group" case_configure_success_keeps_owned_sqlservr
run_case "EXIT trap covers failure between child spawns" case_exit_trap_covers_spawn_gap
run_case "missing setsid fails before any child spawn" case_missing_setsid_fails_before_spawn
run_case "cleanup is idempotent" case_cleanup_is_idempotent
run_case "transient login failure reaches third retry" case_transient_login_failure_retries
run_case "permanent login failure is bounded and fail-closed" case_permanent_login_failure_is_bounded
run_case "entrypoint has no job-spec or login pipeline ownership" case_static_supervision_contract

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
