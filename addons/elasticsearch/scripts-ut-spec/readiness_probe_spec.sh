# shellcheck shell=bash
# shellcheck disable=SC2034

# Validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "es_readiness_probe_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Elasticsearch Readiness Probe Script Tests"
  # Load the script to be tested
  Include ../scripts/readiness-probe-script.sh

  init() {
    ut_mode="true"
    export PROBE_USERNAME="testuser"
    export PROBE_PASSWORD_FILE="./probe_password"
    export PROBE_PASSWORD_PATH="${PROBE_PASSWORD_FILE}"
    export POD_IP="127.0.0.1"
    echo "testpassword" > "${PROBE_PASSWORD_FILE}"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${PROBE_PASSWORD_FILE}"
  }
  AfterAll 'cleanup'

  un_setup() {
    # Reset environment variables and state before each test
    unset PROBE_USERNAME
    unset PROBE_PASSWORD_FILE
    unset PROBE_PASSWORD_PATH
    unset POD_IP
  }

  Describe "log_failure()"
    It "logs error details and exits with code 1"
      When run log_failure '{"error": "some error occurred"}'
      The output should include "readiness probe failed"
      The status should be failure
    End
  End

  Describe "get_probe_password_path()"
    It "returns the correct password path"
      un_setup
      export PROBE_PASSWORD_PATH="/custom/path"
      When run get_probe_password_path
      The output should equal "/custom/path"
      The status should be success
    End

    It "falls back to PROBE_PASSWORD_FILE if PROBE_PASSWORD_PATH is not set"
      un_setup
      export PROBE_PASSWORD_FILE="/default/path"
      When run get_probe_password_path
      The output should equal "${PROBE_PASSWORD_FILE}"
      The status should be success
    End
  End

  Describe "setup_auth()"
    It "sets up authentication correctly"
      get_probe_password_path() {
        echo "${PROBE_PASSWORD_FILE}"
      }
      un_setup
      export PROBE_PASSWORD_FILE="./probe_password"
      touch "${PROBE_PASSWORD_FILE}"
      export PROBE_USERNAME="testuser"
      echo "testpassword" > "${PROBE_PASSWORD_FILE}"
      When run setup_auth
      The output should equal "-u testuser:testpassword"
      The status should be success
    End

    It "returns an empty string if username is not set"
      un_setup
      unset PROBE_USERNAME
      When run setup_auth
      The output should equal ""
      The status should be success
    End

    It "returns an empty string if password file does not exist"
      un_setup
      export PROBE_USERNAME="testuser"
      export PROBE_PASSWORD_FILE="/invalid/path"
      When run setup_auth
      The output should equal ""
      The status should be success
    End
  End

  Describe "get_loopback_address()"
    It "returns IPv4 loopback address when POD_IP is not IPv6"
      un_setup
      export POD_IP="127.0.0.1"
      When run get_loopback_address
      The output should equal "127.0.0.1"
      The status should be success
    End

    It "returns IPv6 loopback address when POD_IP is IPv6"
      un_setup
      export POD_IP="::1"
      When run get_loopback_address
      The output should equal "[::1]"
      The status should be success
    End
  End

  Describe "check_elasticsearch()"
    It "logs failure if curl command fails"
      un_setup
      curl() {
        return 1  # Simulate curl failure
      }
      When run check_elasticsearch "http://127.0.0.1:9200/" "" "1"
      The stdout should be present
      The status should be failure
    End

    It "logs failure if status code is not 200"
      un_setup
      curl() {
        echo "HTTP/1.1 500 Internal Server Error"  # Simulate a 500 error
        return 0
      }
      DEFAULT_TIMEOUT=1
      When run check_elasticsearch "http://127.0.0.1:9200/" "" "$DEFAULT_TIMEOUT"
      The output should include "readiness probe failed"
      The status should be failure
    End
  End
End