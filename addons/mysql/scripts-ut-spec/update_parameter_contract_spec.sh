# shellcheck shell=bash

Describe "MySQL reconfigure compatibility contract"
  setup() {
    MYSQL_ADMIN_USER=kbadmin
    MYSQL_ADMIN_PASSWORD=secret
    MYSQL_CONFIG_FILE=$(mktemp)
    MYSQL_DYNAMIC_PARAMETERS_FILE=$(mktemp)
    MOCK_QUERY_FILE=$(mktemp)
    export MYSQL_ADMIN_USER MYSQL_ADMIN_PASSWORD MYSQL_CONFIG_FILE
    export MYSQL_DYNAMIC_PARAMETERS_FILE MOCK_QUERY_FILE

    printf '%s\n' '[mysqld]' 'max_connections=500' >"$MYSQL_CONFIG_FILE"
    printf '%s\n' 'max_connections' >"$MYSQL_DYNAMIC_PARAMETERS_FILE"
  }

  cleanup() {
    rm -f "$MYSQL_CONFIG_FILE" "$MYSQL_DYNAMIC_PARAMETERS_FILE" "$MOCK_QUERY_FILE"
  }

  mysql() {
    local query
    eval "query=\"\${$#}\""
    case "$query" in
      "SHOW GLOBAL VARIABLES")
        printf '%s\t%s\n' max_connections 400
        ;;
      "SHOW GLOBAL VARIABLES LIKE 'max_connections'")
        printf '%s\t%s\n' max_connections 500
        ;;
      "SET GLOBAL max_connections = 500;")
        printf '%s' "$query" >"$MOCK_QUERY_FILE"
        ;;
      *)
        printf 'unexpected query: %s\n' "$query" >&2
        return 1
        ;;
    esac
  }

  no_diff_mysql() {
    local query
    eval "query=\"\${$#}\""
    case "$query" in
      "SHOW GLOBAL VARIABLES")
        printf '%s\t%s\n' max_connections 500
        ;;
      *)
        printf 'unexpected query: %s\n' "$query" >&2
        return 1
        ;;
    esac
  }

  BeforeEach "setup"
  AfterEach "cleanup"

  It "applies a rendered dynamic difference when runtime argv is absent"
    When run source ../scripts/update-parameter.sh
    The status should be success
    The stdout should include "Applied 1 rendered dynamic parameter"
    The contents of file "$MOCK_QUERY_FILE" should equal "SET GLOBAL max_connections = 500;"
  End

  It "fails closed when argv is absent and rendered config has no observable difference"
    mysql() { no_diff_mysql "$@"; }

    When run source ../scripts/update-parameter.sh
    The status should be failure
    The stderr should include "runtime arguments are missing"
    The stderr should include "next-retry-safe: yes"
  End
End
