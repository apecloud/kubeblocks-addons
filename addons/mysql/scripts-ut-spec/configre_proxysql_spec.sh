# shellcheck shell=bash
# shellcheck disable=SC2034

# shellcheck shell=bash

Describe "ProxySQL Configuration Script Tests"
  Include ../scripts/configure-proxysql.sh

  Describe "Log Function Tests"

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

  Describe "Secret Hygiene Tests"
    It "does not pass the MySQL root password to log"
      When run grep -nE 'log .*MYSQL_ROOT_PASSWORD' ../scripts/configure-proxysql.sh
      The status should be failure
      The output should equal ""
    End
  End

  Describe "MySQL Exec Function Tests"

    verify_backend_argument_boundaries() {
      root=$(mktemp -d "${TMPDIR:-/tmp}/mysql-proxysql-argv.XXXXXX") || return 1

      (
        mysql() {
          : >"${MYSQL_ARGS}"
          for arg do
            printf '<%s>\n' "$arg" >>"${MYSQL_ARGS}"
          done
          printf '0\n'
        }
        export MYSQL_ARGS="${root}/mysql.args"
        export BACKEND_TLS_ENABLED="true"
        export MYSQL_ROOT_USER="root"
        export MYSQL_ROOT_PASSWORD='alpha beta[*]'
        export MYSQL_FQDNS="mysql-0"
        export MYSQL_PORT="3306"
        export BACKEND_SERVER="fallback"

        [ "$(get_writable_mysql_server)" = "mysql-0" ] \
          && grep -Fx '<--password=alpha beta[*]>' "${MYSQL_ARGS}" >/dev/null \
          && grep -Fx '<--ssl-ca=/var/lib/certs/ca.crt>' "${MYSQL_ARGS}" >/dev/null
      )
      status=$?

      rm -rf "${root}"
      return "${status}"
    }

    It "executes MySQL command successfully"
      mysql() {
        echo "MySQL command executed: $*"
        return 0
      }
      When call mysql_exec "root" "password" "localhost" "3306" "SELECT 1"
      The status should be success
      The stdout should match pattern "MySQL command executed: * SELECT 1"
    End

    It "fails to execute MySQL command"
      mysql() {
        echo "MySQL command failed: $*">&2
        return 1
      }
      When call mysql_exec "root" "password" "localhost" "3306" "INVALID COMMAND"
      The status should be failure
      The stderr should match pattern "MySQL command failed: * INVALID COMMAND"
    End

    It "preserves backend password and TLS options as single mysql arguments"
      When call verify_backend_argument_boundaries
      The status should be success
    End
  End

  Describe "Wait for MySQL Function Tests"
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
