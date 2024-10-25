# shellcheck shell=bash
# shellcheck disable=SC2034


# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
# if ! validate_shell_type_and_version "bash" &>/dev/null; then
#   echo "apecloud mysql setup_spec.sh skip all cases because dependency bash is not installed."
#   exit 0
# fi


Describe "ApeCloud MySQL Startup Script Tests"

  init() {
    KB_CLUSTER_COMP_NAME=wesql1-mysql
    KB_COMP_REPLICAS=3
    KB_SERVICE_CHARACTER_TYPE=wesql
    KB_COMP_NAME=mysql
    KB_EMBEDDED_WESQL=1
    KB_CLUSTER_NAME=wesql1
    KB_NAMESPACE=default
    KB_CLUSTER_UID=c3636ff1-bb54-47a4-ac4e-111ba9b41295
    KB_MYSQL_VOLUME_DIR=/data/mysql
    MY_POD_NAME="cluster-mongodb-0"
    MY_POD_LIST=wesql1-mysql-0,wesql1-mysql-1,wesql1-mysql-2
  }
  BeforeAll "init"

  cleanup() {
    rm -rf $DATA_VOLUME
  }
  AfterAll 'cleanup'

  Describe "start replicaset without backup file"
    setup() {
      alias exec1=exec1
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

      When run source ../scripts/replicaset-setup.tpl
      The path "$DATA_VOLUME/db" should be directory
      The path "$DATA_VOLUME/logs" should be directory
      The path "$DATA_VOLUME/tmp" should be directory
      The path "$START_SUCCESS_FILE" should be file
      The status should be success
      The output should include "mongod"

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
End