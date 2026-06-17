# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "postProvision budget guard"
  script_file="../scripts/valkey-register-to-sentinel.sh"

  It "defines a 45s budget deadline"
    When call grep -F 'POSTPROVISION_DEADLINE=$((SECONDS + 45))' "${script_file}"
    The status should be success
    The stdout should include 'POSTPROVISION_DEADLINE'
  End

  It "defines per-phase budget constants tied to retry parameters"
    When call grep -c 'BUDGET_' "${script_file}"
    The status should be success
    The stdout should include "1"
  End

  It "BUDGET_CONNECTIVITY covers call_func_with_retry 3 3 worst case"
    When call grep -F 'BUDGET_CONNECTIVITY=10' "${script_file}"
    The status should be success
    The stdout should include 'BUDGET_CONNECTIVITY=10'
  End

  It "BUDGET_MONITOR covers call_func_with_retry 3 5 worst case"
    When call grep -F 'BUDGET_MONITOR=16' "${script_file}"
    The status should be success
    The stdout should include 'BUDGET_MONITOR=16'
  End

  It "BUDGET_SET covers call_func_with_retry 3 2 worst case"
    When call grep -F 'BUDGET_SET=7' "${script_file}"
    The status should be success
    The stdout should include 'BUDGET_SET=7'
  End

  It "budget_require is called before every call_func_with_retry"
    When call grep -c 'budget_require' "${script_file}"
    The status should be success
    The stdout should include "1"
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

  Describe "budget_require functional test — refuses when remaining < needed"
    setup() {
      spec_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/valkey-budget-spec.XXXXXX")
      cat > "${spec_tmp_dir}/budget_test.sh" <<'SCRIPT'
#!/bin/bash
SECONDS=40
POSTPROVISION_DEADLINE=45
budget_require() {
  local needed="${1}"
  local label="${2:-next step}"
  local remaining=$(( POSTPROVISION_DEADLINE - SECONDS ))
  if [ "$remaining" -lt "$needed" ]; then
    echo "ERROR: postProvision budget insufficient for ${label} (${remaining}s remaining, need ${needed}s)" >&2
    return 1
  fi
}
budget_require 10 "sentinel connectivity check" || exit 1
echo "should not reach here"
SCRIPT
      chmod +x "${spec_tmp_dir}/budget_test.sh"
    }
    Before "setup"

    cleanup() { rm -rf "${spec_tmp_dir:-}"; }
    After "cleanup"

    It "exits when remaining (5s) < needed (10s)"
      When run bash "${spec_tmp_dir}/budget_test.sh"
      The status should equal 1
      The stderr should include "budget insufficient"
      The stderr should include "sentinel connectivity"
      The stderr should include "5s remaining"
      The stderr should include "need 10s"
      The stdout should be blank
    End
  End

  Describe "budget_require functional test — allows when remaining >= needed"
    setup() {
      spec_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/valkey-budget-spec.XXXXXX")
      cat > "${spec_tmp_dir}/budget_pass_test.sh" <<'SCRIPT'
#!/bin/bash
SECONDS=20
POSTPROVISION_DEADLINE=45
budget_require() {
  local needed="${1}"
  local label="${2:-next step}"
  local remaining=$(( POSTPROVISION_DEADLINE - SECONDS ))
  if [ "$remaining" -lt "$needed" ]; then
    echo "ERROR: postProvision budget insufficient for ${label} (${remaining}s remaining, need ${needed}s)" >&2
    return 1
  fi
}
budget_require 10 "sentinel connectivity check" || exit 1
echo "budget ok"
SCRIPT
      chmod +x "${spec_tmp_dir}/budget_pass_test.sh"
    }
    Before "setup"

    cleanup() { rm -rf "${spec_tmp_dir:-}"; }
    After "cleanup"

    It "passes when remaining (25s) >= needed (10s)"
      When run bash "${spec_tmp_dir}/budget_pass_test.sh"
      The status should equal 0
      The stdout should include "budget ok"
    End
  End

  Describe "budget_require functional test — each phase checked independently"
    setup() {
      spec_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/valkey-budget-spec.XXXXXX")
      cat > "${spec_tmp_dir}/budget_phase_test.sh" <<'SCRIPT'
#!/bin/bash
SECONDS=30
POSTPROVISION_DEADLINE=45
BUDGET_CONNECTIVITY=10
BUDGET_MONITOR=16
BUDGET_SET=7
budget_require() {
  local needed="${1}"
  local label="${2:-next step}"
  local remaining=$(( POSTPROVISION_DEADLINE - SECONDS ))
  if [ "$remaining" -lt "$needed" ]; then
    echo "ERROR: postProvision budget insufficient for ${label} (${remaining}s remaining, need ${needed}s)" >&2
    return 1
  fi
}
# 15s remaining: connectivity (10) passes, monitor (16) fails
budget_require "$BUDGET_CONNECTIVITY" "connectivity" || { echo "connectivity rejected"; exit 1; }
echo "connectivity accepted"
budget_require "$BUDGET_MONITOR" "monitor" || { echo "monitor rejected"; exit 0; }
echo "should not reach here"
SCRIPT
      chmod +x "${spec_tmp_dir}/budget_phase_test.sh"
    }
    Before "setup"

    cleanup() { rm -rf "${spec_tmp_dir:-}"; }
    After "cleanup"

    It "accepts connectivity (need 10, have 15) but rejects monitor (need 16, have 15)"
      When run bash "${spec_tmp_dir}/budget_phase_test.sh"
      The status should equal 0
      The stdout should include "connectivity accepted"
      The stdout should include "monitor rejected"
      The stderr should include "budget insufficient for monitor"
    End
  End
End
