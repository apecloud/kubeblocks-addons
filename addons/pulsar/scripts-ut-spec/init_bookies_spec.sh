# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "init_bookies_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Pulsar Init Bookies Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/init-bookies.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "wait_for_zookeeper()"
    It "waits for Zookeeper to be ready"
      nc() {
        if [ "$1" = "-q" ] && [ "$2" = "1" ] && [ "$3" = "zookeeper.example.com" ] && [ "$4" = "2181" ]; then
          echo "imok"
        fi
      }

      When call wait_for_zookeeper "zookeeper.example.com:2181"
      The output should include "Waiting for Zookeeper at zookeeper.example.com:2181 to be ready..."
      The output should include "Zookeeper is ready"
    End
  End

  Describe "merge_bookkeeper_config()"
    It "merges Pulsar configuration files"
      python3() {
        echo "$1 $2 $3"
      }

      When run merge_bookkeeper_config
      The output should include "/kb-scripts/merge_pulsar_config.py"
      The output should include "Merging Pulsar configuration files:"
      The output should include "  - Source: conf/bookkeeper.conf"
      The output should include "  - Destination: /opt/pulsar/conf/bookkeeper.conf"
      The status should be success
    End
  End

  Describe "apply_config_from_env()"
    It "applies configuration from environment variables"
      bin/apply-config-from-env.py() {
        return 0
      }

      When run apply_config_from_env
      The output should include "Applying configuration from environment variables to conf/bookkeeper.conf"
      The status should be success
    End
  End

  Describe "init_bookkeeper_cluster()"
    It "initializes new BookKeeper cluster if not already initialized"
      bin/bookkeeper() {
        if [ "$1" = "shell" ] && [ "$2" = "whatisinstanceid" ]; then
          return 1
        elif [ "$1" = "shell" ] && [ "$2" = "initnewcluster" ]; then
          return 0
        fi
      }

      When run init_bookkeeper_cluster
      The output should include "Checking if BookKeeper cluster is already initialized..."
      The output should include "Initializing new BookKeeper cluster"
      The status should be success
    End

    It "skips initialization if BookKeeper cluster is already initialized"
      bin/bookkeeper() {
        if [ "$1" = "shell" ] && [ "$2" = "whatisinstanceid" ]; then
          return 0
        fi
      }

      When run init_bookkeeper_cluster
      The output should include "Checking if BookKeeper cluster is already initialized..."
      The output should include "BookKeeper cluster is already initialized"
      The status should be success
    End
  End

  Describe "init_bookies()"
    It "initializes bookies"
      export zkServers="zookeeper.example.com:2181"

      wait_for_zookeeper() {
        echo "wait_for_zookeeper called"
      }

      merge_bookkeeper_config() {
        echo "merge_bookkeeper_config called"
      }

      apply_config_from_env() {
        echo "apply_config_from_env called"
      }

      init_bookkeeper_cluster() {
        echo "init_bookkeeper_cluster called"
      }

      When run init_bookies
      The output should include "wait_for_zookeeper called"
      The output should include "merge_bookkeeper_config called"
      The output should include "apply_config_from_env called"
      The output should include "init_bookkeeper_cluster called"
    End

    It "exits with status 1 when zkServers environment variable is not set"
      unset zkServers

      When run init_bookies
      The output should include "Error: zkServers environment variable is not set, Please set the zkServers environment variable and try again."
      The status should be failure
    End
  End
End