# shellcheck shell=bash

Describe "galera-prestop.sh"
  setup() {
    TEST_DIR=$(mktemp -d)
    export DATA_DIR="${TEST_DIR}/data"
    export POD_NAME="mdb-galera-mariadb-0"
    export PEER_FQDNS="mdb-galera-mariadb-0.headless.demo.svc.cluster.local,mdb-galera-mariadb-1.headless.demo.svc.cluster.local,mdb-galera-mariadb-2.headless.demo.svc.cluster.local"
    export MARIADB_ROOT_USER="root"
    export MARIADB_ROOT_PASSWORD="secret"
    mkdir -p "${DATA_DIR}"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "${TEST_DIR}"
    unset DATA_DIR POD_NAME PEER_FQDNS MARIADB_ROOT_USER MARIADB_ROOT_PASSWORD
    unset GALERA_PRESTOP_ORDER_WAIT_SECONDS GALERA_PRESTOP_POLL_SECONDS
  }
  AfterEach "cleanup"

  Include ../scripts/galera-prestop.sh

  It "waits only for higher-ordinal peers"
    POD_NAME="mdb-galera-mariadb-1"

    When call higher_ordinal_peers
    The output should equal "mdb-galera-mariadb-2.headless.demo.svc.cluster.local"
  End

  It "does not wait on pod-2 because no higher ordinal exists"
    POD_NAME="mdb-galera-mariadb-2"

    When call wait_for_higher_ordinals
    The status should be success
    The output should include "no higher-ordinal peers"
  End

  It "degrades after a bounded timeout when a higher ordinal stays alive"
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=0
    peer_sql_port_open() {
      return 0
    }

    When call wait_for_higher_ordinals
    The status should be failure
    The output should include "ordered shutdown degraded"
    The output should include "mdb-galera-mariadb-1"
    The output should include "mdb-galera-mariadb-2"
  End

  It "runs desync, wsrep disable, and mysqladmin shutdown in order"
    local_sql() {
      printf '%s\n' "$1" >> "${TEST_DIR}/sql.log"
      return 0
    }
    mysqladmin() {
      printf 'mysqladmin %s\n' "$*" >> "${TEST_DIR}/sql.log"
      return 0
    }

    When call graceful_shutdown
    The status should be success
    The contents of file "${TEST_DIR}/sql.log" should include "SET GLOBAL wsrep_desync=ON;"
    The contents of file "${TEST_DIR}/sql.log" should include "SET GLOBAL wsrep_on=OFF;"
    The contents of file "${TEST_DIR}/sql.log" should include "mysqladmin -uroot -psecret -h127.0.0.1 shutdown"
  End

  It "does not fail the hook when SQL cleanup commands fail"
    local_sql() {
      return 1
    }
    mysqladmin() {
      return 1
    }

    When call graceful_shutdown
    The status should be success
    The output should include "failed to set wsrep_desync=ON"
    The output should include "failed to set wsrep_on=OFF"
    The output should include "mysqladmin shutdown failed"
  End
End
