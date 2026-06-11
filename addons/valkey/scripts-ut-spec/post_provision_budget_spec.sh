# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "postProvision budget guard"
  script_file="../scripts/valkey-register-to-sentinel.sh"

  It "defines a 45s budget deadline"
    When call grep -F 'POSTPROVISION_DEADLINE=$((SECONDS + 45))' "${script_file}"
    The status should be success
    The stdout should include 'POSTPROVISION_DEADLINE'
  End

  It "checks budget before each sentinel registration"
    When call grep -c 'budget_check' "${script_file}"
    The status should be success
    The stdout should equal "2"
  End

  It "exits 1 with diagnostic stderr when budget is exhausted"
    When call grep -F 'budget exhausted' "${script_file}"
    The status should be success
    The stdout should include "budget exhausted"
  End

  It "uses connectivity retry 3x3 (max 9s) not 5x5 (25s)"
    When call grep -E 'call_func_with_retry 3 3 check_(sentinel|data)_connectivity' "${script_file}"
    The status should be success
    The stdout should include "call_func_with_retry 3 3"
  End

  It "does not use 5-second retry intervals for sentinel commands"
    When call grep -E 'call_func_with_retry [0-9]+ 5 execute_sentinel_cmd' "${script_file}"
    The status should be failure
  End

  It "prints elapsed time on successful completion"
    When call grep -F 'elapsed' "${script_file}"
    The status should be success
    The stdout should include "elapsed"
  End

  Describe "budget_check functional test"
    setup() {
      spec_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/valkey-budget-spec.XXXXXX")
      cat > "${spec_tmp_dir}/budget_test.sh" <<'SCRIPT'
#!/bin/bash
SECONDS=100
POSTPROVISION_DEADLINE=50
budget_check() {
  if [ "$SECONDS" -ge "$POSTPROVISION_DEADLINE" ]; then
    echo "ERROR: postProvision budget exhausted (${SECONDS}s elapsed, limit 45s)" >&2
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

    It "exits 1 when SECONDS exceeds deadline"
      When run bash "${spec_tmp_dir}/budget_test.sh"
      The status should equal 1
      The stderr should include "budget exhausted"
      The stdout should be blank
    End
  End
End
