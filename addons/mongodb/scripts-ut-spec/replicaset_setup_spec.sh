# shellcheck shell=bash
# shellcheck disable=SC2034


# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
# if ! validate_shell_type_and_version "bash" &>/dev/null; then
#   echo "mongodb replicaset_setup_spec.sh skip all cases because dependency bash is not installed."
#   exit 0
# fi


Describe "Mongodb Startup Script Tests"

  init() {
    DATA_VOLUME="./mongodb_data"
    SYNCER_POD_NAME="cluster-mongodb-0"
    START_SUCCESS_FILE=$DATA_VOLUME/success
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