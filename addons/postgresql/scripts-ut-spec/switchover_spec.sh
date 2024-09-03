# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "switchover_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "PostgreSQL Switchover Script Tests"

  Include ../scripts/switchover.sh
  Include $common_library_file

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "switchover()"
    Context "when CURRENT_POD_NAME or POSTGRES_PRIMARY_POD_NAME is not set"
      setup() {
        unset CURRENT_POD_NAME
        unset POSTGRES_PRIMARY_POD_NAME
      }
      Before 'setup'

      It "exits with an error"
        When run switchover
        The output should include "CURRENT_POD_NAME or POSTGRES_PRIMARY_POD_NAME is not set. Exiting..."
        The status should be failure
      End
    End

    Context "when POSTGRES_PRIMARY_POD_NAME is not unique"
      setup() {
        CURRENT_POD_NAME="pod1"
        POSTGRES_PRIMARY_POD_NAME="pod1,pod2"
      }
      Before 'setup'

      It "exits with an error"
        When run switchover
        The output should include "Error: POSTGRES_PRIMARY_POD_NAME should be a unique pod name. Exiting."
        The status should be failure
      End
    End

    Context "when POSTGRES_POD_NAME_LIST or POSTGRES_POD_FQDN_LIST is not set"
      setup() {
        CURRENT_POD_NAME="pod1"
        POSTGRES_PRIMARY_POD_NAME="pod1"
        unset POSTGRES_POD_NAME_LIST
        unset POSTGRES_POD_FQDN_LIST
      }
      Before 'setup'

      It "exits with an error"
        When run switchover
        The output should include "POSTGRES_POD_NAME_LIST or POSTGRES_POD_FQDN_LIST is not set. Exiting..."
        The status should be failure
      End
    End

    Context "when the current pod FQDN is not found"
      setup() {
        CURRENT_POD_NAME="pod1"
        POSTGRES_PRIMARY_POD_NAME="pod1"
        POSTGRES_POD_NAME_LIST="pod2,pod3"
        POSTGRES_POD_FQDN_LIST="pod2.example.com,pod3.example.com"
      }
      Before 'setup'

      It "exits with an error"
        When run switchover
        The output should include "Error: Failed to get current pod: pod1 fqdn from postgres pod fqdn list: pod2.example.com,pod3.example.com. Exiting."
        The status should be failure
      End
    End

    Context "when KB_SWITCHOVER_CANDIDATE_NAME is set"
      setup() {
        CURRENT_POD_NAME="pod1"
        POSTGRES_PRIMARY_POD_NAME="pod1"
        POSTGRES_POD_NAME_LIST="pod1,pod2"
        POSTGRES_POD_FQDN_LIST="pod1.example.com,pod2.example.com"
        KB_SWITCHOVER_CANDIDATE_NAME="pod2"
      }
      Before 'setup'

      It "calls switchover_with_candidate"
        switchover_with_candidate() {
          echo "Calling switchover_with_candidate with arguments: $1 $2 $3"
        }
        When run switchover
        The output should include "Calling switchover_with_candidate with arguments: pod1.example.com pod1 pod2"
      End
    End

    Context "when KB_SWITCHOVER_CANDIDATE_NAME is not set"
      setup() {
        CURRENT_POD_NAME="pod1"
        POSTGRES_PRIMARY_POD_NAME="pod1"
        POSTGRES_POD_NAME_LIST="pod1,pod2"
        POSTGRES_POD_FQDN_LIST="pod1.example.com,pod2.example.com"
        unset KB_SWITCHOVER_CANDIDATE_NAME
      }
      Before 'setup'

      It "calls switchover_without_candidate"
        switchover_without_candidate() {
          echo "Calling switchover_without_candidate with arguments: $1 $2"
        }
        When run switchover
        The output should include "Calling switchover_without_candidate with arguments: pod1.example.com pod1"
      End
    End
  End
End