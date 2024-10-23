# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "init_proxy_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Pulsar Init Proxy Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/init-proxy.sh

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

  Describe "main()"
    It "waits for Zookeeper when metadataStoreUrl is provided"
      export metadataStoreUrl="zookeeper.example.com:2181"

      wait_for_zookeeper() {
        echo "wait_for_zookeeper called with $1"
      }

      When run main
      The output should include "wait_for_zookeeper called with zookeeper.example.com:2181"
    End

    It "skips Zookeeper readiness check when metadataStoreUrl is not provided"
      unset metadataStoreUrl

      wait_for_zookeeper() {
        echo "wait_for_zookeeper called"
      }

      When run main
      The output should not include "wait_for_zookeeper called"
      The output should include "Zookeeper URL not provided, skipping Zookeeper readiness check"
    End
  End
End