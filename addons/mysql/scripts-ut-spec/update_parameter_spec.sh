# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "MySQL update-parameter Script Tests"

  setup() {
    MYSQL_ADMIN_USER="kbadmin"
    MYSQL_ADMIN_PASSWORD="secret"
    MOCK_QUERY_FILE=$(mktemp)
  }
  cleanup() {
    rm -f "${MOCK_QUERY_FILE}"
  }
  BeforeEach "setup"
  AfterEach "cleanup"

  Describe "success path"
    mysql() {
      # last argument is the query
      eval "printf '%s' \"\${$#}\"" > "${MOCK_QUERY_FILE}"
      return 0
    }

    It "applies a plain numeric value and reports success"
      When run source ../scripts/update-parameter.sh max_connections 500
      The status should be success
      The stdout should include "Set parameter max_connections to value 500"
      The contents of file "${MOCK_QUERY_FILE}" should equal "SET GLOBAL max_connections = 500;"
    End

    It "converts size suffixes to bytes"
      When run source ../scripts/update-parameter.sh innodb_buffer_pool_size 128M
      The status should be success
      The stdout should include "Set parameter"
      The contents of file "${MOCK_QUERY_FILE}" should equal "SET GLOBAL innodb_buffer_pool_size = 134217728;"
    End

    It "quotes non-numeric values"
      When run source ../scripts/update-parameter.sh sql_mode NO_ENGINE_SUBSTITUTION
      The status should be success
      The stdout should include "Set parameter"
      The contents of file "${MOCK_QUERY_FILE}" should equal "SET GLOBAL sql_mode = 'NO_ENGINE_SUBSTITUTION';"
    End

    It "normalizes dashes to underscores"
      When run source ../scripts/update-parameter.sh max-connections 500
      The status should be success
      The stdout should include "Set parameter max_connections"
      The contents of file "${MOCK_QUERY_FILE}" should equal "SET GLOBAL max_connections = 500;"
    End
  End

  Describe "tolerated cannot-apply-online errors"
    It "tolerates ERROR 1238 (read-only variable) and says it applies after restart"
      mysql() {
        echo "ERROR 1238 (HY000) at line 1: Variable 'gtid_mode' is a read-only variable" >&2
        return 1
      }
      When run source ../scripts/update-parameter.sh gtid_mode ON
      The status should be success
      The stdout should include "read-only"
      The stdout should include "after the next restart"
    End

    It "tolerates ERROR 1193 for loose_-prefixed parameters (plugin not loaded)"
      mysql() {
        echo "ERROR 1193 (HY000): Unknown system variable 'audit_log_policy'" >&2
        return 1
      }
      When run source ../scripts/update-parameter.sh loose_audit_log_policy ALL
      The status should be success
      The stdout should include "skipped"
    End
  End

  Describe "real errors fail the action"
    It "fails on ERROR 1193 for a parameter without the loose_ prefix"
      mysql() {
        echo "ERROR 1193 (HY000): Unknown system variable 'no_such_variable'" >&2
        return 1
      }
      When run source ../scripts/update-parameter.sh no_such_variable 1
      The status should be failure
      The stderr should include "Failed to set parameter no_such_variable"
    End

    It "fails on ERROR 1231 (wrong value)"
      mysql() {
        echo "ERROR 1231 (42000): Variable 'innodb_flush_log_at_trx_commit' can't be set to the value of '9'" >&2
        return 1
      }
      When run source ../scripts/update-parameter.sh innodb_flush_log_at_trx_commit 9
      The status should be failure
      The stderr should include "Failed to set parameter"
    End

    It "fails on authentication error (ERROR 1045)"
      mysql() {
        echo "ERROR 1045 (28000): Access denied for user 'kbadmin'@'localhost'" >&2
        return 1
      }
      When run source ../scripts/update-parameter.sh max_connections 500
      The status should be failure
      The stderr should include "Failed to set parameter"
    End

    It "fails when the server is unreachable"
      mysql() {
        echo "ERROR 2003 (HY000): Can't connect to MySQL server on '127.0.0.1:3306'" >&2
        return 1
      }
      When run source ../scripts/update-parameter.sh max_connections 500
      The status should be failure
      The stderr should include "Failed to set parameter"
    End
  End

  Describe "MySQL 8.4 removed-variable rejection"
    # mysql mock that answers SELECT VERSION() with the configured version and
    # records / succeeds any SET GLOBAL. The tail argument is the SQL query.
    mock_mysql_version() {
      local version="$1"; shift
      local q; eval "q=\"\${$#}\""
      case "$q" in
        *VERSION*) printf '%s\n' "$version" ;;
        *) printf '%s' "$q" > "${MOCK_QUERY_FILE}"; return 0 ;;
      esac
    }

    It "rejects a removed variable on MySQL 8.4 before SET GLOBAL"
      mysql() { mock_mysql_version "8.4.8" "$@"; }
      When run source ../scripts/update-parameter.sh expire_logs_days 1
      The status should be failure
      The stderr should include "removed in MySQL 8.4"
      # SET GLOBAL must not have been attempted for the removed variable.
      The contents of file "${MOCK_QUERY_FILE}" should not include "SET GLOBAL expire_logs_days"
    End

    It "rejects another removed variable (master_info_repository) on 8.4"
      mysql() { mock_mysql_version "8.4.8" "$@"; }
      When run source ../scripts/update-parameter.sh master_info_repository TABLE
      The status should be failure
      The stderr should include "removed in MySQL 8.4"
    End

    It "accepts a non-removed variable on MySQL 8.4"
      mysql() { mock_mysql_version "8.4.8" "$@"; }
      When run source ../scripts/update-parameter.sh max_connections 500
      The status should be success
      The stdout should include "Set parameter max_connections"
      The contents of file "${MOCK_QUERY_FILE}" should equal "SET GLOBAL max_connections = 500;"
    End

    It "does not reject the removed name on MySQL 8.0 (still a legal 8.0 variable)"
      mysql() { mock_mysql_version "8.0.33" "$@"; }
      When run source ../scripts/update-parameter.sh expire_logs_days 1
      The status should be success
      The stdout should include "Set parameter expire_logs_days"
      The contents of file "${MOCK_QUERY_FILE}" should equal "SET GLOBAL expire_logs_days = 1;"
    End
  End
End
