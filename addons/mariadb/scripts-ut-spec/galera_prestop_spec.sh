# shellcheck shell=bash

Describe "galera-prestop.sh"
  setup() {
    TEST_DIR=$(mktemp -d)
    export DATA_DIR="${TEST_DIR}/data"
    export POD_NAME="mdb-galera-mariadb-0"
    export PEER_FQDNS="mdb-galera-mariadb-0.headless.demo.svc.cluster.local,mdb-galera-mariadb-1.headless.demo.svc.cluster.local,mdb-galera-mariadb-2.headless.demo.svc.cluster.local"
    export GALERA_PRESTOP_CONTAINER_LOG_PATH="${TEST_DIR}/container.log"
    export GALERA_PRESTOP_DEGRADED_LOG="${DATA_DIR}/log/galera-prestop-degraded.log"
    mkdir -p "${DATA_DIR}"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "${TEST_DIR}"
    unset DATA_DIR POD_NAME PEER_FQDNS
    unset GALERA_PRESTOP_ORDER_WAIT_SECONDS GALERA_PRESTOP_POLL_SECONDS
    unset GALERA_PRESTOP_PROBE_TIMEOUT_SECONDS GALERA_PRESTOP_CONTAINER_LOG_PATH
    unset GALERA_PRESTOP_TERMINATION_GRACE_SECONDS GALERA_PRESTOP_SAFETY_MARGIN_SECONDS
    unset GALERA_PRESTOP_DEGRADED_LOG VALIDATION_ERROR
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
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=116
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

  It "classifies authoritative name absence separately from transient DNS failure"
    timeout() {
      printf 'bash: example: Name or service not known\n' >&2
      return 1
    }

    When call peer_sql_port_state "missing.example" 2
    The output should equal "absent"
  End

  It "classifies no-address name absence as authoritative"
    timeout() {
      printf 'bash: example: No address associated with hostname\n' >&2
      return 1
    }

    When call peer_sql_port_state "missing.example" 2
    The output should equal "absent"
  End

  It "keeps temporary DNS failure uncertain"
    timeout() {
      printf 'bash: example: Temporary failure in name resolution\n' >&2
      return 1
    }

    When call peer_sql_port_state "missing.example" 2
    The output should equal "dns-transient"
  End

  It "requires two consecutive authoritative absences before closing a peer"
    POD_NAME="mdb-galera-mariadb-1"
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=10
    GALERA_PRESTOP_POLL_SECONDS=1
    printf '0\n' > "${TEST_DIR}/clock"
    monotonic_seconds() {
      cat "${TEST_DIR}/clock"
    }
    sleep() {
      local now
      now="$(cat "${TEST_DIR}/clock")"
      printf '%s\n' "$((now + 1))" > "${TEST_DIR}/clock"
    }
    peer_sql_port_state() {
      local calls=0
      [ -f "${TEST_DIR}/peer-calls" ] && calls="$(cat "${TEST_DIR}/peer-calls")"
      calls=$((calls + 1))
      printf '%s\n' "${calls}" > "${TEST_DIR}/peer-calls"
      printf 'absent'
    }

    When call wait_for_higher_ordinals
    The status should be success
    The contents of file "${TEST_DIR}/peer-calls" should equal "2"
    The output should include "higher-ordinal peers have stopped"
  End

  It "clears an absence streak after an uncertain observation"
    POD_NAME="mdb-galera-mariadb-1"
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=10
    GALERA_PRESTOP_POLL_SECONDS=1
    printf '0\n' > "${TEST_DIR}/clock"
    monotonic_seconds() {
      cat "${TEST_DIR}/clock"
    }
    sleep() {
      local now
      now="$(cat "${TEST_DIR}/clock")"
      printf '%s\n' "$((now + 1))" > "${TEST_DIR}/clock"
    }
    peer_sql_port_state() {
      local calls=0
      [ -f "${TEST_DIR}/peer-calls" ] && calls="$(cat "${TEST_DIR}/peer-calls")"
      calls=$((calls + 1))
      printf '%s\n' "${calls}" > "${TEST_DIR}/peer-calls"
      case "${calls}" in
        1|3|4) printf 'absent' ;;
        2) printf 'dns-transient' ;;
      esac
    }

    When call wait_for_higher_ordinals
    The status should be success
    The contents of file "${TEST_DIR}/peer-calls" should equal "4"
    The output should include "higher-ordinal peers have stopped"
  End

  It "clears an absence streak across timeout unreachable and unknown states"
    POD_NAME="mdb-galera-mariadb-1"
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=20
    GALERA_PRESTOP_POLL_SECONDS=1
    printf '0\n' > "${TEST_DIR}/clock"
    monotonic_seconds() {
      cat "${TEST_DIR}/clock"
    }
    sleep() {
      local now
      now="$(cat "${TEST_DIR}/clock")"
      printf '%s\n' "$((now + 1))" > "${TEST_DIR}/clock"
    }
    peer_sql_port_state() {
      local calls=0
      [ -f "${TEST_DIR}/peer-calls" ] && calls="$(cat "${TEST_DIR}/peer-calls")"
      calls=$((calls + 1))
      printf '%s\n' "${calls}" > "${TEST_DIR}/peer-calls"
      case "${calls}" in
        1|3|5|7|8) printf 'absent' ;;
        2) printf 'timeout' ;;
        4) printf 'unreachable' ;;
        6) printf 'unexpected-state' ;;
      esac
    }

    When call wait_for_higher_ordinals
    The status should be success
    The contents of file "${TEST_DIR}/peer-calls" should equal "8"
    The output should include "higher-ordinal peers have stopped"
  End

  It "tracks authoritative absence streaks independently per peer"
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=10
    GALERA_PRESTOP_POLL_SECONDS=1
    printf '0\n' > "${TEST_DIR}/clock"
    monotonic_seconds() {
      cat "${TEST_DIR}/clock"
    }
    sleep() {
      local now
      now="$(cat "${TEST_DIR}/clock")"
      printf '%s\n' "$((now + 1))" > "${TEST_DIR}/clock"
    }
    peer_sql_port_state() {
      local peer="$1"
      local key="${peer%%.*}"
      local counter="${TEST_DIR}/${key}.calls"
      local calls=0
      [ -f "${counter}" ] && calls="$(cat "${counter}")"
      calls=$((calls + 1))
      printf '%s\n' "${calls}" > "${counter}"
      case "${key}" in
        mdb-galera-mariadb-1) printf 'absent' ;;
        mdb-galera-mariadb-2)
          case "${calls}" in
            1|3|4) printf 'absent' ;;
            2) printf 'open' ;;
          esac
          ;;
      esac
    }

    When call wait_for_higher_ordinals
    The status should be success
    The contents of file "${TEST_DIR}/mdb-galera-mariadb-1.calls" should equal "2"
    The contents of file "${TEST_DIR}/mdb-galera-mariadb-2.calls" should equal "4"
    The output should include "higher-ordinal peers have stopped"
  End

  It "does not close a peer after only one authoritative absence"
    POD_NAME="mdb-galera-mariadb-1"
    GALERA_PRESTOP_ORDER_WAIT_SECONDS=2
    GALERA_PRESTOP_POLL_SECONDS=1
    printf '0\n' > "${TEST_DIR}/clock"
    monotonic_seconds() {
      cat "${TEST_DIR}/clock"
    }
    sleep() {
      local now
      now="$(cat "${TEST_DIR}/clock")"
      printf '%s\n' "$((now + 1))" > "${TEST_DIR}/clock"
    }
    peer_sql_port_state() {
      if [ ! -f "${TEST_DIR}/observed-once" ]; then
        : > "${TEST_DIR}/observed-once"
        printf 'absent'
      else
        printf 'open'
      fi
    }

    When call wait_for_higher_ordinals
    The status should be failure
    The output should include "reason=order_wait_timeout"
  End

  It "persists and mirrors degraded shutdown evidence"
    When call record_degraded "reason=test_degradation"
    The status should be success
    The output should include "ordered shutdown degraded: reason=test_degradation"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=test_degradation"
    The contents of file "${GALERA_PRESTOP_CONTAINER_LOG_PATH}" should include "ordered shutdown degraded: reason=test_degradation"
  End

  It "fails closed on invalid identity before publishing the shutdown marker"
    POD_NAME=""

    When call main
    The status should be failure
    The output should include "reason=invalid_pod_name"
    The stderr should include "shutdown preparation failed: reason=invalid_pod_name"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=invalid_pod_name"
    The path "${DATA_DIR}/.galera-shutting-down" should not be exist
  End

  It "fails the hook when both failure evidence sinks are unavailable"
    POD_NAME=""
    GALERA_PRESTOP_CONTAINER_LOG_PATH="/dev/null/container-log"
    GALERA_PRESTOP_DEGRADED_LOG="/dev/null/degraded-log"

    When call main
    The status should be failure
    The output should include "reason=invalid_pod_name"
    The stderr should include "shutdown preparation failed"
    The path "${DATA_DIR}/.galera-shutting-down" should not be exist
  End

  It "fails closed on a stuck higher-ordinal peer before publishing the shutdown marker"
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
    When call main
    The status should be failure
    The output should include "reason=order_wait_timeout"
    The stderr should include "shutdown preparation failed: higher-ordinal peers did not stop"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=order_wait_timeout"
    The path "${DATA_DIR}/.galera-shutting-down" should not be exist
  End

  It "publishes the marker then lets kubelet signal PID 1"
    mariadb() {
      printf 'mariadb %s\n' "$*" >> "${TEST_DIR}/unexpected-client.log"
      return 0
    }
    mysqladmin() {
      printf 'mysqladmin %s\n' "$*" >> "${TEST_DIR}/unexpected-client.log"
      return 0
    }

    When call prepare_ordered_shutdown
    The status should be success
    The path "${DATA_DIR}/.galera-shutting-down" should be exist
    The output should include "kubelet may now signal mariadbd"
    The path "${TEST_DIR}/unexpected-client.log" should not be exist
  End

  It "returns success only after order and marker preparation both close"
    peer_sql_port_state() {
      printf 'closed'
    }

    When call main
    The status should be success
    The path "${DATA_DIR}/.galera-shutting-down" should be exist
    The output should include "higher-ordinal peers have stopped"
    The output should include "kubelet may now signal mariadbd"
  End

  It "fails when the shutdown marker cannot be published"
    DATA_DIR="/dev/null/data"

    When call prepare_ordered_shutdown
    The status should be failure
    The output should include "failed to publish .galera-shutting-down"
    The contents of file "${GALERA_PRESTOP_DEGRADED_LOG}" should include "reason=shutting_down_marker_failed"
  End
End
