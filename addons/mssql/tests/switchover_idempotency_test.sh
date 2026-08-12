#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Production-script test for targeted switchover replay semantics. The first
# syncer call may complete the topology change while a duplicate invocation
# reaches syncer after the old primary has started demoting. A non-zero CLI
# result is therefore not sufficient evidence that the requested state failed.
#
# No live SQL Server is required. The real switchover.sh runs with mocked
# sqlcmd, syncerctl, and conn_pod boundaries. ROLE_SAMPLES is a comma-separated
# sequence of "<old-primary-role>:<candidate-role>" samples where SQL Server
# role values are 1=PRIMARY and 2=SECONDARY.

set -u

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
SWITCHOVER_SCRIPT="${SWITCHOVER_SCRIPT:-$SCRIPTS_DIR/switchover.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"

if command -v timeout >/dev/null 2>&1; then
  :
elif command -v gtimeout >/dev/null 2>&1; then
  cat > "$TMP/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
exec gtimeout "$@"
MOCK
  chmod +x "$TMP/bin/timeout"
else
  # macOS has neither GNU timeout nor gtimeout by default. This fallback is a
  # real fork/TERM/KILL/wait implementation, not a pass-through fake: it lets
  # the production script exercise an actual deadline and proves the monitored
  # child was reaped. Linux CI uses the runtime-compatible GNU timeout above.
  cat > "$TMP/bin/timeout" <<'MOCK'
#!/usr/bin/env perl
use strict;
use warnings;

my $kill_after;
if (@ARGV >= 2 && $ARGV[0] eq '-k') {
  shift @ARGV;
  $kill_after = shift @ARGV;
  $kill_after =~ s/s$//;
}
die "missing -k" unless defined $kill_after;
my $deadline = shift @ARGV;
$deadline =~ s/s$//;
die "missing command" unless @ARGV;

my $pid = fork();
die "fork failed: $!" unless defined $pid;
if ($pid == 0) {
  exec @ARGV;
  die "exec failed: $!";
}

my $timed_out = 0;
$SIG{ALRM} = sub {
  $timed_out = 1;
  kill 'TERM', $pid;
  $SIG{ALRM} = sub { kill 'KILL', $pid; };
  alarm($kill_after);
};
alarm($deadline);
waitpid($pid, 0);
alarm(0);
my $status = $?;
if ($timed_out) {
  exit(($status & 127) == 9 ? 137 : 124);
}
exit($status >> 8);
MOCK
  chmod +x "$TMP/bin/timeout"
fi

cat > "$TMP/bin/sqlcmd" <<'MOCK'
#!/usr/bin/env bash
printf '1 1\n'
MOCK
chmod +x "$TMP/bin/sqlcmd"

cat > "$TMP/syncerctl" <<'MOCK'
#!/usr/bin/env bash
if [ "${SYNCER_MODE:-exit}" = "term-resistant" ]; then
  printf '%s\n' "$$" > "$STATE_DIR/syncer-pid"
  trap '' TERM
  while :; do :; done
fi
printf '%s\n' "${SYNCER_OUTPUT:-switchover mock result}" >&2
exit "${SYNCER_RC:-0}"
MOCK
chmod +x "$TMP/syncerctl"

cat > "$TMP/common.sh" <<'MOCK'
log() {
  printf '%s\n' "$*"
}

conn_pod() {
  local count_file="${STATE_DIR}/role-probe-count"
  local count=0
  [ ! -f "$count_file" ] || count=$(cat "$count_file")
  count=$((count + 1))
  printf '%s\n' "$count" > "$count_file"

  local sample
  sample=$(printf '%s' "${ROLE_SAMPLES:-}" | cut -d, -f"$count")
  if [ -z "$sample" ]; then
    sample=$(printf '%s' "${ROLE_SAMPLES:-}" | awk -F, '{print $NF}')
  fi
  [ -n "$sample" ] || return 1

  local current_role="${sample%%:*}"
  local candidate_role="${sample##*:}"
  [ -n "$current_role" ] && [ -n "$candidate_role" ] || return 1
  printf '%s %s\n' "$KB_SWITCHOVER_CURRENT_NAME" "$current_role"
  printf '%s %s\n' "$KB_SWITCHOVER_CANDIDATE_NAME" "$candidate_role"
}
MOCK

# Replace only runtime filesystem boundaries. All control flow remains the
# checked-in production script.
sed \
  -e "s#source /scripts/common.sh#source \"$TMP/common.sh\"#" \
  -e "s#/tools/syncerctl#\"$TMP/syncerctl\"#g" \
  -e 's/^SWITCHOVER_TIMEOUT_SECONDS=.*/SWITCHOVER_TIMEOUT_SECONDS=1/' \
  -e 's/^POSTCHECK_SLEEP=.*/POSTCHECK_SLEEP=0/' \
  "$SWITCHOVER_SCRIPT" > "$TMP/switchover-under-test.sh"

