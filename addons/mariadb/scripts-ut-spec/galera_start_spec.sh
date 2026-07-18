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
    unset GALERA_ORPHAN_JOINING_THRESHOLD_SECONDS
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

    It "does not treat a malformed safe_to_bootstrap value as safe (anchored match)"
      # A torn/corrupt write leaving 'safe_to_bootstrap: 10' must NOT satisfy
      # the safe=1 guard via substring match; pod-0 defers rather than
      # bootstrapping possibly-stale data.
      POD_NAME="mdb-galera-mariadb-0"
      write_grastate 7 10
      _any_peer_alive() {
        return 1
      }
      mariadbd() {
        printf "WSREP: Recovered position: 631a68d0-7697-11f1-923e-42be04dfa95f:7\n"
      }

      When call should_bootstrap
      The status should be failure
      The output should include "Refusing automatic Galera crash recovery bootstrap"
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

  Describe "orphan Joining self-heal (C6 E predicate)"
    setup_orphan() {
      export SOCK="${TEST_DIR}/mysqld.sock"
      ORPHAN_RESTART_CALLS=0
      ORPHAN_OBSERVE_CALLS=0
      ORPHAN_TEST_TOKEN=""
      KILL_SIGNALS_FILE="${TEST_DIR}/kill-signals"
      : > "${KILL_SIGNALS_FILE}"
    }
    cleanup_orphan() {
      unset SOCK GALERA_ORPHAN_JOINING_THRESHOLD_SECONDS
      unset ORPHAN_RESTART_CALLS ORPHAN_OBSERVE_CALLS ORPHAN_TEST_TOKEN
      unset ORPHAN_THRESHOLD_SECONDS ORPHAN_THRESHOLD_TICKS ORPHAN_MUTATION_ENABLED
      unset E_IDENTITY E_TOKEN E_COUNT E_ATTEMPTED_IDENTITY
      unset ORPHAN_OBS_IDENTITY ORPHAN_OBS_TOKEN ORPHAN_RESTART_RESULT
      unset ORPHAN_RESTART_MUTATION_ATTEMPTED
    }
    BeforeEach setup_orphan
    AfterEach cleanup_orphan

    exact_joining_status() {
      cat <<'EOF'
wsrep_local_state	1
wsrep_local_state_comment	Joining: receiving State Transfer
wsrep_cluster_status	Primary
wsrep_ready	OFF
wsrep_connected	ON
wsrep_last_committed	-1
wsrep_cluster_conf_id	7
wsrep_incoming_addresses	10.0.0.2:3306, 10.0.0.1:3306
EOF
    }

    observe_snapshot() {
      _orphan_joining_observe
      rc=$?
      printf 'identity=%s\ntoken=%s\nstate=%s\ncomment=%s\n' \
        "${ORPHAN_OBS_IDENTITY:-}" "${ORPHAN_OBS_TOKEN:-}" \
        "${GALERA_OBS_STATE:-}" "${GALERA_OBS_STATE_COMMENT:-}"
      return "${rc}"
    }

    It "reads the eight wsrep keys in one shipped-helper call and canonicalizes Joining/members"
      mariadb() {
        printf 'x' >> "${TEST_DIR}/mariadb-calls"
        printf '%s\n' "$*" > "${TEST_DIR}/mariadb-query-args"
        exact_joining_status
      }
      _galera_socket_present() { return 0; }
      _mariadbd_identity() { printf '4242:99\n'; return 0; }
      _galera_sst_process_absent() { return 0; }

      When call observe_snapshot
      The status should be success
      The output should include "identity=4242:99"
      The output should include "comment=Joining"
      The output should include "ready=OFF|connected=ON|last_committed=-1|conf_id=7|members=10.0.0.1:3306,10.0.0.2:3306"
      The contents of file "${TEST_DIR}/mariadb-calls" should equal "x"
      The contents of file "${TEST_DIR}/mariadb-query-args" should include "wsrep_local_state"
      The contents of file "${TEST_DIR}/mariadb-query-args" should include "wsrep_local_state_comment"
      The contents of file "${TEST_DIR}/mariadb-query-args" should include "wsrep_cluster_status"
      The contents of file "${TEST_DIR}/mariadb-query-args" should include "wsrep_ready"
      The contents of file "${TEST_DIR}/mariadb-query-args" should include "wsrep_connected"
      The contents of file "${TEST_DIR}/mariadb-query-args" should include "wsrep_last_committed"
      The contents of file "${TEST_DIR}/mariadb-query-args" should include "wsrep_cluster_conf_id"
      The contents of file "${TEST_DIR}/mariadb-query-args" should include "wsrep_incoming_addresses"
    End

    It "treats an incomplete keyed SQL receipt as unknown without leaking partial role state"
      mariadb() {
        exact_joining_status \
          | awk -F '\t' '
              $1 == "wsrep_local_state" { print $1 "\t4"; next }
              $1 == "wsrep_local_state_comment" { print $1 "\tSynced"; next }
              $1 != "wsrep_cluster_conf_id" { print }
            '
      }
      _galera_socket_present() { return 0; }

      incomplete_snapshot() {
        _orphan_joining_observe
        rc=$?
        printf 'state=%s\ncomment=%s\ncluster=%s\nready=%s\nconnected=%s\nlast=%s\nconf=%s\nmembers=%s\n' \
          "${GALERA_OBS_STATE:-}" "${GALERA_OBS_STATE_COMMENT:-}" \
          "${GALERA_OBS_CLUSTER_STATUS:-}" "${GALERA_OBS_READY:-}" \
          "${GALERA_OBS_CONNECTED:-}" "${GALERA_OBS_LAST_COMMITTED:-}" \
          "${GALERA_OBS_CONF_ID:-}" "${GALERA_OBS_MEMBERS:-}"
        if [ "${GALERA_OBS_STATE:-}" = "4" ] \
          && [ "${GALERA_OBS_CLUSTER_STATUS:-}" = "Primary" ]; then
          touch "${DATA_DIR}/.galera-synced"
        fi
        [ ! -e "${DATA_DIR}/.galera-synced" ] || return 1
        return "${rc}"
      }

      When call incomplete_snapshot
      The status should equal 2
      The output should equal "state=
