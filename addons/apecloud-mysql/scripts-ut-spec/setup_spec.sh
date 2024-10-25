# shellcheck shell=bash
# shellcheck disable=SC2034


# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
# if ! validate_shell_type_and_version "bash" &>/dev/null; then
#   echo "apecloud mysql setup_spec.sh skip all cases because dependency bash is not installed."
#   exit 0
# fi


Describe "ApeCloud MySQL Startup Script Tests"

  init() {
  }
  BeforeAll "init"

  cleanup() {
    rm -rf $DATA_VOLUME
  }
  AfterAll 'cleanup'

  Describe "start replicaset without backup file"
    setup() {
      KB_CLUSTER_COMP_NAME=wesql1-mysql
      KB_COMP_REPLICAS=3
      KB_SERVICE_CHARACTER_TYPE=wesql
      KB_COMP_NAME=mysql
      KB_EMBEDDED_WESQL=1
      KB_CLUSTER_NAME=wesql1
      KB_NAMESPACE=default
      KB_CLUSTER_UID=c3636ff1-bb54-47a4-ac4e-111ba9b41295
      KB_MYSQL_VOLUME_DIR=./
      MY_POD_NAME="cluster-mongodb-0"
      MY_POD_LIST=wesql1-mysql-0,wesql1-mysql-1,wesql1-mysql-2
    }
    Before 'setup'

    un_setup() {
      unalias exec1
    }
    After 'un_setup'

    It "start successfully"
      exec() {
        touch $START_SUCCESS_FILE
        echo "$@"
      }

      When run source ../scripts/setup.sh
      The path "$KB_MYSQL_VOLUME_DIR/binlog" should be directory
      The path "$KB_MYSQL_VOLUME_DIR/auditlog" should be directory
      The path "$KB_MYSQL_VOLUME_DIR/docker-entrypoint-initdb.d" should be directory
      The path "$START_SUCCESS_FILE" should be file
      The status should be success
      The output should include "docker-entrypoint.sh"

      # Can not refer to variables inside the shell script
      # The variable MONGODB_ROOT should be defined
    End

    It "start failed"
      exec() {
        echo "$@">&2
        return 1
      }

      When run source ../scripts/replicaset-setup.tpl
      The status should be failure
      The stderr should be present

      # Can not refer to variables inside the shell script
      # The variable MONGODB_ROOT should be defined
    End
  End

  Describe "get_service_name function"
    It "returns the correct service name"
      KB_CLUSTER_COMP_NAME="test-cluster"
      When call get_service_name
      The output should equal "test-cluster-headless"
    End
  End

  Describe "get_cluster_members function"
    It "returns the correct cluster members"
      MY_POD_LIST="pod1,pod2,pod3"
      KB_CLUSTER_COMP_NAME="test-cluster"
      MYSQL_CONSENSUS_PORT=13306
      When call get_cluster_members
      The output should equal "pod1.test-cluster-headless:13306;pod2.test-cluster-headless:13306;pod3.test-cluster-headless:13306"
    End
  End

  Describe "get_pod_index function"
    It "returns the correct pod index"
      MY_POD_LIST="pod1,pod2,pod3"
      When call get_pod_index "pod2"
      The output should equal "1"
    End
  End

  Describe "generate_cluster_info function"
    It "sets the correct environment variables"
      MY_POD_NAME="pod1"
      MY_POD_LIST="pod1,pod2,pod3"
      KB_CLUSTER_COMP_NAME="test-cluster"
      KB_COMP_REPLICAS=3
      KB_CLUSTER_UID="test-uid"
      When call generate_cluster_info
      The variable KB_MYSQL_N should equal "3"
      The variable KB_MYSQL_CLUSTER_UID should equal "test-uid"
      The variable KB_MYSQL_CLUSTER_MEMBERS should equal "pod1.test-cluster-headless:13306;pod2.test-cluster-headless:13306;pod3.test-cluster-headless:13306"
      The variable KB_MYSQL_CLUSTER_MEMBER_INDEX should equal "0"
      The variable KB_MYSQL_CLUSTER_MEMBER_HOST should equal "pod1.test-cluster-headless"
    End
  End
End

