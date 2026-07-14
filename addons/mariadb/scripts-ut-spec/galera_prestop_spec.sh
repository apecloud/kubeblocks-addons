# shellcheck shell=bash

Describe "galera-prestop.sh"
  setup() {
    TEST_DIR=$(mktemp -d)
    export DATA_DIR="${TEST_DIR}/data"
    export POD_NAME="mdb-galera-mariadb-0"
    export PEER_FQDNS="mdb-galera-mariadb-0.headless.demo.svc.cluster.local,mdb-galera-mariadb-1.headless.demo.svc.cluster.local,mdb-galera-mariadb-2.headless.demo.svc.cluster.local"
    export MARIADB_ROOT_USER="root"
    export MARIADB_ROOT_PASSWORD="secret"
    export GALERA_PRESTOP_CONTAINER_LOG_PATH="${TEST_DIR}/container.log"
    export GALERA_PRESTOP_DEGRADED_LOG="${DATA_DIR}/log/galera-prestop-degraded.log"
    mkdir -p "${DATA_DIR}"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "${TEST_DIR}"
    unset DATA_DIR POD_NAME PEER_FQDNS MARIADB_ROOT_USER MARIADB_ROOT_PASSWORD
    unset GALERA_PRESTOP_ORDER_WAIT_SECONDS GALERA_PRESTOP_POLL_SECONDS
    unset GALERA_PRESTOP_PROBE_TIMEOUT_SECONDS GALERA_PRESTOP_SQL_TIMEOUT_SECONDS
    unset GALERA_PRESTOP_SHUTDOWN_TIMEOUT_SECONDS GALERA_PRESTOP_CONTAINER_LOG_PATH
    unset GALERA_PRESTOP_TERMINATION_GRACE_SECONDS GALERA_PRESTOP_SAFETY_MARGIN_SECONDS
    unset GALERA_PRESTOP_DEGRADED_LOG VALIDATION_ERROR DEGRADED_EVIDENCE_WRITE_FAILED
  }
  AfterEach "cleanup"

  Include ../scripts/galera-prestop.sh

  timeout() {
    shift
    "$@"
  }

  It "rejects a missing pod identity instead of treating it as the highest ordinal"
    POD_NAME=""

    When call validate_inputs
    The status should be failure
    The variable VALIDATION_ERROR should include "reason=invalid_pod_name"
  End

  It "rejects missing peer identities instead of treating them as stopped"
    PEER_FQDNS=""

    When call validate_inputs
    The status should be failure
    The variable VALIDATION_ERROR should equal "reason=missing_peer_fqdns"
  End

  It "rejects empty entries in the peer FQDN list"
    PEER_FQDNS="mdb-galera-mariadb-0.headless.demo.svc.cluster.local,,mdb-galera-mariadb-2.headless.demo.svc.cluster.local"

    When call validate_inputs
    The status should be failure
    The variable VALIDATION_ERROR should equal "reason=invalid_peer_fqdns_list"
  End

  It "rejects a peer name that is not an FQDN"
    PEER_FQDNS="mdb-galera-mariadb-0,mdb-galera-mariadb-1.headless.demo.svc.cluster.local"

    When call validate_inputs
    The status should be failure
    The variable VALIDATION_ERROR should include "reason=invalid_peer_fqdn"
  End

  It "rejects a non-numeric pod ordinal"
    POD_NAME="mdb-galera-mariadb-primary"

    When call validate_inputs
    The status should be failure
    The variable VALIDATION_ERROR should include "reason=invalid_pod_name"
  End

  It "requires the local pod to appear in PEER_FQDNS"
    PEER_FQDNS="mdb-galera-mariadb-1.headless.demo.svc.cluster.local,mdb-galera-mariadb-2.headless.demo.svc.cluster.local"

    When call validate_inputs
    The status should be failure
    The variable VALIDATION_ERROR should include "reason=self_missing_from_peer_fqdns"
  End

  It "rejects timeout settings that consume the termination grace period"
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=70
    GALERA_PRESTOP_SQL_TIMEOUT_SECONDS=5
    GALERA_PRESTOP_SHUTDOWN_TIMEOUT_SECONDS=40
    GALERA_PRESTOP_SAFETY_MARGIN_SECONDS=5
    GALERA_PRESTOP_TERMINATION_GRACE_SECONDS=120

    When call validate_inputs
    The status should be failure
    The variable VALIDATION_ERROR should include "reason=timeout_budget_exceeds_termination_grace"
  End

  It "accepts the default timeout budget with a safety margin"
    When call validate_inputs
    The status should be success
  End

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

    When call wait_for_higher_ordinals
    The status should be failure
    The output should include "ordered shutdown degraded"
    The output should include "mdb-galera-mariadb-1"
    The output should include "mdb-galera-mariadb-2"
  End

  It "uses wall-clock progress instead of adding only poll intervals"
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=2
    GALERA_PRESTOP_POLL_SECONDS=30
    printf '0\n' > "${TEST_DIR}/clock"
    monotonic_seconds() {
      local now
      now="$(cat "${TEST_DIR}/clock")"
      printf '%s\n' "$((now + 1))" > "${TEST_DIR}/clock"
      printf '%s' "${now}"
    }
    peer_sql_port_state() {
      printf 'open'
    }

    When call wait_for_higher_ordinals
    The status should be failure
    The output should include "reason=order_wait_timeout"
    The output should include "elapsed_seconds="
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "budget-exhausted"
  End

  It "classifies a TCP timeout as uncertain rather than stopped"
    timeout() {
      return 124
    }

    When call peer_sql_port_state "mdb-galera-mariadb-2.example" 2
    The output should equal "timeout"
  End

  It "classifies connection refused as a stopped peer"
    timeout() {
      printf 'bash: connect: Connection refused\n' >&2
      return 1
    }

    When call peer_sql_port_state "mdb-galera-mariadb-2.example" 2
    The output should equal "closed"
  End

  It "classifies DNS failure as uncertain rather than stopped"
    timeout() {
      printf 'bash: example: Name or service not known\n' >&2
      return 1
    }

    When call peer_sql_port_state "missing.example" 2
    The output should equal "dns-failure"
  End

  It "persists and mirrors degraded shutdown evidence"
    When call record_degraded "reason=test_degradation"
    The status should be success
    The output should include "ordered shutdown degraded: reason=test_degradation"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=test_degradation"
    The contents of file "${GALERA_PRESTOP_CONTAINER_LOG_PATH}" should include "ordered shutdown degraded: reason=test_degradation"
  End

  It "keeps the preStop hook successful after invalid identity is recorded"
    POD_NAME=""
    local_sql() {
      return 0
    }
    mysqladmin() {
      return 0
    }

    When call main
    The status should be success
    The output should include "reason=invalid_pod_name"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=invalid_pod_name"
  End

  It "finishes local shutdown then fails the hook when both degraded evidence sinks are unavailable"
    POD_NAME=""
    GALERA_PRESTOP_CONTAINER_LOG_PATH="/dev/null/container-log"
    GALERA_PRESTOP_DEGRADED_LOG="/dev/null/degraded-log"
    local_sql() {
      printf '%s\n' "$1" >> "${TEST_DIR}/sql.log"
      return 0
    }
    mysqladmin() {
      printf 'mysqladmin %s\n' "$*" >> "${TEST_DIR}/sql.log"
      return 0
    }

    When call main
    The status should be failure
    The output should include "reason=invalid_pod_name"
    The stderr should include "degraded evidence sinks unavailable"
    The contents of file "${TEST_DIR}/sql.log" should include "SET GLOBAL wsrep_desync=ON;"
    The contents of file "${TEST_DIR}/sql.log" should include "mysqladmin"
  End

  It "degrades a stuck higher-ordinal peer but still shuts down locally and exits successfully"
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=2
    GALERA_PRESTOP_POLL_SECONDS=30
    printf '0\n' > "${TEST_DIR}/clock"
    monotonic_seconds() {
      local now
      now="$(cat "${TEST_DIR}/clock")"
      printf '%s\n' "$((now + 1))" > "${TEST_DIR}/clock"
      printf '%s' "${now}"
    }
    peer_sql_port_state() {
      printf 'open'
    }
    local_sql() {
      printf '%s\n' "$1" >> "${TEST_DIR}/sql.log"
      return 0
    }
    mysqladmin() {
      printf 'mysqladmin %s\n' "$*" >> "${TEST_DIR}/sql.log"
      return 0
    }

    When call main
    The status should be success
    The output should include "reason=order_wait_timeout"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=order_wait_timeout"
    The contents of file "${TEST_DIR}/sql.log" should include "SET GLOBAL wsrep_desync=ON;"
    The contents of file "${TEST_DIR}/sql.log" should include "SET GLOBAL wsrep_on=OFF;"
    The contents of file "${TEST_DIR}/sql.log" should include "mysqladmin -uroot -psecret -h127.0.0.1 shutdown"
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

  It "publishes the shutting-down marker before the first Galera desync mutation"
    local_sql() {
      if [ "$1" = "SET GLOBAL wsrep_desync=ON;" ] \
        && [ ! -f "${DATA_DIR}/.galera-shutting-down" ]; then
        printf 'desync-before-marker\n' >> "${TEST_DIR}/sql.log"
        return 1
      fi
      printf '%s\n' "$1" >> "${TEST_DIR}/sql.log"
      return 0
    }
    mysqladmin() {
      printf 'mysqladmin %s\n' "$*" >> "${TEST_DIR}/sql.log"
      return 0
    }

    When call graceful_shutdown
    The status should be success
    The path "${DATA_DIR}/.galera-shutting-down" should be exist
    The contents of file "${TEST_DIR}/sql.log" should not include "desync-before-marker"
    The contents of file "${TEST_DIR}/sql.log" should include "SET GLOBAL wsrep_desync=ON;"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should not include "reason=wsrep_desync_failed"
  End

  It "records a marker publication failure but still performs the local shutdown"
    DATA_DIR="/dev/null/data"
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
    The output should include "failed to publish .galera-shutting-down"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=shutting_down_marker_failed"
    The contents of file "${TEST_DIR}/sql.log" should include "SET GLOBAL wsrep_desync=ON;"
    The contents of file "${TEST_DIR}/sql.log" should include "mysqladmin"
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
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=wsrep_desync_failed"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=wsrep_disable_failed"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=mysqladmin_shutdown_failed"
  End
End
