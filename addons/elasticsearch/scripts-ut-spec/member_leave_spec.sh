# shellcheck shell=bash
# shellcheck disable=SC2034

# Validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "es_member_leave_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Elasticsearch Member Leave Script Tests"
  # Load the script to be tested
  Include ../scripts/member-leave.sh

  init() {
    ut_mode="true"
    export KB_LEAVE_MEMBER_POD_NAME="test-pod"
    ENDPOINT="http://127.0.0.1:9200"
    CURL_OPTIONS="--fail --max-time 3 --retry 3"
  }
  BeforeAll "init"

  un_setup() {
    # Reset environment variables and state before each test
    unset KB_LEAVE_MEMBER_POD_NAME
    unset ENDPOINT
    unset CURL_OPTIONS
  }

  Describe "init_vars()"
    It "exits if KB_LEAVE_MEMBER_POD_NAME is not set"
      un_setup
      When call init_vars
      The variable ENDPOINT should equal "http://127.0.0.1:9200"
      The output should include "KB_LEAVE_MEMBER_POD_NAME is not set, exiting"
      The status should be failure
    End

    It "initializes variables correctly"
      un_setup
      export KB_LEAVE_MEMBER_POD_NAME="test-pod"
      When call init_vars
      The variable ENDPOINT should equal "http://127.0.0.1:9200"
      The status should be success
    End
  End

  Describe "get_es_version()"
    It "successfully retrieves the Elasticsearch version"
      un_setup
      export KB_LEAVE_MEMBER_POD_NAME="test-pod"
      curl() {
        echo '{"version":{"number":"7.9.1"}}'  # Mocked Elasticsearch response
        return 0
      }
      When run get_es_version
      The output should equal "7.9"
      The status should be success
    End

    It "handles failure in retrieving Elasticsearch version"
      un_setup
      export KB_LEAVE_MEMBER_POD_NAME="test-pod"
      curl() {
        return 1  # Simulate curl failure
      }
      When run get_es_version
      The output should include "failed to get es version"
      The status should be failure
    End
  End

  Describe "get_exclusion_url()"
    It "returns the correct exclusion URL for version < 7.8"
      un_setup
      export ENDPOINT="http://127.0.0.1:9200"
      export KB_LEAVE_MEMBER_POD_NAME="test-pod"
      When run get_exclusion_url "7.7"
      The output should equal "http://127.0.0.1:9200/_cluster/voting_config_exclusions/test-pod"
      The status should be success
    End

    It "returns the correct exclusion URL for version >= 7.8"
      un_setup
      export ENDPOINT="http://127.0.0.1:9200"
      export KB_LEAVE_MEMBER_POD_NAME="test-pod"
      When run get_exclusion_url "7.8"
      The output should equal "http://127.0.0.1:9200/_cluster/voting_config_exclusions?node_names=test-pod"
      The status should be success
    End
  End

  Describe "clear_exclusions()"
    It "successfully clears voting config exclusions"
      un_setup
      curl() {
        return 0  # Simulate successful clear
      }
      When run clear_exclusions
      The output should include "successfully cleared voting config exclusions"
      The status should be success
    End

    It "handles failure in clearing voting config exclusions"
      un_setup
      curl() {
        return 1  # Simulate failure
      }
      When run clear_exclusions
      The output should include "failed to clear voting config exclusions"
      The status should be failure
    End
  End

  Describe "add_node_to_exclusions()"
    It "successfully adds a node to the exclusion list"
      un_setup
      curl() {
        return 0  # Simulate successful addition
      }
      export KB_LEAVE_MEMBER_POD_NAME="test-pod"
      When run add_node_to_exclusions "http://127.0.0.1:9200/_cluster/voting_config_exclusions?node_names=test-pod"
      The output should include "successfully added node test-pod to voting config exclusion list"
      The status should be success
    End

    It "handles failure in adding a node to the exclusion list"
      un_setup
      curl() {
        return 1  # Simulate failure
      }
      export KB_LEAVE_MEMBER_POD_NAME="test-pod"
      When run add_node_to_exclusions "http://127.0.0.1:9200/_cluster/voting_config_exclusions?node_names=test-pod"
      The output should include "failed to add node test-pod to voting config exclusion list"
      The status should be failure
    End
  End

  Describe "member_leave()"
    It "executes the member leaving process successfully"
      un_setup
      export KB_LEAVE_MEMBER_POD_NAME="test-pod"
      curl() {
        echo '{"version":{"number":"7.9.1"}}'  # Mock Elasticsearch version response
        return 0
      }
      When run member_leave
      The output should include "removing node test-pod"
      The status should be success
    End

    It "handles failure in initialization"
      un_setup
      unset KB_LEAVE_MEMBER_POD_NAME  # Simulate missing pod name
      When run member_leave
      The output should include "KB_LEAVE_MEMBER_POD_NAME is not set, exiting"
      The status should be failure
    End
  End
End