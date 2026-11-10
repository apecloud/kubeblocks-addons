# shellcheck shell=sh
# shellcheck disable=SC2317,SC2329

Describe "PgBouncer readiness recovery"
  setup() {
    TEST_COMMAND_LOG=$(mktemp)
    export TEST_COMMAND_LOG
    export POSTGRESQL_USERNAME=postgres POSTGRESQL_PASSWORD=fixture CURRENT_POD_IP=127.0.0.1
    export PGBOUNCER_BACKEND_ROLE=rw PGBOUNCER_ADMIN_USERNAME=pgbouncer PGBOUNCER_ADMIN_PASSWORD=admin-fixture
    export TEST_BACKEND=primary TEST_QUERY_STATUS=0 TEST_RECONNECT_STATUS=0 TEST_BLOCK_QUERY=0
  }

  cleanup() {
    rm -f "$TEST_COMMAND_LOG"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Mock psql
    case "$*" in
      *--username=postgres*--dbname=postgres*)
        [ "$PGPASSWORD" = fixture ] || exit 98
        if [ "$TEST_BLOCK_QUERY" = 1 ]; then
          exec sleep 10
        fi
        printf '%s\n' "$TEST_BACKEND"
        exit "$TEST_QUERY_STATUS"
        ;;
      *--username=pgbouncer*--dbname=pgbouncer*--command=RECONNECT)
        [ "$PGPASSWORD" = admin-fixture ] || exit 98
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

  It "is ready on a replica for a read-only pool"
    PGBOUNCER_BACKEND_ROLE=ro
    TEST_BACKEND=replica
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should be success
    The contents of file "$TEST_COMMAND_LOG" should be blank
  End

  It "retires connections to a promoted replica for a read-only pool"
    PGBOUNCER_BACKEND_ROLE=ro
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should be failure
    The contents of file "$TEST_COMMAND_LOG" should equal RECONNECT
  End

  It "retires a primary even if its default transactions are read-only"
    PGBOUNCER_BACKEND_ROLE=ro
    TEST_BACKEND=read-only
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should be failure
    The contents of file "$TEST_COMMAND_LOG" should equal RECONNECT
  End

  It "rejects an unknown backend role"
    PGBOUNCER_BACKEND_ROLE=invalid
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should be failure
    The contents of file "$TEST_COMMAND_LOG" should be blank
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

  It "kills a queued backend query within the probe budget"
    TEST_BLOCK_QUERY=1
    When run sh ../scripts/pgbouncer-readiness.sh
    The status should equal 137
    The stderr should be defined
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
