# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "start_bookies_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Pulsar Start Bookies Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/start-bookies.sh
  Include $common_library_file

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "merge_configs()"
    It "merges configuration files"
      python3() {
        echo "$1 $2 $3"
      }

      bin/apply-config-from-env.py() {
        return 0
      }

      When run merge_configs
      The output should include "/kb-scripts/merge_pulsar_config.py"
      The output should include "conf/bookkeeper.conf"
      The output should include "/opt/pulsar/conf/bookkeeper.conf"
      The status should be success
    End
  End

  Describe "get_directory()"
    It "retrieves directory value from the configuration file"
      grep() {
        echo "zkLedgersRootPath=/ledgers"
      }

      When call get_directory "journalDirectories"
      The output should equal "/ledgers"
    End
  End

  Describe "create_directories()"
    It "creates necessary directories"
      mkdir() {
        echo "Creating directories"
      }

      When run create_directories "/var/pulsar/journal" "/var/pulsar/ledgers"
      The output should include "Creating directories"
      The status should be success
    End
  End

  Describe "check_empty_directories()"
    It "checks if both directories are empty"
      ls() {
        return 1  # Simulates empty directory
      }

      When call check_empty_directories "/var/pulsar/journal" "/var/pulsar/ledgers"
      The status should be success
    End
  End

  Describe "handle_empty_directories()"
    It "handles the case when both directories are empty"
      get_target_pod_fqdn_from_pod_fqdn_vars() {
        echo "pod.example.com"
      }

      zkURL="zookeeper.example.com"

      When run handle_empty_directories
      The stderr should include "Error: BOOKKEEPER_POD_FQDN_LIST or CURRENT_POD_NAME or zkServers is empty. Exiting."
      The stdout should include "journalRes and ledgerRes directory is empty, check whether the remote cookies is empty either"
      The status should be failure
    End

    It "removes redundant bookieID if necessary"
      BOOKKEEPER_POD_FQDN_LIST="pod1,pod2"
      CURRENT_POD_NAME="pod1"
      zkServers="pod1.svc.cluster.local"

      get_target_pod_fqdn_from_pod_fqdn_vars() {
        echo "pod1.example.com"
      }

      python3() {
        return 0  # Simulates successful command
      }

      grep() {
        echo "zkLedgersRootPath=/ledgers"
      }

      When run handle_empty_directories
      The output should include "Warning: exist redundant bookieID"
      The status should be success
    End
  End
End