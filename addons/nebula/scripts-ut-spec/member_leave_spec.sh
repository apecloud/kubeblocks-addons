# shellcheck shell=bash
# shellcheck disable=SC2034

# Validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "nebula_member_leave_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Nebula Member Leave Script Tests"
  # Load the script to be tested
  Include ../scripts/member-leave.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  setup_environment() {
    export GRAPHD_SVC_NAME="graphd-service"
    export GRAPHD_SVC_PORT="3699"
    export KB_LEAVE_MEMBER_POD_NAME="pod-3"
    export STORAGED_COMPONENT_REPLICAS="2"
    export STORAGED_COMPONENT_NAME="storaged"
    export CLUSTER_NAMESPACE="default"
    export CUSTER_DOMAIN="cluster.local"
  }

  Describe "execute_nebula_command()"
    setup_environment

    It "executes nebula-console command successfully"
      # Mock nebula-console command
      /usr/local/bin/nebula-console() {
        echo "addr: $2"
        echo "port: $4"
        echo "user: $6"
        echo "password: $8"
        echo "file: ${10}"
        return 0
      }

      When call execute_nebula_command "host_file"
      The output should include "addr: graphd-service"
      The output should include "port: 3699"
      The output should include "user: root"
      The output should include "password: nebula"
      The output should include "file: host_file"
      The status should be success
    End

    It "fails to execute nebula-console command"
      /usr/local/bin/nebula-console() {
        return 1
      }

      When call execute_nebula_command "host_file"
      The stderr should include "Failed to execute nebula-console command"
      The status should be failure
    End
  End

  Describe "process_storage_cleanup()"
    setup_environment

    It "cleans up storage when condition is met"
      export KB_LEAVE_MEMBER_POD_NAME="pod-3"
      export STORAGED_COMPONENT_REPLICAS="2"

      execute_nebula_command() {
        echo "execute_nebula_command called"
        return 0
      }

      When call process_storage_cleanup
      The output should include "execute_nebula_command called"
      The status should be success
    End

    It "skips cleanup when condition is not met"
      export KB_LEAVE_MEMBER_POD_NAME="pod-1"
      export STORAGED_COMPONENT_REPLICAS="2"

      When call process_storage_cleanup
      The output should include "No need to clean up storage"
      The status should be success
    End
  End
End