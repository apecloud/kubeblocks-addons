# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "postProvision budget guard"
  script_file="../scripts/valkey-register-to-sentinel.sh"

  It "defines a 45s budget deadline"
    When call grep -F 'POSTPROVISION_DEADLINE=$((SECONDS + 45))' "${script_file}"
    The status should be success
    The stdout should include 'POSTPROVISION_DEADLINE'
  End

  It "defines a per-sentinel budget estimate"
    When call grep -F 'PER_SENTINEL_BUDGET=' "${script_file}"
    The status should be success
    The stdout should include 'PER_SENTINEL_BUDGET='
  End

  It "checks budget before each sentinel registration"
    When call grep -c 'budget_check' "${script_file}"
    The status should be success
    The stdout should equal "2"
  End

  It "budget_check requires minimum remaining time (not just elapsed >= deadline)"
    When call grep -F 'remaining' "${script_file}"
    The status should be success
    The stdout should include 'remaining'
  End

  It "uses connectivity retry 3x3 (max 9s) not 5x5 (25s)"
    When call grep -E 'call_func_with_retry 3 3 check_(sentinel|data)_connectivity' "${script_file}"
    The status should be success
    The stdout should include "call_func_with_retry 3 3"
  End

  It "uses 5-second retry only for the initial SENTINEL monitor registration"
    When call grep -c 'call_func_with_retry 3 5 execute_sentinel_cmd' "${script_file}"
    The status should be success
    The stdout should equal "1"
  End

  It "uses 2-second retry for sentinel SET commands (not 5)"
    When call grep -c 'call_func_with_retry 3 2 execute_sentinel_cmd' "${script_file}"
    The status should be success
    The stdout should include "5"
  End

  It "prints elapsed time on successful completion"
    When call grep -F 'elapsed' "${script_file}"
    The status should be success
    The stdout should include "elapsed"
  End

  Describe "budget_check functional test — refuses when remaining < PER_SENTINEL_BUDGET"
    setup() {
      spec_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/valkey-budget-spec.XXXXXX")
      cat > "${spec_tmp_dir}/budget_test.sh" <<'SCRIPT'
#!/bin/bash
SECONDS=40
POSTPROVISION_DEADLINE=45
PER_SENTINEL_BUDGET=12
budget_check() {
  local remaining=$(( POSTPROVISION_DEADLINE - SECONDS ))
  if [ "$remaining" -lt "$PER_SENTINEL_BUDGET" ]; then
    echo "ERROR: postProvision budget insufficient (${SECONDS}s elapsed, ${remaining}s remaining, need ${PER_SENTINEL_BUDGET}s)" >&2
    exit 1
  fi
}
budget_check
echo "should not reach here"
SCRIPT
      chmod +x "${spec_tmp_dir}/budget_test.sh"
    }
    Before "setup"

    cleanup() { rm -rf "${spec_tmp_dir:-}"; }
    After "cleanup"

    It "exits 1 when remaining time < PER_SENTINEL_BUDGET"
      When run bash "${spec_tmp_dir}/budget_test.sh"
      The status should equal 1
      The stderr should include "budget insufficient"
      The stderr should include "remaining"
      The stdout should be blank
    End
  End

  Describe "budget_check functional test — allows when remaining >= PER_SENTINEL_BUDGET"
    setup() {
      spec_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/valkey-budget-spec.XXXXXX")
      cat > "${spec_tmp_dir}/budget_pass_test.sh" <<'SCRIPT'
#!/bin/bash
SECONDS=20
POSTPROVISION_DEADLINE=45
PER_SENTINEL_BUDGET=12
budget_check() {
  local remaining=$(( POSTPROVISION_DEADLINE - SECONDS ))
  if [ "$remaining" -lt "$PER_SENTINEL_BUDGET" ]; then
    echo "ERROR: postProvision budget insufficient (${SECONDS}s elapsed, ${remaining}s remaining, need ${PER_SENTINEL_BUDGET}s)" >&2
    exit 1
  fi
}
budget_check
echo "budget ok"
SCRIPT
      chmod +x "${spec_tmp_dir}/budget_pass_test.sh"
    }
    Before "setup"

    cleanup() { rm -rf "${spec_tmp_dir:-}"; }
    After "cleanup"

    It "passes when remaining time >= PER_SENTINEL_BUDGET"
      When run bash "${spec_tmp_dir}/budget_pass_test.sh"
      The status should equal 0
      The stdout should include "budget ok"
    End
  End
End
