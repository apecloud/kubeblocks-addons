# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 >/dev/null 2>&1; then
  echo "data-dump_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Etcd Data Dump Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
    # Mock the data_dump function for the test
    data_dump() {
      sleep 1
    }
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
    unset ut_mode
    unset -f data_dump
  }
  AfterAll 'cleanup'

  Describe "data_dump() function"
    It "executes successfully"
      start_time=$(date +%s)
      data_dump
      end_time=$(date +%s)
      elapsed=$((end_time - start_time))
      The variable elapsed should equal 1
    End
  End
End
