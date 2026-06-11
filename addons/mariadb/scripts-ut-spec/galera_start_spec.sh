# shellcheck shell=bash

Describe "galera-start.sh"
  setup() {
    TEST_DIR=$(mktemp -d)
    export DATA_DIR="${TEST_DIR}/data"
    export POD_NAME="mdb-galera-mariadb-1"
    export MARIADB_ROOT_USER="root"
    export MARIADB_ROOT_PASSWORD="secret"
    export PEER_FQDNS="mdb-galera-mariadb-0.headless.demo.svc.cluster.local,mdb-galera-mariadb-1.headless.demo.svc.cluster.local"
    mkdir -p "${DATA_DIR}"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "${TEST_DIR}"
    unset DATA_DIR POD_NAME MARIADB_ROOT_USER MARIADB_ROOT_PASSWORD PEER_FQDNS
    unset GALERA_PRIMARY_PEER_WAIT_SECONDS
  }
  AfterEach "cleanup"

  Include ../scripts/galera-start.sh

  Describe "_any_peer_alive()"
    It "queries peer wsrep status with TLS disabled"
      timeout() {
        echo "$*" >> "${TEST_DIR}/timeout.args"
        case "$*" in
          *" bash -c "*) return 0 ;;
          *" mariadb "*) printf "wsrep_cluster_status\tPrimary\n"; return 0 ;;
        esac
        return 1
      }

      When call _any_peer_alive quiet
      The status should be success
      The output should include "wsrep_cluster_status=Primary"
      The contents of file "${TEST_DIR}/timeout.args" should include "--ssl=0"
      The contents of file "${TEST_DIR}/timeout.args" should include "-P3306"
    End
  End

  Describe "_wait_for_primary_peer()"
    It "defers non-pod-0 join when no Primary peer appears within the bounded window"
      GALERA_PRIMARY_PEER_WAIT_SECONDS=0
      _any_peer_alive() {
        return 1
      }

      When call _wait_for_primary_peer
      The status should be failure
      The output should include "Deferring join to avoid forming a separate non-Primary Galera partition"
    End
  End
End
