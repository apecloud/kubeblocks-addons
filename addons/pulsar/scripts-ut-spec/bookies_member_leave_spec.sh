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

  Describe "format_bookie()"
    It "formats bookie with force and deleteCookie"
      bin/bookkeeper() {
        if [ "$1" = "shell" ] && [ "$2" = "bookieformat" ] && [ "$3" = "-nonInteractive" ] && [ "$4" = "-force" ] && [ "$5" = "-deleteCookie" ]; then
          echo "Bookie formatted with force and deleteCookie"
          return 0
        fi
        return 1
      }

      When call format_bookie "true" "true"
      The output should include "Formatting Bookie..."
      The output should include "Bookie formatted with force and deleteCookie"
      The status should be success
    End

    It "formats bookie without force and deleteCookie"
      bin/bookkeeper() {
        if [ "$1" = "shell" ] && [ "$2" = "bookieformat" ] && [ "$3" = "-nonInteractive" ]; then
          echo "Bookie formatted"
          return 0
        fi
        return 1
      }

      When call format_bookie "false" "false"
      The output should include "Formatting Bookie..."
      The output should include "Bookie formatted"
      The status should be success
    End
  End

  Describe "should_format_bookie()"
    It "returns true when pod index is greater than or equal to replicas"
      When call should_format_bookie "pod-3" "2"
      The status should be success
    End

    It "returns false when pod index is less than replicas"
      When call should_format_bookie "pod-1" "2"
      The status should be failure
    End
  End

  Describe "bookies_member_leave()"
    setup() {
      export CURRENT_POD_NAME="pod-3"
      export BOOKKEEPER_COMP_REPLICAS="2"
    }

    It "formats bookie when condition is met"
      setup

      format_bookie() {
        echo "format_bookie called with $1 $2"
      }

      When call bookies_member_leave
      The output should include "format_bookie called with true true"
    End

    It "skips formatting when condition is not met"
      export CURRENT_POD_NAME="pod-1"
      export BOOKKEEPER_COMP_REPLICAS="2"

      When call bookies_member_leave
      The output should include "Skipping Bookie formatting"
    End
  End
End