# shellcheck shell=bash
# shellcheck disable=SC2034


# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
# if ! validate_shell_type_and_version "bash" &>/dev/null; then
#   echo "apecloud mysql setup_spec.sh skip all cases because dependency bash is not installed."
#   exit 0
# fi


Describe "ApeCloud MySQL Startup Script Tests"

  init() {
    START_SUCCESS_FILE=./success
    MY_POD_NAME="cluster-mongodb-0"
    MY_POD_LIST=wesql1-mysql-0,wesql1-mysql-1,wesql1-mysql-2
    MY_COMP_REPLICAS=3
    MY_COMP_NAME=mysql
    MY_CLUSTER_NAME=wesql1
    MY_CLUSTER_UID=c3636ff1-bb54-47a4-ac4e-111ba9b41295
    KB_SERVICE_CHARACTER_TYPE=wesql
    KB_MYSQL_VOLUME_DIR=.
  }
  BeforeAll "init"

  cleanup() {
    rm -rf $START_SUCCESS_FILE
  }
  AfterAll 'cleanup'

  Describe "start apecloud mysql"
    It "start successfully"
      exec() {
        touch $START_SUCCESS_FILE
        echo "$@"
      }

      rmdir() {
        echo "rmdir $@">&2
      }

      ln() {
        echo "ln $@">&2
      }

      When run source ../scripts/setup.sh
      The path "$KB_MYSQL_VOLUME_DIR/binlog" should be directory
      The path "$KB_MYSQL_VOLUME_DIR/auditlog" should be directory
      The path "$KB_MYSQL_VOLUME_DIR/docker-entrypoint-initdb.d" should be directory
      The path "$START_SUCCESS_FILE" should be file
      The status should be success
      The output should include "docker-entrypoint.sh"
      The stderr should include "rmdir /docker-entrypoint-initdb.d"
      The stderr should include "ln -s"

      # Can not refer to variables inside the shell script
      # The variable MONGODB_ROOT should be defined
    End

    It "start failed"
      exec() {
        echo "$@">&2
        return 1
      }

      rmdir() {
        echo "rmdir $@">&2
      }

      ln() {
        echo "ln $@">&2
      }

      When run source ../scripts/setup.sh
      The status should be failure
      The stderr should be present
      The stdout should be present

      # Can not refer to variables inside the shell script
      # The variable MONGODB_ROOT should be defined
    End
  End
End

Describe "get_service_name function"
  Include ../scripts/setup.sh
  setup() {
    MY_COMP_NAME=mysql
    MY_CLUSTER_NAME=wesql1
  }
  Before "setup"
  It "returns the correct service name"
    When call get_service_name
    The output should equal "wesql1-mysql-headless"
  End
End

Describe "get_cluster_members function"
  Include ../scripts/setup.sh
  setup() {
    MY_POD_LIST="pod1,pod2,pod3"
    MY_COMP_NAME=mysql
    MY_CLUSTER_NAME=wesql1
    MYSQL_CONSENSUS_PORT=13306
  }
  Before "setup"
  It "returns the correct cluster members"
    When call get_cluster_members
    The output should equal "pod1.wesql1-mysql-headless:13306;pod2.wesql1-mysql-headless:13306;pod3.wesql1-mysql-headless:13306"
  End
End

Describe "get_pod_index function"
  Include ../scripts/setup.sh
  setup() {
    MY_POD_LIST="pod1,pod2,pod3"
  }
  Before "setup"
  It "returns the correct pod index"
    When call get_pod_index "pod2"
    The output should equal "1"
  End
End

Describe "generate_cluster_info function"
  Include ../scripts/setup.sh
  setup() {
    MY_POD_NAME="pod1"
    MY_POD_LIST="pod1,pod2,pod3"
    MY_COMP_NAME=mysql
    MY_CLUSTER_NAME=wesql1
    MY_COMP_REPLICAS=3
    MY_CLUSTER_UID="test-uid"
  }
  Before "setup"
  It "sets the correct environment variables"
    When call generate_cluster_info
    The variable KB_MYSQL_N should equal "3"
    The variable KB_MYSQL_CLUSTER_UID should equal "test-uid"
    The variable KB_MYSQL_CLUSTER_MEMBERS should equal "pod1.wesql1-mysql-headless:13306;pod2.wesql1-mysql-headless:13306;pod3.wesql1-mysql-headless:13306"
    The variable KB_MYSQL_CLUSTER_MEMBER_INDEX should equal "0"
    The variable KB_MYSQL_CLUSTER_MEMBER_HOST should equal "pod1.wesql1-mysql-headless"
    The stdout should be present
  End
End