pass=0
fail=0
hard_timeout=false

if grep -Fq 'SWITCHOVER_TIMEOUT_SECONDS=' "$SWITCHOVER_SCRIPT" &&
   grep -Fq 'SWITCHOVER_KILL_AFTER_SECONDS=' "$SWITCHOVER_SCRIPT" &&
   grep -Fq "timeout -k \"\${SWITCHOVER_KILL_AFTER_SECONDS}s\" \"\${SWITCHOVER_TIMEOUT_SECONDS}s\"" "$SWITCHOVER_SCRIPT"; then
  echo "PASS  syncerctl mutation has a TERM-to-KILL hard timeout budget"
  pass=$((pass + 1))
  hard_timeout=true
else
  echo "FAIL  syncerctl mutation lacks a TERM-to-KILL hard timeout budget"
  fail=$((fail + 1))
fi

run_case() {
  local label="$1"
  local expected="$2"
  local syncer_rc="$3"
  local role_samples="$4"
  local candidate="mssql-1"
  [ "$#" -lt 5 ] || candidate="$5"
  local syncer_mode="exit"
  [ "$#" -lt 6 ] || syncer_mode="$6"
  local state_dir="$TMP/state-${pass}-${fail}"
  local out rc started finished elapsed
  mkdir -p "$state_dir"

  started=$(date +%s)
  out=$(
    PATH="$TMP/bin:$PATH" \
    STATE_DIR="$state_dir" \
    ROLE_SAMPLES="$role_samples" \
    SYNCER_RC="$syncer_rc" \
    SYNCER_MODE="$syncer_mode" \
    SYNCER_OUTPUT="mssql-0 is not the primary" \
    SQLCMD="$TMP/bin/sqlcmd" \
    MSSQL_SERVER_PORT=1433 \
    MSSQL_SA_USER=sa \
    MSSQL_SA_PASSWORD=test \
    KB_CLUSTER_COMP_NAME=mssql \
    KB_SWITCHOVER_ROLE=primary \
    KB_SWITCHOVER_CURRENT_NAME=mssql-0 \
    KB_SWITCHOVER_CANDIDATE_NAME="$candidate" \
    bash "$TMP/switchover-under-test.sh" 2>&1
  )
  rc=$?
  finished=$(date +%s)
  elapsed=$((finished - started))

  local outcome_ok=false
  if { [ "$expected" = success ] && [ "$rc" -eq 0 ]; } ||
     { [ "$expected" = failure ] && [ "$rc" -ne 0 ]; }; then
    outcome_ok=true
  fi

  local deadline_ok=true
  local timeout_rc_ok=true
  if [ "$syncer_mode" = "term-resistant" ]; then
    local syncer_pid=""
    [ ! -f "$state_dir/syncer-pid" ] || syncer_pid=$(cat "$state_dir/syncer-pid")
    if [ "$elapsed" -lt 1 ] || [ "$elapsed" -gt 4 ] ||
       [ -z "$syncer_pid" ] || kill -0 "$syncer_pid" 2>/dev/null; then
      deadline_ok=false
    fi
    if ! printf '%s\n' "$out" | grep -Fq 'switchover command failed (rc=137):'; then
      timeout_rc_ok=false
    fi
  fi

  if [ "$outcome_ok" = true ] && [ "$deadline_ok" = true ] && [ "$timeout_rc_ok" = true ]; then
    printf 'PASS  %s (rc=%s elapsed=%ss)\n' "$label" "$rc" "$elapsed"
    pass=$((pass + 1))
  else
    printf 'FAIL  %s (expected=%s rc=%s elapsed=%ss hard-deadline=%s timeout-rc=%s)\n' \
      "$label" "$expected" "$rc" "$elapsed" "$deadline_ok" "$timeout_rc_ok"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
}

run_case "syncer success remains success" success 0 "1:2"
run_case "duplicate failure closes when requested topology is already converged" success 255 "2:1"
run_case "candidate primary without old-primary demotion stays failed" failure 255 "1:1,1:1,1:1"
run_case "old primary secondary without candidate promotion stays failed" failure 255 "2:2,2:2,2:2"
run_case "duplicate failure closes after bounded mid-poll transition" success 255 "1:2,2:1"
if [ "$hard_timeout" = true ]; then
  run_case "TERM-resistant syncer is killed and converged topology closes" success 124 "2:1" "mssql-1" "term-resistant"
  run_case "TERM-resistant syncer is killed and unknown topology fails" failure 124 "" "mssql-1" "term-resistant"
else
  echo "FAIL  real deadline/reap cases blocked by missing hard-timeout contract"
  fail=$((fail + 2))
fi
run_case "syncer failure stays failed while old topology persists" failure 255 "1:2,1:2,1:2"
run_case "unknown post-state stays failed" failure 255 ""
run_case "non-targeted syncer failure cannot be declared idempotent" failure 255 "2:1" ""

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
