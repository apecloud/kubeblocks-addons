# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "check_bookies_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Pulsar Check Bookies Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/check-bookies.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "apply_config_from_env()"
    It "applies configuration from environment variables"
      # mock command to apply configuration from environment variables
      bin/apply-config-from-env.py() {
        return 0
      }

      When call apply_config_from_env
      The output should include "Applying configuration from environment variables:"
      The output should include "  - Command: bin/apply-config-from-env.py conf/bookkeeper.conf"
      The status should be success
    End
  End

  Describe "wait_for_bookkeeper()"
    It "waits for bookkeeper to start"
      # mock command to check if bookkeeper instance id is available
      bin/bookkeeper() {
        if [ "$1" = "shell" ] && [ "$2" = "whatisinstanceid" ]; then
          return 0
        fi
        return 1
      }

      When run wait_for_bookkeeper
      The output should include "Waiting for bookkeeper to start..."
      The output should include "Bookkeeper started successfully"
      The status should be success
    End
  End

  Describe "set_tcp_keepalive()"
    It "sets TCP keepalive parameters"
      sysctl() {
        return 0
      }

      When run set_tcp_keepalive
      The output should include "Setting TCP keepalive parameters:"
      The output should include "  - net.ipv4.tcp_keepalive_time=1"
      The output should include "  - net.ipv4.tcp_keepalive_intvl=11"
      The output should include "  - net.ipv4.tcp_keepalive_probes=3"
      The status should be success
    End
  End
End