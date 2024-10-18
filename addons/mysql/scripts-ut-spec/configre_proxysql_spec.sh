# shellcheck shell=bash
# shellcheck disable=SC2034

# shellcheck shell=bash

Describe "ProxySQL Configuration Script Tests"

  Describe "Log Function Tests"
    Include ../scripts/configure-proxysql.sh

    It "outputs a log message"
      When call log "INFO" "Test log message"
      The status should be success
      The stdout should include "Test log message"
    End

    It "outputs a correctly formatted log message"
      When call log "INFO" "Test log message"
      The status should be success
      The stdout should match pattern "*[0-9][0-9]/[0-9][0-9]/[0-9][0-9]*"
    End
  End

  Describe "MySQL Exec Function Tests"
    Include ../scripts/configure-proxysql.sh

    It "executes MySQL command successfully"
      mysql() {
        echo "MySQL command executed: "$@ 
        return 0
      }
      When call mysql_exec "root" "password" "localhost" "3306" "SELECT 1"
      The status should be success
      The stdout should match pattern "MySQL command executed: * SELECT 1"
    End

    It "fails to execute MySQL command"
      mysql() {
        echo "MySQL command failed: "$@>&2
        return 1
      }
      When call mysql_exec "root" "password" "localhost" "3306" "INVALID COMMAND"
      The status should be failure
      The stderr should match pattern "MySQL command failed: * INVALID COMMAND"
    End
  End

  Describe "Wait for MySQL Function Tests"
    Include ../scripts/configure-proxysql.sh
    setup() {
      # Mock the mysql_exec function to simulate MySQL responses
      mysql_exec() {
        if [ "$5" == "select 1;" ]; then
          echo "1"
          return 0
        else
          return 1
        fi
      }
    }
    Before 'setup'

    It "waits for MySQL to be online"
      When call wait_for_mysql "root" "password" "localhost" "3306"
      The output should include "Waiting for host localhost to be online ..."
      The status should be success
    End

    # no test for this case, as it will abort
    # It "fails to wait for MySQL to be online"
    #   mysql_exec() {
    #     echo failed
    #     return 1
    #   }
    #   sleep() {
    #   }

    #   When call wait_for_mysql "root" "password" "localhost" "3306"
    #   The output should include "Server localhost start failed ..."
    #   The status should be failure
    # End
  End
End