# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "bookies_member_leave_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Pulsar Bookies Member Leave Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/bookies-member-leave.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  bin/bookkeeper() {
    return 0
  }

  Describe "bookies_member_leave()"
    It "formats bookie when condition is met"
      export CURRENT_POD_NAME="pod-3"
      export KB_LEAVE_MEMBER_POD_NAME="pod-3"

      When call bookies_member_leave
      The output should include "Formatting Bookie..."
      The output should include "Bookie formatted"
    End

    It "skips formatting when condition is not met"
      export CURRENT_POD_NAME="pod-1"
      export KB_LEAVE_MEMBER_POD_NAME="pod-2"

      When call bookies_member_leave
      The output should include "Member to leave is not current pod, skipping Bookie formatting"
      The status should be failure
    End
  End
End