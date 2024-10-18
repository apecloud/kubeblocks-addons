# shellcheck shell=bash
# shellcheck disable=SC2034


# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
# if ! validate_shell_type_and_version "bash" &>/dev/null; then
#   echo "mongodb replicaset_setup_spec.sh skip all cases because dependency bash is not installed."
#   exit 0
# fi

Describe "ProxySQL Entry Script Tests"

    init() {
        TEST_DATA_DIR="./test_data"
        export FRONTEND_TLS_ENABLED="false"
    }
    BeforeAll "init"

    cleanup() {
        rm -rf $TEST_DATA_DIR
    }
    AfterAll 'cleanup'

    Describe "Run proxysql-entry.sh with FRONTEND_TLS_ENABLED=false"

        It "runs successfully"
            When run source ../scripts/proxysql-entry.sh
            The status should be failure
            The stdout should include "Configuring proxysql ..."
            The stderr should include "/scripts/proxysql/configure-proxysql.sh: No such file or directory"
        End
    End


  Describe "Log Function Tests"
    Include ../scripts/proxysql-entry.sh

    It "outputs a log message"
      When call log "INFO" "Test log message"
      The status should be success
      The stdout should include "INFO"
      The stdout should include "Test log message"
    End
  End

End