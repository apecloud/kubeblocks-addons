# shellcheck shell=bash
# shellcheck disable=SC2329

Describe "MySQL reconfigure compatibility contract"
  setup() {
    MYSQL_ADMIN_USER=kbadmin
    MYSQL_ADMIN_PASSWORD=secret
    MYSQL_CONFIG_FILE=$(mktemp)
    MYSQL_DYNAMIC_PARAMETERS_FILE=$(mktemp)
    MOCK_QUERY_FILE=$(mktemp)
    MYSQL_RECONFIGURE_RECEIPT_FILE=$(mktemp)
    rm -f "$MOCK_QUERY_FILE"
    rm -f "$MYSQL_RECONFIGURE_RECEIPT_FILE"
    export MYSQL_ADMIN_USER MYSQL_ADMIN_PASSWORD MYSQL_CONFIG_FILE
    export MYSQL_DYNAMIC_PARAMETERS_FILE MOCK_QUERY_FILE MYSQL_RECONFIGURE_RECEIPT_FILE

    printf '%s\n' '[mysqld]' 'max_connections=500' >"$MYSQL_CONFIG_FILE"
    printf '%s\n' 'max_connections' >"$MYSQL_DYNAMIC_PARAMETERS_FILE"
  }

  cleanup() {
    rm -f "$MYSQL_CONFIG_FILE" "$MYSQL_DYNAMIC_PARAMETERS_FILE" "$MOCK_QUERY_FILE"
    rm -f "$MYSQL_RECONFIGURE_RECEIPT_FILE" "${MYSQL_RECONFIGURE_RECEIPT_FILE}".*
  }

  mysql() {
    local query
    eval "query=\"\${$#}\""
    case "$query" in
      "SHOW GLOBAL VARIABLES")
        printf '%s\t%s\n' max_connections 400
        ;;
      "SHOW GLOBAL VARIABLES WHERE Variable_name = 'max_connections'")
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

  verification_failure_mysql() {
    local query
    eval "query=\"\${$#}\""
    case "$query" in
      "SHOW GLOBAL VARIABLES")
        printf '%s\t%s\n' max_connections 400
        ;;
      "SHOW GLOBAL VARIABLES WHERE Variable_name = 'max_connections'")
        printf '%s\t%s\n' max_connections 450
        ;;
      "SET GLOBAL max_connections = 500;")
        ;;
      *)
        printf 'unexpected query: %s\n' "$query" >&2
        return 1
        ;;
    esac
  }

  string_mysql() {
    local query
    eval "query=\"\${$#}\""
    case "$query" in
      "SET GLOBAL sql_mode = 'ANSI''QUOTES';")
        printf '%s' "$query" >"$MOCK_QUERY_FILE"
        ;;
      *)
        printf 'unexpected query: %s\n' "$query" >&2
        return 1
        ;;
    esac
  }

  partial_visibility_mysql() {
    local query
    eval "query=\"\${$#}\""
    case "$query" in
      "SHOW GLOBAL VARIABLES")
        printf '%s\t%s\n' max_connections 400
        ;;
      *)
        printf 'unexpected mutation/query: %s\n' "$query" >&2
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
    The path "$MYSQL_RECONFIGURE_RECEIPT_FILE" should be exist
  End

  It "fails closed when argv is absent and rendered config has no observable difference"
    mysql() { no_diff_mysql "$@"; }

    When run source ../scripts/update-parameter.sh
    The status should be failure
    The stderr should include "runtime arguments are missing"
    The stderr should include "next-retry-safe: yes"
  End

  It "accepts an idempotent retry only for the same completed rendered config"
    mysql() { no_diff_mysql "$@"; }
    fingerprint=$(cksum "$MYSQL_CONFIG_FILE" "$MYSQL_DYNAMIC_PARAMETERS_FILE" | cksum | awk '{ print $1 ":" $2 }')
    printf 'complete:%s\n' "$fingerprint" >"$MYSQL_RECONFIGURE_RECEIPT_FILE"

    When run source ../scripts/update-parameter.sh
    The status should be success
    The stdout should include "already converged for the recorded config"
  End

  It "finishes an interrupted matching pending receipt after convergence"
    mysql() { no_diff_mysql "$@"; }
    fingerprint=$(cksum "$MYSQL_CONFIG_FILE" "$MYSQL_DYNAMIC_PARAMETERS_FILE" | cksum | awk '{ print $1 ":" $2 }')
    printf 'pending:%s\n' "$fingerprint" >"$MYSQL_RECONFIGURE_RECEIPT_FILE"

    When run source ../scripts/update-parameter.sh
    The status should be success
    The stdout should include "already converged for the recorded config"
    The contents of file "$MYSQL_RECONFIGURE_RECEIPT_FILE" should start with "complete:"
  End

  It "fails closed when an argv-less update does not converge"
    mysql() { verification_failure_mysql "$@"; }

    When run source ../scripts/update-parameter.sh
    The status should be failure
    The stdout should include "Set parameter max_connections to value 500"
    The stderr should include "did not converge"
    The stderr should include "next-retry-safe: yes"
  End

  It "preflights all configured allowlisted variables before any fallback mutation"
    printf '%s\n' '[mysqld]' 'max_connections=500' 'event_scheduler=ON' >"$MYSQL_CONFIG_FILE"
    printf '%s\n' 'max_connections' 'event_scheduler' >"$MYSQL_DYNAMIC_PARAMETERS_FILE"
    mysql() { partial_visibility_mysql "$@"; }

    When run source ../scripts/update-parameter.sh
    The status should be failure
    The stderr should include "event_scheduler is absent from live MySQL variables"
    The path "$MOCK_QUERY_FILE" should not be exist
    The path "$MYSQL_RECONFIGURE_RECEIPT_FILE" should not be exist
  End

  It "preserves the deterministic positional-argument path"
    When run source ../scripts/update-parameter.sh max-connections 500
    The status should be success
    The stdout should include "Set parameter max_connections to value 500"
    The contents of file "$MOCK_QUERY_FILE" should equal "SET GLOBAL max_connections = 500;"
  End

  It "escapes string values on the positional-argument path"
    mysql() { string_mysql "$@"; }

    When run source ../scripts/update-parameter.sh sql-mode "ANSI'QUOTES"
    The status should be success
    The stdout should include "Set parameter sql_mode"
    The contents of file "$MOCK_QUERY_FILE" should equal "SET GLOBAL sql_mode = 'ANSI''QUOTES';"
  End

  It "rejects ambiguous extra runtime arguments"
    When run source ../scripts/update-parameter.sh max_connections 500 unexpected
    The status should be failure
    The stderr should include "Expected exactly two runtime arguments"
    The stderr should include "next-retry-safe: yes"
  End
End
