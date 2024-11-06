# shellcheck shell=bash
# shellcheck disable=SC2034

# Validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "nebula_post_start_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Nebula Post Start Script Tests"
  # Load the script to be tested
  Include ../scripts/post-start.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  setup_environment() {
    export GRAPHD_SVC_NAME="graphd-service"
    export GRAPHD_SVC_PORT="3699"
    export POD_FQDN="nebula-storaged-0.nebula-storaged.default.svc.cluster.local"
  }

  Describe "execute_nebula_show_space()"
    setup_environment

    It "executes nebula-console show space command successfully"
      # Mock nebula-console command
      /usr/local/bin/nebula-console() {
        echo "addr: $2"
        echo "port: $4"
        echo "user: $6"
        echo "password: $8"
        echo "cmd: ${10}"
        return 0
      }

      When call execute_nebula_show_space
      The output should include "addr: graphd-service"
      The output should include "port: 3699"
      The output should include "user: root"
      The output should include "password: nebula"
      The output should include "cmd: show spaces"
      The status should be success
    End

    It "fails to execute nebula-console command"
      /usr/local/bin/nebula-console() {
        return 1
      }

      When call execute_nebula_show_space
      The stderr should include "Failed to execute nebula-console show spaces command"
      The status should be failure
    End
  End

  Describe "add_storage_host()"
    setup_environment

    It "adds storage host successfully"
      # Mock nebula-console command
      /usr/local/bin/nebula-console() {
        return 0
      }

      When call add_storage_host
      The output should include "Add storage host command: ADD HOSTS \"nebula-storaged-0.nebula-storaged.default.svc.cluster.local\":9779"
      The status should be success
    End

    It "fails to add storage host"
      /usr/local/bin/nebula-console() {
        return 1
      }

      When call add_storage_host
      The stderr should include "Failed to add storage host"
      The output should include "Add storage host command: ADD HOSTS \"nebula-storaged-0.nebula-storaged.default.svc.cluster.local\":9779"
      The status should be failure
    End
End