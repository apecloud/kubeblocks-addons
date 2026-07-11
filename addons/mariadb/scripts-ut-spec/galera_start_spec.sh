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
    unset GALERA_PRIMARY_PEER_WAIT_SECONDS GALERA_BOOTSTRAP_DEFER_REASON
  }
  AfterEach "cleanup"

  Include ../scripts/galera-start.sh

  script_file() {
    printf "%s/addons/mariadb/scripts/galera-start.sh" "${SHELLSPEC_CWD:?}"
  }

  script_contains() {
    grep -F "$1" "$(script_file)"
  }

  write_grastate() {
    cat > "${DATA_DIR}/grastate.dat" <<EOF
uuid:    631a68d0-7697-11f1-923e-42be04dfa95f
seqno:   ${1}
safe_to_bootstrap: ${2}
EOF
  }

  socketless_self_heal_kills_mariadbd() {
    awk '
      index($0, "NO_SOCKET_COUNT=0") && !counter { counter = NR }
      index($0, "NO_SOCKET_THRESHOLD=\"${GALERA_SOCKETLESS_MARIADBD_THRESHOLD:-30}\"") && !threshold { threshold = NR }
      threshold && index($0, "pgrep -x mariadbd") && !detects { detects = NR }
      index($0, "_restart_mariadbd_for_self_heal") && !helper { helper = NR }
      index($0, "mariadbd running without ${SOCK}") { message = NR }
      index($0, "kill -TERM ${pids}") && !term { term = NR }
      index($0, "kill -KILL ${pids}") && !kill9 { kill9 = NR }
      END { exit(counter && threshold && detects && helper && message && term && kill9 && counter < threshold && threshold < detects && message > detects && term < kill9 ? 0 : 1) }
    ' "$(script_file)"
  }

  socket_available_resets_socketless_counter() {
    awk '
      index($0, "if [ -S \"${SOCK}\" ]; then") { socket = NR }
      socket && index($0, "NO_SOCKET_COUNT=0") { reset = NR; exit }
      END { exit(socket && reset && socket < reset ? 0 : 1) }
    ' "$(script_file)"
  }

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

    It "treats a port-open-but-unqueryable peer as possibly-alive (fail closed against split-brain)"
      # Port 3306 open, but the wsrep status query returns nothing (auth error
      # / SST / load). This must NOT be read as "no peer" — a live Primary we
      # cannot read would let this node bootstrap a second Primary.
      timeout() {
        case "$*" in
          *" bash -c "*) return 0 ;;      # port open
          *" mariadb "*) return 0 ;;      # query "runs" but prints no status
        esac
        return 1
      }
      sleep() { :; }

      When call _any_peer_alive
      The status should be success
      The output should include "unreadable after retries"
    End

    It "skips a peer that gives a clean non-Primary answer"
      timeout() {
        case "$*" in
          *" bash -c "*) return 0 ;;
          *" mariadb "*) printf "wsrep_cluster_status\tnon-Primary\n"; return 0 ;;
        esac
        return 1
      }

      When call _any_peer_alive
      The status should be failure
      The output should include "not Primary, skipping"
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

  Describe "should_bootstrap()"
    It "refuses pod-0 crash recovery bootstrap when local grastate is not safe"
      POD_NAME="mdb-galera-mariadb-0"
      write_grastate 7 0
      _any_peer_alive() {
        return 1
      }
      mariadbd() {
        printf "WSREP: Recovered position: 631a68d0-7697-11f1-923e-42be04dfa95f:7\n"
      }

      When call should_bootstrap
      The status should be failure
      The output should include "Refusing automatic Galera crash recovery bootstrap"
      The output should include "wsrep-recover: seqno=7"
      The contents of file "${DATA_DIR}/grastate.dat" should include "safe_to_bootstrap: 0"
      The variable GALERA_BOOTSTRAP_DEFER_REASON should include "latest seqno"
    End

    It "allows pod-0 bootstrap when grastate is already safe"
      POD_NAME="mdb-galera-mariadb-0"
      write_grastate 9 1
      _any_peer_alive() {
        return 1
      }

      When call should_bootstrap
      The status should be success
      The output should include "grastate.dat: safe_to_bootstrap=1"
    End

    It "allows non-pod-0 bootstrap when Galera marks it safe after clean shutdown"
      POD_NAME="mdb-galera-mariadb-1"
      write_grastate 9 1
      _any_peer_alive() {
        return 1
      }

      When call should_bootstrap
      The status should be success
      The output should include "grastate.dat: safe_to_bootstrap=1"
    End

    It "keeps fresh (seqno=-1, safe_to_bootstrap=1) bootstrap single-owner on pod-0"
      POD_NAME="mdb-galera-mariadb-0"
      write_grastate -1 1
      _any_peer_alive() {
        return 1
      }

      When call should_bootstrap
      The status should be success
      The output should include "Fresh grastate.dat seqno=-1 safe_to_bootstrap=1, pod-0 will bootstrap"
    End

    It "prevents non-pod-0 fresh (seqno=-1, safe_to_bootstrap=1) bootstrap"
      POD_NAME="mdb-galera-mariadb-1"
      write_grastate -1 1
      _any_peer_alive() {
        return 1
      }

      When call should_bootstrap
      The status should be failure
      The output should include "Fresh grastate.dat seqno=-1 safe_to_bootstrap=1"
      The output should include "will wait for pod-0 bootstrap"
    End

    It "refuses pod-0 bootstrap on a hard-crash grastate (seqno=-1, safe_to_bootstrap=0)"
      # A running node killed by OOM/power-loss/SIGKILL leaves seqno=-1 but
      # safe_to_bootstrap=0 — indistinguishable from a fresh PVC by seqno
      # alone. pod-0 must NOT blind-bootstrap possibly-stale data; it defers
      # to the fail-closed crash-recovery path.
      POD_NAME="mdb-galera-mariadb-0"
      write_grastate -1 0
      _any_peer_alive() {
        return 1
      }
      mariadbd() {
        printf "WSREP: Recovered position: 631a68d0-7697-11f1-923e-42be04dfa95f:44\n"
      }

      When call should_bootstrap
      The status should be failure
      The output should include "Refusing automatic Galera crash recovery bootstrap"
      The variable GALERA_BOOTSTRAP_DEFER_REASON should include "latest seqno"
    End

    It "prevents non-pod-0 hard-crash (seqno=-1, safe_to_bootstrap=0) bootstrap"
      POD_NAME="mdb-galera-mariadb-1"
      write_grastate -1 0
      _any_peer_alive() {
        return 1
      }

      When call should_bootstrap
      The status should be failure
    End
  End

  Describe "socketless mariadbd self-heal"
    It "self-heals when mariadbd runs without creating the local socket"
      When call socketless_self_heal_kills_mariadbd
      The status should be success
    End

    It "resets socketless self-heal once the MariaDB socket exists"
      When call socket_available_resets_socketless_counter
      The status should be success
    End

    It "keeps socketless self-heal threshold configurable"
      When call script_contains "GALERA_SOCKETLESS_MARIADBD_THRESHOLD"
      The status should be success
      The output should include "GALERA_SOCKETLESS_MARIADBD_THRESHOLD"
    End

    It "does not count socketless ticks while an SST is in progress"
      # H9: a joiner performing SST runs mariadbd without a SQL socket until
      # the transfer completes; the socketless killer must skip it, keyed on
      # the Galera SST marker (sst_in_progress) or a live wsrep_sst_ helper.
      When call script_contains "sst_in_progress"
      The status should be success
      The output should include "sst_in_progress"
    End

    It "gates the SST skip BEFORE the socketless-kill increment (source order)"
      # The sst_in_progress guard branch must precede the NO_SOCKET_COUNT
      # increment so an in-progress SST resets the counter instead of
      # accumulating toward a kill.
      When run sh -c '
        f="$(printf "%s/addons/mariadb/scripts/galera-start.sh" "'"${SHELLSPEC_CWD:?}"'")"
        sst=$(grep -n "sst_in_progress" "$f" | head -1 | cut -d: -f1)
        inc=$(grep -n "NO_SOCKET_COUNT=\$((NO_SOCKET_COUNT + 1))" "$f" | head -1 | cut -d: -f1)
        if [ -n "$sst" ] && [ -n "$inc" ] && [ "$sst" -lt "$inc" ]; then echo OK; else echo "FAIL sst=$sst inc=$inc"; fi
      '
      The status should be success
      The output should equal "OK"
    End
  End
End
