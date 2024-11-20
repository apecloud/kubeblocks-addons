# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "startup_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "ZooKeeper Startup Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/startup.sh

  init() {
    myid_file="./myid"
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $myid_file;
  }
  AfterAll 'cleanup'

  Describe "set_zookeeper_server_id()"
    Context "when myid_file exists"
      setup() {
        echo "1" > $myid_file
      }
      Before "setup"

      un_setup() {
        rm -rf $myid_file
      }
      After "un_setup"

      It "sets ZOO_SERVER_ID from $myid_file"
        When call set_zookeeper_server_id
        The variable ZOO_SERVER_ID should eq "1"
      End
    End

    Context "when $myid_file does not exist"
      setup() {
        rm -rf $myid_file
        export CURRENT_POD_NAME="zookeeper-2"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_POD_NAME
      }
      After "un_setup"

      It "sets ZOO_SERVER_ID from CURRENT_POD_NAME and creates $myid_file"
        When call set_zookeeper_server_id
        The variable ZOO_SERVER_ID should eq "2"
        The contents of file "$myid_file" should eq "2"
      End
    End
  End

  Describe "compare_version()"
    It "returns true when v1 > v2"
      When call compare_version "gt" "3.5.0" "3.4.0"
      The status should be success
    End

    It "returns false when v1 <= v2"
      When call compare_version "gt" "3.4.0" "3.5.0"
      The status should be failure
    End

    It "returns true when v1 <= v2"
      When call compare_version "le" "3.4.0" "3.5.0"
      The status should be success
    End

    It "returns false when v1 > v2"
      When call compare_version "le" "3.5.0" "3.4.0"
      The status should be failure
    End

    It "returns true when v1 < v2"
      When call compare_version "lt" "3.4.0" "3.5.0"
      The status should be success
    End

    It "returns false when v1 >= v2"
      When call compare_version "lt" "3.5.0" "3.4.0"
      The status should be failure
    End

    It "returns true when v1 >= v2"
      When call compare_version "ge" "3.5.0" "3.4.0"
      The status should be success
    End

    It "returns false when v1 < v2"
      When call compare_version "ge" "3.4.0" "3.5.0"
      The status should be failure
    End
  End

End