comment=
cluster=
ready=
connected=
last=
conf=
members="
    End

    It "fails closed for each of the eight individually missing receipt keys"
      missing_key_matrix() {
        local missing rc
        while IFS= read -r missing; do
          mariadb() {
            exact_joining_status | grep -v "^${missing}"
          }
          _orphan_joining_observe >/dev/null 2>&1
          rc=$?
          printf '%s:%s:%s:%s\n' "${missing}" "${rc}" \
            "${GALERA_OBS_STATE:-}" "${GALERA_OBS_CLUSTER_STATUS:-}"
          [ "${rc}" -eq 2 ] || return 1
          [ -z "${GALERA_OBS_STATE:-}${GALERA_OBS_CLUSTER_STATUS:-}" ] || return 1
        done <<'EOF'
wsrep_local_state
wsrep_local_state_comment
wsrep_cluster_status
wsrep_ready
wsrep_connected
wsrep_last_committed
wsrep_cluster_conf_id
wsrep_incoming_addresses
EOF
      }
      _galera_socket_present() { return 0; }

      When call missing_key_matrix
      The status should be success
      The lines of output should equal 8
      The output should not include "Primary"
    End

    It "treats a present but empty required receipt value as unknown"
      mariadb() {
        exact_joining_status \
          | awk -F '\t' '$1 == "wsrep_cluster_conf_id" { print $1 "\t"; next } { print }'
      }
      _galera_socket_present() { return 0; }
      _mariadbd_identity() { printf '4242:99\n'; return 0; }
      _galera_sst_process_absent() { return 0; }

      When call _orphan_joining_observe
      The status should equal 2
    End

    It "accepts only exact numeric-state 1 plus canonical Joining"
      run_state_matrix() {
        local state comment expected rc
        while IFS='|' read -r state comment expected; do
          mariadb() {
            exact_joining_status \
              | awk -F '\t' -v state="${state}" -v comment="${comment}" '
                  $1 == "wsrep_local_state" { print $1 "\t" state; next }
                  $1 == "wsrep_local_state_comment" { print $1 "\t" comment; next }
                  { print }
                '
          }
          _orphan_joining_observe >/dev/null 2>&1
          rc=$?
          printf '%s:%s\n' "${state}:${comment}" "${rc}"
          [ "${rc}" -eq "${expected}" ] || return 1
        done <<'EOF'
1|Joining: receiving State Transfer|0
3|Joined|1
2|Donor/Desynced|1
0|Initialized|1
4|Synced|1
1|joining: receiving State Transfer|1
EOF
      }
      _galera_socket_present() { return 0; }
      _mariadbd_identity() { printf '4242:99\n'; return 0; }
      _galera_sst_process_absent() { return 0; }

      When call run_state_matrix
      The status should be success
      The lines of output should equal 6
    End

    It "does not classify E while the SST marker exists"
      mariadb() { exact_joining_status; }
      _galera_socket_present() { return 0; }
      _mariadbd_identity() { printf '4242:99\n'; return 0; }
      _galera_sst_process_absent() { return 0; }
      touch "${DATA_DIR}/sst_in_progress"

      When call _orphan_joining_observe
      The status should equal 1
    End

    It "does not classify E while a wsrep_sst helper exists"
      mariadb() { exact_joining_status; }
      _galera_socket_present() { return 0; }
      _mariadbd_identity() { printf '4242:99\n'; return 0; }
      _galera_sst_process_absent() { return 1; }

      When call _orphan_joining_observe
      The status should equal 1
    End

    It "treats pgrep errors as unknown rather than falling back"
      pgrep() { return 2; }
      pidof() { printf '4242\n'; return 0; }

      When call _mariadbd_identity
      The status should equal 2
      The output should equal ""
    End

    It "treats multiple mariadbd PIDs as unknown"
      pgrep() { printf '4242\n4343\n'; return 0; }
      _read_proc_starttime() { printf '99\n'; }

      When call _mariadbd_identity
      The status should equal 2
      The output should equal ""
    End

    It "treats proc-stat read failure as unknown"
      pgrep() { printf '4242\n'; return 0; }
      _read_proc_starttime() { return 1; }

      When call _mariadbd_identity
      The status should equal 2
      The output should equal ""
    End

    It "defaults the threshold to 90s and rounds a positive decimal up to 3s ticks"
      threshold_matrix() {
        _orphan_joining_tracker_init || return 1
        printf '%s:%s:%s\n' "${ORPHAN_THRESHOLD_SECONDS}" "${ORPHAN_THRESHOLD_TICKS}" "${ORPHAN_MUTATION_ENABLED}"
        GALERA_ORPHAN_JOINING_THRESHOLD_SECONDS=4
        _orphan_joining_tracker_init || return 1
        printf '%s:%s:%s\n' "${ORPHAN_THRESHOLD_SECONDS}" "${ORPHAN_THRESHOLD_TICKS}" "${ORPHAN_MUTATION_ENABLED}"
        GALERA_ORPHAN_JOINING_THRESHOLD_SECONDS=100000000000000000000
        _orphan_joining_tracker_init || return 1
        printf '%s:%s:%s\n' "${ORPHAN_THRESHOLD_SECONDS}" "${ORPHAN_THRESHOLD_TICKS}" "${ORPHAN_MUTATION_ENABLED}"
      }

      When call threshold_matrix
      The status should be success
      The line 1 of output should equal "90:30:1"
      The line 2 of output should equal "4:2:1"
      The line 3 of output should equal "100000000000000000000:33333333333333333334:1"
    End

    It "disables E mutation for nonnumeric, zero, and negative thresholds"
      invalid_threshold_matrix() {
        local value
        for value in bad 0 -3; do
          GALERA_ORPHAN_JOINING_THRESHOLD_SECONDS="${value}"
          _orphan_joining_tracker_init >/dev/null
          printf '%s:%s\n' "${value}" "${ORPHAN_MUTATION_ENABLED}"
          [ "${ORPHAN_MUTATION_ENABLED}" = "0" ] || return 1
        done
      }

      When call invalid_threshold_matrix
      The status should be success
      The output should include "bad:0"
      The output should include "0:0"
      The output should include "-3:0"
    End

    It "is a behavior OLD RED on parent exact: two 3s-boundary E samples call restart once"
      two_exact_ticks() {
        GALERA_ORPHAN_JOINING_THRESHOLD_SECONDS=3
        E_COUNT=0
        _orphan_joining_tracker_init || return 1
        _orphan_joining_observe() {
          ORPHAN_OBS_IDENTITY='4242:99'
          ORPHAN_OBS_TOKEN='4242:99|ready=OFF|connected=ON|last_committed=-1|conf_id=7|members=a,b'
          return 0
        }
        _restart_orphan_joiner() {
          ORPHAN_RESTART_CALLS=$((ORPHAN_RESTART_CALLS + 1))
          ORPHAN_RESTART_RESULT='restart_effective'
          ORPHAN_RESTART_MUTATION_ATTEMPTED=1
          return 0
        }
        _orphan_joining_watcher_tick
        printf 'sample1_calls=%s count=%s\n' "${ORPHAN_RESTART_CALLS}" "${E_COUNT}"
        [ "${ORPHAN_RESTART_CALLS}" -eq 0 ] || return 1
        [ "${E_COUNT}" = "0" ] || return 1
        _orphan_joining_watcher_tick
        printf 'calls=%s result=%s\n' "${ORPHAN_RESTART_CALLS}" "${ORPHAN_RESTART_RESULT}"
      }

      When call two_exact_ticks
      The status should be success
      The output should include "sample1_calls=0 count=0"
      The output should include "calls=1 result=restart_effective"
    End

    It "requires 30 completed 3s intervals: samples 1-30 do not mutate and sample 31 does once"
      ninety_second_boundary() {
        GALERA_ORPHAN_JOINING_THRESHOLD_SECONDS=90
        _orphan_joining_tracker_init || return 1
        _orphan_joining_observe() {
          ORPHAN_OBS_IDENTITY='4242:99'
          ORPHAN_OBS_TOKEN='stable-token'
          return 0
        }
        _restart_orphan_joiner() {
          ORPHAN_RESTART_CALLS=$((ORPHAN_RESTART_CALLS + 1))
          ORPHAN_RESTART_RESULT='restart_effective'
          ORPHAN_RESTART_MUTATION_ATTEMPTED=1
          return 0
        }
        local sample
        for sample in $(seq 1 30); do
          _orphan_joining_watcher_tick
        done
        printf 'sample30_calls=%s count=%s\n' "${ORPHAN_RESTART_CALLS}" "${E_COUNT}"
        [ "${ORPHAN_RESTART_CALLS}" -eq 0 ] || return 1
        _orphan_joining_watcher_tick
        printf 'sample31_calls=%s\n' "${ORPHAN_RESTART_CALLS}"
      }

      When call ninety_second_boundary
      The status should be success
      The output should include "sample30_calls=0 count=29"
      The output should include "sample31_calls=1"
    End

    It "resets the timer when E_TOKEN changes"
      token_change_resets() {
        GALERA_ORPHAN_JOINING_THRESHOLD_SECONDS=3
        _orphan_joining_tracker_init || return 1
        _orphan_joining_observe() {
          ORPHAN_OBSERVE_CALLS=$((ORPHAN_OBSERVE_CALLS + 1))
          ORPHAN_OBS_IDENTITY='4242:99'
          if [ "${ORPHAN_OBSERVE_CALLS}" -eq 1 ]; then
            ORPHAN_OBS_TOKEN='token-a'
          else
            ORPHAN_OBS_TOKEN='token-b'
          fi
          return 0
        }
        _restart_orphan_joiner() {
          ORPHAN_RESTART_CALLS=$((ORPHAN_RESTART_CALLS + 1))
          ORPHAN_RESTART_RESULT='restart_effective'
          ORPHAN_RESTART_MUTATION_ATTEMPTED=1
          return 0
        }
        _orphan_joining_watcher_tick
        _orphan_joining_watcher_tick
        [ "${ORPHAN_RESTART_CALLS}" -eq 0 ] || return 1
        _orphan_joining_watcher_tick
        printf 'calls=%s count=%s token=%s\n' "${ORPHAN_RESTART_CALLS}" "${E_COUNT}" "${E_TOKEN}"
      }

      When call token_change_resets
      The status should be success
      The output should include "calls=1"
    End

    It "cancels with mutation=0 when action-time identity or predicate changed"
      _orphan_joining_observe() {
        ORPHAN_OBS_IDENTITY='5252:100'
        ORPHAN_OBS_TOKEN='new-token'
        return 0
      }
      kill() { printf '%s\n' "$*" >> "${KILL_SIGNALS_FILE}"; }

      When call _restart_orphan_joiner '4242:99' 'old-token'
      The status should be success
      The output should include "action=restart_canceled"
      The contents of file "${KILL_SIGNALS_FILE}" should equal ""
    End

    It "cancels with mutation=0 when the action-time progress token changed"
      _orphan_joining_observe() {
        ORPHAN_OBS_IDENTITY='4242:99'
        ORPHAN_OBS_TOKEN='progressed-token'
        return 0
      }
      kill() { printf '%s\n' "$*" >> "${KILL_SIGNALS_FILE}"; }

      When call _restart_orphan_joiner '4242:99' 'stalled-token'
      The status should be success
      The output should include "action=restart_canceled"
      The output should include "predicate_identity_or_token_changed"
      The contents of file "${KILL_SIGNALS_FILE}" should equal ""
    End

    It "proves TERM effective only after the old identity disappears"
      _orphan_joining_observe() {
        ORPHAN_OBS_IDENTITY='4242:99'
        ORPHAN_OBS_TOKEN='same-token'
        return 0
      }
      _mariadbd_identity() { return 1; }
      kill() { printf '%s\n' "$*" >> "${KILL_SIGNALS_FILE}"; return 0; }
      sleep() { :; }

      When call _restart_orphan_joiner '4242:99' 'same-token'
      The status should be success
      The output should include "action=restart_attempted"
      The output should include "action=restart_effective"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-TERM 4242"
      The contents of file "${KILL_SIGNALS_FILE}" should not include "-KILL"
    End

    It "treats same PID with a new proc starttime after TERM as a replaced identity"
      _orphan_joining_observe() {
        ORPHAN_OBS_IDENTITY='4242:99'
        ORPHAN_OBS_TOKEN='same-token'
        return 0
      }
      _mariadbd_identity() { printf '4242:100\n'; return 0; }
      kill() { printf '%s\n' "$*" >> "${KILL_SIGNALS_FILE}"; return 0; }
      sleep() { :; }

      When call _restart_orphan_joiner '4242:99' 'same-token'
      The status should be success
      The output should include "action=restart_effective"
      The output should include "signal=TERM"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-TERM 4242"
      The contents of file "${KILL_SIGNALS_FILE}" should not include "-KILL"
    End

    It "reports TERM command failure and does not escalate"
      _orphan_joining_observe() {
        ORPHAN_OBS_IDENTITY='4242:99'
        ORPHAN_OBS_TOKEN='same-token'
        return 0
      }
      kill() { printf '%s\n' "$*" >> "${KILL_SIGNALS_FILE}"; return 1; }
      sleep() { :; }

      When call _restart_orphan_joiner '4242:99' 'same-token'
      The status should be failure
      The output should include "reason=term_signal_failed"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-TERM 4242"
      The contents of file "${KILL_SIGNALS_FILE}" should not include "-KILL"
    End

    It "proves KILL effective when the old identity survives TERM then changes"
      _orphan_joining_observe() {
        ORPHAN_OBS_IDENTITY='4242:99'
        ORPHAN_OBS_TOKEN='same-token'
        return 0
      }
      _mariadbd_identity() {
        local count=0
        [ ! -s "${TEST_DIR}/identity-count" ] || count=$(cat "${TEST_DIR}/identity-count")
        count=$((count + 1))
        printf '%s\n' "${count}" > "${TEST_DIR}/identity-count"
        if [ "${count}" -le 6 ]; then
          printf '4242:99\n'
        else
          printf '4242:100\n'
        fi
        return 0
      }
      kill() { printf '%s\n' "$*" >> "${KILL_SIGNALS_FILE}"; return 0; }
      sleep() { :; }

      When call _restart_orphan_joiner '4242:99' 'same-token'
      The status should be success
      The output should include "action=restart_effective"
      The output should include "signal=KILL"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-TERM 4242"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-KILL 4242"
    End

    It "reports KILL command failure after TERM did not replace the identity"
      _orphan_joining_observe() {
        ORPHAN_OBS_IDENTITY='4242:99'
        ORPHAN_OBS_TOKEN='same-token'
        return 0
      }
      _mariadbd_identity() { printf '4242:99\n'; return 0; }
      kill() {
        printf '%s\n' "$*" >> "${KILL_SIGNALS_FILE}"
        [ "$1" != "-KILL" ]
      }
      sleep() { :; }

      When call _restart_orphan_joiner '4242:99' 'same-token'
      The status should be failure
      The output should include "reason=kill_signal_failed"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-TERM 4242"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-KILL 4242"
    End

    It "escalates once to KILL and reports failed when the old identity remains"
      _orphan_joining_observe() {
        ORPHAN_OBS_IDENTITY='4242:99'
        ORPHAN_OBS_TOKEN='same-token'
        return 0
      }
      _mariadbd_identity() { printf '4242:99\n'; return 0; }
      kill() { printf '%s\n' "$*" >> "${KILL_SIGNALS_FILE}"; return 0; }
      sleep() { :; }

      When call _restart_orphan_joiner '4242:99' 'same-token'
      The status should be failure
      The output should include "action=restart_failed"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-TERM 4242"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-KILL 4242"
    End

    It "fails closed without KILL when identity becomes unknown after TERM"
      _orphan_joining_observe() {
        ORPHAN_OBS_IDENTITY='4242:99'
        ORPHAN_OBS_TOKEN='same-token'
        return 0
      }
      _mariadbd_identity() { return 2; }
      kill() { printf '%s\n' "$*" >> "${KILL_SIGNALS_FILE}"; return 0; }
      sleep() { :; }

      When call _restart_orphan_joiner '4242:99' 'same-token'
      The status should be failure
      The output should include "reason=identity_unknown_before_kill"
      The contents of file "${KILL_SIGNALS_FILE}" should include "-TERM 4242"
      The contents of file "${KILL_SIGNALS_FILE}" should not include "-KILL"
    End

    It "latches a failed identity so later exact E ticks do not kill it again"
      failed_identity_latched() {
        GALERA_ORPHAN_JOINING_THRESHOLD_SECONDS=3
        _orphan_joining_tracker_init || return 1
        _orphan_joining_observe() {
          ORPHAN_OBS_IDENTITY='4242:99'
          ORPHAN_OBS_TOKEN='same-token'
          return 0
        }
        _restart_orphan_joiner() {
          ORPHAN_RESTART_CALLS=$((ORPHAN_RESTART_CALLS + 1))
          ORPHAN_RESTART_RESULT='restart_failed'
          ORPHAN_RESTART_MUTATION_ATTEMPTED=1
          return 1
        }
        _orphan_joining_watcher_tick
        _orphan_joining_watcher_tick
        printf 'calls=%s latched=%s\n' "${ORPHAN_RESTART_CALLS}" "${E_ATTEMPTED_IDENTITY}"
      }

      When call failed_identity_latched
      The status should be success
      The output should include "calls=1 latched=4242:99"
    End
  End

  Describe "wsrep_sst_auth is not persisted (H11)"
    # rsync SST does not use wsrep_sst_auth; writing it to DATA_DIR (a
    # needSnapshot volume) leaked the plaintext root password into snapshots.

    It "does not write wsrep_sst_auth to any file"
      When run sh -c "grep -nE 'wsrep_sst_auth=.*>|> +\"?\\\$?\\{?sst_conf' \"$(script_file)\" || true"
      The status should be success
      The output should equal ""
    End

    It "does not load a defaults-extra-file for SST auth"
      When run sh -c "grep -F 'defaults-extra-file=' \"$(script_file)\" | grep -F 'sst' || true"
      The status should be success
      The output should equal ""
    End

    It "removes any stale .galera-sst-auth.cnf left by a previous chart version"
      When call script_contains "rm -f \"\${DATA_DIR}/.galera-sst-auth.cnf\""
      The status should be success
      The output should include ".galera-sst-auth.cnf"
    End
  End

  Describe "graceful-shutdown self-heal guard"
    # Behavioral test: with the shutdown marker present the self-heal helper
    # must NOT kill mariadbd (0 kills); without it, it must kill (>=1). Stub the
    # pid lookup and the actual signal so we count kill attempts.
    setup_guard() {
      GUARD_DIR="$(mktemp -d)"
      export DATA_DIR="${GUARD_DIR}"
      KILL_COUNT_FILE="${GUARD_DIR}/kills"
      : > "${KILL_COUNT_FILE}"
      _mariadbd_pids() { echo 4242; }
      kill() { printf 'x' >> "${KILL_COUNT_FILE}"; }
      sleep() { :; }
    }
    cleanup_guard() { rm -rf "${GUARD_DIR}"; unset DATA_DIR; }
    BeforeEach setup_guard
    AfterEach cleanup_guard

    It "does not kill mariadbd while a graceful shutdown is in progress"
      touch "${DATA_DIR}/.galera-shutting-down"

      When call _restart_mariadbd_for_self_heal "test-reason"
      The status should be success
      The output should include "graceful shutdown in progress"
      The contents of file "${KILL_COUNT_FILE}" should equal ""
    End

    It "kills mariadbd when no graceful shutdown is in progress"
      When call _restart_mariadbd_for_self_heal "test-reason"
      The status should be success
      The output should include "SIGTERM"
      The contents of file "${KILL_COUNT_FILE}" should not equal ""
    End

    # Behavioral test of the watcher start-up marker reset: seed all three
    # stale markers a previous container generation could leave on the PV, call
    # the extracted helper main() runs at watcher start, and assert every marker
    # is gone. This exercises the shipped code path (not a source grep), so a
    # future drift in which markers get cleared — including dropping the
    # .galera-shutting-down removal that would otherwise disable self-heal for
    # the new container's whole lifetime — fails the test.
    It "clears stale role/synced/shutting-down markers at watcher start"
      touch "${DATA_DIR}/.galera-synced"
      touch "${DATA_DIR}/.galera-role"
      touch "${DATA_DIR}/.galera-shutting-down"

      When call _clear_stale_markers_on_start
      The status should be success
      The path "${DATA_DIR}/.galera-synced" should not be exist
      The path "${DATA_DIR}/.galera-role" should not be exist
      The path "${DATA_DIR}/.galera-shutting-down" should not be exist
    End
  End
End
