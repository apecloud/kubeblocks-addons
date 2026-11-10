# shellcheck shell=sh
# shellcheck disable=SC2317,SC2329

Describe "PgBouncer readiness recovery"
  setup() {
    TEST_COMMAND_LOG=$(mktemp)
    export TEST_COMMAND_LOG
    export POSTGRESQL_USERNAME=postgres POSTGRESQL_PASSWORD=fixture CURRENT_POD_IP=127.0.0.1
    export TEST_BACKEND=primary TEST_QUERY_STATUS=0 TEST_RECONNECT_STATUS=0
  }

  cleanup() {
    rm -f "$TEST_COMMAND_LOG"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Mock psql
    case "$*" in
      *--dbname=postgres*)
        printf '%s\n' "$TEST_BACKEND"
        exit "$TEST_QUERY_STATUS"
        ;;
      *--dbname=pgbouncer*--command=RECONNECT)
        printf '%s\n' RECONNECT >> "$TEST_COMMAND_LOG"
        exit "$TEST_RECONNECT_STATUS"
        ;;
      *) exit 99 ;;
    esac
  End

  It "is ready on a writable primary without reconnecting"
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should be success
    The contents of file "$TEST_COMMAND_LOG" should be blank
  End

  It "retires replica connections and waits for the next probe to become ready"
    TEST_BACKEND=replica
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should be failure
    The contents of file "$TEST_COMMAND_LOG" should equal RECONNECT
  End

  It "does not reconnect a primary configured for read-only transactions"
    TEST_BACKEND=read-only
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should be failure
    The contents of file "$TEST_COMMAND_LOG" should be blank
  End

  It "does not reconnect when the backend query fails"
    TEST_BACKEND=replica
    TEST_QUERY_STATUS=2
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should be failure
    The contents of file "$TEST_COMMAND_LOG" should be blank
  End

  It "remains unready when the admin reconnect fails"
    TEST_BACKEND=replica
    TEST_RECONNECT_STATUS=2
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should be failure
    The contents of file "$TEST_COMMAND_LOG" should equal RECONNECT
  End
End
