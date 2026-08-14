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
  End

  Describe "ProxySQL User Configuration Tests"
    run_configure_proxysql_with_quoted_credentials() {
      local status
      MYSQL_SQL_LOG=$(mktemp)
      export MYSQL_SQL_LOG

      mysql() {
        local arg
        for arg in "$@"; do
          case "$arg" in
            *"insert or replace into mysql_users"*)
              printf '%s\n' "$arg" >> "$MYSQL_SQL_LOG"
              ;;
          esac
        done

        case "$*" in
          *"select 1;"*) printf '1\n' ;;
          *"super_read_only"*) printf '0\n' ;;
          *"group_replication_group_name"*) printf 'NULL\n' ;;
          *"@@version"*) printf '8.0.0\n' ;;
        esac
      }
      export -f mysql

      MYSQL_ROOT_USER="ro'ot"
      MYSQL_ROOT_PASSWORD="pa'ss"
      PROXYSQL_ADMIN_PASSWORD=admin
      BACKEND_SERVER=mysql-0
      MYSQL_FQDNS=mysql-0
      MYSQL_PORT=3306
      BACKEND_TLS_ENABLED=false
      export MYSQL_ROOT_USER MYSQL_ROOT_PASSWORD PROXYSQL_ADMIN_PASSWORD
      export BACKEND_SERVER MYSQL_FQDNS MYSQL_PORT BACKEND_TLS_ENABLED

      bash ../scripts/configure-proxysql.sh >/dev/null 2>&1
      status=$?
      cat "$MYSQL_SQL_LOG"
      rm -f "$MYSQL_SQL_LOG"
      return "$status"
    }

    It "escapes root credentials used as SQL literals"
      When call run_configure_proxysql_with_quoted_credentials
      The status should be success
      The stdout should include "values ('ro''ot','pa''ss',1)"
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
