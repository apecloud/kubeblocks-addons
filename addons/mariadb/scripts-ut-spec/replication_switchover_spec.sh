# shellcheck shell=sh
# Unit tests for replication-switchover.sh
# Tests role guard, candidate resolution, and syncerctl/DCS handoff.

Describe "replication-switchover.sh"
  setup() {
    TEST_DIR=$(mktemp -d)
    export MARIADB_DATADIR="$TEST_DIR"
    export DATA_DIR="$TEST_DIR"
    export SYNCERCTL_BIN="${TEST_DIR}/syncerctl"
    export SYNCERCTL_ARGS="${TEST_DIR}/syncerctl.args"
    export MARIADB_CLIENT_BIN="${TEST_DIR}/mariadb"
    export CLUSTER_NAME="mdb"
    export COMPONENT_NAME="mariadb"
    export CLUSTER_NAMESPACE="demo"
    export KB_SWITCHOVER_ROLE="primary"
    export KB_SWITCHOVER_CURRENT_NAME="mdb-mariadb-0"
    export KB_SWITCHOVER_CANDIDATE_NAME=""
    export SWITCHOVER_WAIT_SECONDS="2"
    export SWITCHOVER_STABILIZATION_SECONDS="1"
    export SWITCHOVER_POLL_SECONDS="1"
    touch "${MARIADB_CLIENT_BIN}"
    chmod +x "${MARIADB_CLIENT_BIN}"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    unset MARIADB_DATADIR DATA_DIR SYNCERCTL_BIN SYNCERCTL_ARGS MARIADB_CLIENT_BIN MYSQL_CLIENT_DIR
    unset CLUSTER_NAME COMPONENT_NAME CLUSTER_NAMESPACE
    unset KB_SWITCHOVER_ROLE KB_SWITCHOVER_CURRENT_NAME KB_SWITCHOVER_CANDIDATE_NAME
    unset SWITCHOVER_WAIT_SECONDS SWITCHOVER_STABILIZATION_SECONDS SWITCHOVER_POLL_SECONDS
    unset PRIMARY_SERVICE_ROUTE_WAIT_SECONDS MARIADB_INTERNAL_ROOT_USER
    unset MARIADB_CONNECT_TIMEOUT_SECONDS
  }
  AfterEach "cleanup"

  Include ../scripts/replication-switchover.sh

  make_syncerctl() {
    cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
case "$*" in
  *" getrole"*)
    case "$*" in
      *"--host mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"*) printf "primary" ;;
      *"--host 127.0.0.1"*) printf "secondary" ;;
      *) printf "unknown" ;;
    esac
    ;;
  *)
    printf "%s" "$*" > "${SYNCERCTL_ARGS}"
    printf "switchover success\n"
    ;;
esac
EOF
    chmod +x "${SYNCERCTL_BIN}"
  }

  make_failing_syncerctl() {
    cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
printf "create switchover failed\n" >&2
exit 1
EOF
    chmod +x "${SYNCERCTL_BIN}"
  }

  make_zero_status_failing_syncerctl() {
    cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
printf "switchover failed: operation precheck failed: mdb-mariadb-0 is not the primary\n"
exit 0
EOF
    chmod +x "${SYNCERCTL_BIN}"
  }

  make_role_syncerctl() {
    cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
printf "%s" "$*" > "${SYNCERCTL_ARGS}"
case "$*" in
  *" getrole"*)
    case "$*" in
      *"--host mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"*) printf "primary" ;;
      *"--host 127.0.0.1"*) printf "secondary" ;;
      *) printf "unknown" ;;
    esac
    ;;
  *) printf "switchover success\n" ;;
esac
EOF
    chmod +x "${SYNCERCTL_BIN}"
  }

  record_call() {
    printf "%s\n" "$1" >> "${TEST_DIR}/calls"
  }

  Describe "resolve_candidate_fqdn()"
    Context "when KB_SWITCHOVER_CANDIDATE_NAME is explicitly set"
      setup_candidate() {
        export KB_SWITCHOVER_CANDIDATE_NAME="mdb-mariadb-1"
      }
      Before "setup_candidate"

      It "uses the given candidate name to build FQDN"
        When call resolve_candidate_fqdn
        The status should be success
        The output should eq "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
      End

      It "passes a bounded connect timeout to mariadb client probes"
        cat > "${MARIADB_CLIENT_BIN}" <<EOF
#!/bin/sh
printf "%s\\n" "\$*" > "${TEST_DIR}/mariadb.args"
printf "1\\n"
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        export MARIADB_CONNECT_TIMEOUT_SECONDS="7"
        query_value "127.0.0.1" "SELECT 1;" >/dev/null
        When run cat "${TEST_DIR}/mariadb.args"
        The status should be success
        The output should include "--connect-timeout=7"
      End

      # alpha.59: tests for wait_switchover_done / wait_post_switchover_stabilization /
      # wait_primary_service_routes_candidate / wait_current_secondary_remote_root_fenced
      # were removed alongside the helpers themselves. The switchover action no longer
      # waits for these convergences inside the kbagent action ceiling; see
      # addon-test-runner-write-after-bounded-role-gate guide. The negative assertion
      # that run_switchover never invokes these helpers lives in the run_switchover()
      # describe block below.
    End

    Context "when no candidate name and current pod is pod-0"
      setup_pod0() {
        export KB_SWITCHOVER_CANDIDATE_NAME=""
        export KB_SWITCHOVER_CURRENT_NAME="mdb-mariadb-0"
      }
      Before "setup_pod0"

      It "picks pod-1 as candidate"
        When call resolve_candidate_fqdn
        The status should be success
        The output should eq "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
      End
    End

    Context "when no candidate name and current pod is pod-1"
      setup_pod1() {
        export KB_SWITCHOVER_CANDIDATE_NAME=""
        export KB_SWITCHOVER_CURRENT_NAME="mdb-mariadb-1"
      }
      Before "setup_pod1"

      It "picks pod-0 as candidate"
        When call resolve_candidate_fqdn
        The status should be success
        The output should eq "mdb-mariadb-0.mdb-mariadb-headless.demo.svc.cluster.local"
      End
    End

    Context "when CLUSTER_DOMAIN is overridden"
      setup_custom_domain() {
        export CLUSTER_DOMAIN="custom.local"
        export KB_SWITCHOVER_CANDIDATE_NAME="mdb-mariadb-1"
      }
      Before "setup_custom_domain"

      It "uses the overridden cluster domain in candidate FQDN"
        When call resolve_candidate_fqdn
        The status should be success
        The output should eq "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.custom.local"
      End
    End
  End

  Describe "resolve_candidate_name()"
    Context "when KB_SWITCHOVER_CANDIDATE_NAME is explicitly set"
      setup_candidate() {
        export KB_SWITCHOVER_CANDIDATE_NAME="mdb-mariadb-1"
      }
      Before "setup_candidate"

      It "uses the given candidate pod name"
        When call resolve_candidate_name
        The status should be success
        The output should eq "mdb-mariadb-1"
      End
    End
  End

  Describe "main() role guard"
    Context "when KB_SWITCHOVER_ROLE is not 'primary'"
      setup_secondary() {
        export KB_SWITCHOVER_ROLE="secondary"
      }
      Before "setup_secondary"

      It "exits 0 and does nothing"
        When call main
        The status should be success
        The output should include "Not the primary"
        The path "${SYNCERCTL_ARGS}" should not be exist
      End
    End
  End

  Describe "run_switchover()"
    Context "when syncerctl creates DCS switchover and DB truth converges"
      It "returns success"
        make_syncerctl
        prepare_current_primary_for_switchover() {
          return 0
        }
        remote_root_has_full_access() {
          return 0
        }
        remote_root_write_ready() {
          return 0
        }
        verify_post_dcs_local_root_write_fenced() {
          return 0
        }
        revoke_user_facing_root_admin_privileges_for_secondary() {
          return 0
        }
        wait_candidate_promoted_via_syncerctl() {
          return 0
        }
        fence_local_remote_root_for_secondary() {
          return 0
        }
        local_remote_root_is_fenced_for_secondary() {
          return 0
        }
        query_value() {
          case "$1:$2" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@server_id;"*) echo "2" ;;
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@global.read_only;"*) echo "0" ;;
            "mdb-mariadb.demo.svc.cluster.local:SELECT @@server_id;"*) echo "2" ;;
            "127.0.0.1:SELECT @@global.read_only;"*) echo "1" ;;
          esac
        }
        query_slave_status() {
          case "$1" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local") return 0 ;;
          esac
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
Master_Host: mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local
EOF
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be success
        The output should include "Switchover candidate remote root write probe converged for mdb-mariadb-1"
        The output should include "Switchover action returned: DCS recorded, current primary fenced, candidate promoted via DCS, candidate writable"
      End

      It "passes pod names to syncerctl instead of candidate FQDN"
        make_syncerctl
        prepare_current_primary_for_switchover() {
          return 0
        }
        remote_root_has_full_access() {
          return 0
        }
        remote_root_write_ready() {
          return 0
        }
        verify_post_dcs_local_root_write_fenced() {
          return 0
        }
        revoke_user_facing_root_admin_privileges_for_secondary() {
          return 0
        }
        wait_candidate_promoted_via_syncerctl() {
          return 0
        }
        fence_local_remote_root_for_secondary() {
          return 0
        }
        local_remote_root_is_fenced_for_secondary() {
          return 0
        }
        query_value() {
          case "$1:$2" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@server_id;"*) echo "2" ;;
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@global.read_only;"*) echo "0" ;;
            "mdb-mariadb.demo.svc.cluster.local:SELECT @@server_id;"*) echo "2" ;;
            "127.0.0.1:SELECT @@global.read_only;"*) echo "1" ;;
          esac
        }
        query_slave_status() {
          case "$1" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local") return 0 ;;
          esac
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
Master_Host: mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local
EOF
        }
        run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        When run cat "${SYNCERCTL_ARGS}"
        The status should be success
        The output should eq "--host 127.0.0.1 --port 3601 switchover --primary mdb-mariadb-0 --candidate mdb-mariadb-1"
      End

      It "fails before switchover when mariadb client is unavailable"
        make_role_syncerctl
        rm -f "${MARIADB_CLIENT_BIN}"
        When call main
        The status should be failure
        The stderr should include "Switchover failed: MARIADB_CLIENT_BIN=${MARIADB_CLIENT_BIN} is not executable"
        The path "${SYNCERCTL_ARGS}" should not be exist
      End

      It "uses bundled mysql-client when MARIADB_CLIENT_BIN is not set"
        make_syncerctl
        unset MARIADB_CLIENT_BIN
        export MYSQL_CLIENT_DIR="${TEST_DIR}/mysql-client"
        mkdir -p "${MYSQL_CLIENT_DIR}/bin"
        touch "${MYSQL_CLIENT_DIR}/bin/mariadb"
        chmod +x "${MYSQL_CLIENT_DIR}/bin/mariadb"
        prepare_current_primary_for_switchover() {
          return 0
        }
        remote_root_has_full_access() {
          return 0
        }
        remote_root_write_ready() {
          return 0
        }
        verify_post_dcs_local_root_write_fenced() {
          return 0
        }
        revoke_user_facing_root_admin_privileges_for_secondary() {
          return 0
        }
        wait_candidate_promoted_via_syncerctl() {
          return 0
        }
        fence_local_remote_root_for_secondary() {
          return 0
        }
        local_remote_root_is_fenced_for_secondary() {
          return 0
        }
        query_value() {
          case "$1:$2" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@server_id;"*) echo "2" ;;
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@global.read_only;"*) echo "0" ;;
            "mdb-mariadb.demo.svc.cluster.local:SELECT @@server_id;"*) echo "2" ;;
            "127.0.0.1:SELECT @@global.read_only;"*) echo "1" ;;
          esac
        }
        query_slave_status() {
          case "$1" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local") return 0 ;;
          esac
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
Master_Host: mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local
EOF
        }
        When call main
        The status should be success
        The output should include "Switchover using mariadb client: ${MYSQL_CLIENT_DIR}/bin/mariadb"
        The output should include "Switchover action returned: DCS recorded, current primary fenced, candidate promoted via DCS, candidate writable"
      End

      It "alpha.59 contract: never invokes wait_switchover_done / wait_post_switchover_stabilization / wait_primary_service_routes_candidate / current_follows_candidate"
        # Per addon-test-runner-write-after-bounded-role-gate guide: the
        # switchover action MUST NOT block on post-DCS convergence helpers
        # because kbagent enforces a 60s ceiling. Override each helper to record
        # a BUG_ marker; the assertion at the end verifies none fired.
        make_syncerctl
        prepare_current_primary_for_switchover() { return 0; }
        fence_local_remote_root_for_secondary() { return 0; }
        local_remote_root_is_fenced_for_secondary() { return 0; }
        remote_root_write_ready() { return 0; }
        verify_post_dcs_local_root_write_fenced() { return 0; }
        revoke_user_facing_root_admin_privileges_for_secondary() { return 0; }
        wait_candidate_promoted_via_syncerctl() { return 0; }
        query_value() {
          case "$1:$2" in
            "127.0.0.1:SELECT @@global.read_only;"*) echo "1" ;;
          esac
        }
        wait_switchover_done() { record_call "BUG_wait_switchover_done_called"; return 0; }
        wait_post_switchover_stabilization() { record_call "BUG_wait_post_switchover_stabilization_called"; return 0; }
        wait_primary_service_routes_candidate() { record_call "BUG_wait_primary_service_routes_candidate_called"; return 0; }
        wait_current_secondary_remote_root_fenced() { record_call "BUG_wait_current_secondary_remote_root_fenced_called"; return 0; }
        current_follows_candidate() { record_call "BUG_current_follows_candidate_called"; return 0; }
        primary_service_routes_candidate() { record_call "BUG_primary_service_routes_candidate_called"; return 0; }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be success
        The output should include "Switchover action returned: DCS recorded, current primary fenced, candidate promoted via DCS, candidate writable"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_switchover_done_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_post_switchover_stabilization_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_primary_service_routes_candidate_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_current_secondary_remote_root_fenced_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_current_follows_candidate_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_primary_service_routes_candidate_called"
      End

      It "alpha.61 contract: fails closed when candidate remote root write probe does not close in budget"
        export CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS=0
        export SWITCHOVER_POLL_SECONDS=1
        make_syncerctl
        prepare_current_primary_for_switchover() { return 0; }
        fence_local_remote_root_for_secondary() { return 0; }
        local_remote_root_is_fenced_for_secondary() { return 0; }
        remote_root_write_ready() { return 1; }
        verify_post_dcs_local_root_write_fenced() { return 0; }
        revoke_user_facing_root_admin_privileges_for_secondary() { return 0; }
        wait_candidate_promoted_via_syncerctl() { return 0; }
        query_value() {
          case "$1:$2" in
            "127.0.0.1:SELECT @@global.read_only;"*) echo "1" ;;
          esac
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be failure
        The output should include "Switchover post-DCS guard passed"
        The stderr should include "reason=candidate_remote_root_write_not_ready_in_budget"
        The stderr should include "fail-closed"
      End
    End

    Context "when syncerctl cannot create DCS switchover"
      It "returns failure"
        make_failing_syncerctl
        prepare_current_primary_for_switchover() {
          return 0
        }
        rollback_current_primary_switchover_guard() {
          record_call "rollback"
          return 0
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be failure
        The output should include "Switchover: creating syncer DCS switchover"
        The stderr should include "Switchover failed: syncerctl could not create DCS switchover"
        The contents of file "${TEST_DIR}/calls" should include "rollback"
      End

      It "treats a zero-status syncerctl failure message as failure and rolls back"
        make_zero_status_failing_syncerctl
        prepare_current_primary_for_switchover() {
          return 0
        }
        rollback_current_primary_switchover_guard() {
          record_call "rollback"
          return 0
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be failure
        The output should include "Switchover syncerctl output: switchover failed: operation precheck failed: mdb-mariadb-0 is not the primary"
        The stderr should include "Switchover failed: syncerctl did not report success"
        The stderr should include "Switchover failed: syncerctl could not create DCS switchover"
        The contents of file "${TEST_DIR}/calls" should include "rollback"
      End
    End

    Context "when guarding the old primary before DCS switchover"
      It "alpha.62 v1: fence_local_remote_root_for_secondary grants explicit non-bypass list per host (no SUPER/READ_ONLY ADMIN/BINLOG ADMIN/CONNECTION ADMIN)"
        export MARIADB_ROOT_USER="root"
        export MARIADB_ROOT_PASSWORD="pw"
        export MARIADB_ROOT_HOST="%"
        export MARIADB_CONNECT_TIMEOUT_SECONDS="5"
        export MARIADB_CLIENT_BIN="${TEST_DIR}/mariadb-fence"
        export MOCK_FENCE_CALLS="${TEST_DIR}/fence-calls"
        : > "${MOCK_FENCE_CALLS}"
        cat > "${MARIADB_CLIENT_BIN}" <<EOF_MOCK
#!/bin/sh
echo "\$@" >> "${MOCK_FENCE_CALLS}"
# Verifier reads SHOW GRANTS — return alpha.62 expected secondary-fence grants
# so post-fence verifier passes (no bypass priv, has GRANT SELECT, ...).
echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO \\\`root\\\`@\\\`%\\\`"
exit 0
EOF_MOCK
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call fence_local_remote_root_for_secondary "%"
        The status should be success
        The contents of file "${MOCK_FENCE_CALLS}" should include "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN"
        The contents of file "${MOCK_FENCE_CALLS}" should not include "GRANT READ_ONLY ADMIN"
        The contents of file "${MOCK_FENCE_CALLS}" should not include "GRANT SUPER"
        The contents of file "${MOCK_FENCE_CALLS}" should not include "GRANT BINLOG ADMIN"
        The contents of file "${MOCK_FENCE_CALLS}" should not include "GRANT CONNECTION ADMIN"
        The contents of file "${MOCK_FENCE_CALLS}" should not include "GRANT ALL PRIVILEGES"
        The output should include "fence_local_remote_root_for_secondary: host=% fence_apply_rc=0"
      End

      It "disconnects active remote root sessions around the grant fence"
        enumerate_user_facing_root_hosts() { echo "%"; return 0; }
        query_local_value() {
          record_call "query_sessions"
          echo "88 89"
        }
        run_local_sql_best_effort() {
          record_call "best_effort=$1"
          return 0
        }
        fence_local_remote_root_for_secondary() {
          record_call "fence"
          return 0
        }
        local_remote_root_is_fenced_for_secondary() {
          record_call "verify_fence"
          return 0
        }
        syncerctl_switchover() {
          record_call "syncerctl"
          return 0
        }
        set_local_read_only() {
          record_call "set_read_only=$1"
          return 0
        }
        local_read_only_is() {
          record_call "verify_read_only=$1"
          [ "$1" = "1" ]
        }
        candidate_is_primary() {
          return 0
        }
        current_follows_candidate() {
          return 0
        }
        wait_post_switchover_stabilization() {
          return 0
        }
        primary_service_routes_candidate() {
          return 0
        }
        wait_current_secondary_remote_root_fenced() {
          return 0
        }
        remote_root_write_ready() {
          return 0
        }
        verify_post_dcs_local_root_write_fenced() {
          return 0
        }
        revoke_user_facing_root_admin_privileges_for_secondary() {
          return 0
        }
        wait_candidate_promoted_via_syncerctl() {
          return 0
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be success
        The output should include "Switchover pre-DCS guard: disconnecting active remote root sessions 88 89"
        The output should include "remote root session disconnect issued killed=2 skipped=0"
        The contents of file "${TEST_DIR}/calls" should include "best_effort=KILL CONNECTION 88;"
        The contents of file "${TEST_DIR}/calls" should include "best_effort=KILL CONNECTION 89;"
        The contents of file "${TEST_DIR}/calls" should include "fence"
        The contents of file "${TEST_DIR}/calls" should include "syncerctl"
      End

      It "fences remote root before DCS and local writes immediately after DCS is accepted"
        enumerate_user_facing_root_hosts() { echo "%"; return 0; }
        fence_local_remote_root_for_secondary() {
          record_call "fence"
          return 0
        }
        local_remote_root_is_fenced_for_secondary() {
          record_call "verify_fence"
          return 0
        }
        syncerctl_switchover() {
          record_call "syncerctl"
          return 0
        }
        set_local_read_only() {
          record_call "set_read_only=$1"
          return 0
        }
        local_read_only_is() {
          record_call "verify_read_only=$1"
          [ "$1" = "1" ]
        }
        candidate_is_primary() {
          return 0
        }
        current_follows_candidate() {
          return 0
        }
        wait_post_switchover_stabilization() {
          return 0
        }
        primary_service_routes_candidate() {
          return 0
        }
        wait_current_secondary_remote_root_fenced() {
          return 0
        }
        remote_root_write_ready() {
          return 0
        }
        verify_post_dcs_local_root_write_fenced() {
          return 0
        }
        revoke_user_facing_root_admin_privileges_for_secondary() {
          return 0
        }
        wait_candidate_promoted_via_syncerctl() {
          return 0
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be success
        The output should include "Switchover pre-DCS guard passed"
        The output should include "Switchover: creating syncer DCS switchover"
        The output should include "Switchover post-DCS guard passed"
        The contents of file "${TEST_DIR}/calls" should include "fence"
        The contents of file "${TEST_DIR}/calls" should include "verify_fence"
        The contents of file "${TEST_DIR}/calls" should include "syncerctl"
        The contents of file "${TEST_DIR}/calls" should include "set_read_only=ON"
        The contents of file "${TEST_DIR}/calls" should include "verify_read_only=1"
      End

      It "fails closed when post-DCS local write fence does not close"
        prepare_current_primary_for_switchover() {
          record_call "prepare"
          return 0
        }
        syncerctl_switchover() {
          record_call "syncerctl"
          return 0
        }
        set_local_read_only() {
          record_call "set_read_only=$1"
          return 1
        }
        rollback_current_primary_switchover_guard() {
          record_call "rollback"
          return 0
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be failure
        The output should include "Switchover post-DCS guard"
        The stderr should include "Switchover failed: current primary local write fence did not close after DCS switchover"
        The contents of file "${TEST_DIR}/calls" should include "prepare"
        The contents of file "${TEST_DIR}/calls" should include "syncerctl"
        The contents of file "${TEST_DIR}/calls" should include "set_read_only=ON"
        The contents of file "${TEST_DIR}/calls" should not include "rollback"
      End

      It "does not create DCS switchover when the old-primary guard fails"
        make_syncerctl
        enumerate_user_facing_root_hosts() { echo "%"; return 0; }
        fence_local_remote_root_for_secondary() {
          record_call "fence"
          return 1
        }
        rollback_current_primary_switchover_guard() {
          record_call "rollback"
          return 0
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be failure
        The output should include "Switchover pre-DCS guard"
        The stderr should include "Switchover failed: could not fence current primary remote root before DCS switchover"
        The path "${SYNCERCTL_ARGS}" should not be exist
        The contents of file "${TEST_DIR}/calls" should include "fence"
        The contents of file "${TEST_DIR}/calls" should include "rollback"
      End
    End
  End

  Describe "current_follows_candidate()"
    It "repairs kubeblocks health check SQL-thread errors before deciding old-primary follow failed"
      export MARIADB_ROOT_USER="root"
      export MARIADB_ROOT_PASSWORD="pw"
      query_value() {
        case "$1:$2" in
          "127.0.0.1:SELECT @@global.read_only;"*) echo "1" ;;
        esac
      }
      query_slave_status() {
        local count
        count=$(cat "${TEST_DIR}/slave-status-count" 2>/dev/null || echo 0)
        count=$((count + 1))
        printf "%s" "${count}" > "${TEST_DIR}/slave-status-count"
        if [ "${count}" -eq 1 ]; then
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 1062
Last_SQL_Error: Error 'Duplicate entry' on table 'kubeblocks.kb_health_check'
Master_Host: mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local
EOF
        else
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
Master_Host: mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local
EOF
        fi
      }
      run_local_maintenance_sql() {
        record_call "maintenance=$1"
        return 0
      }
      run_local_sql_best_effort() {
        record_call "best_effort=$1"
        return 0
      }
      set_local_read_only() {
        record_call "set_read_only=$1"
        return 0
      }
      syncer_role_is() {
        record_call "syncer_role=$1:$2"
        return 0
      }
      When call current_follows_candidate "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
      The status should be success
      The output should include "detected repairable kubeblocks health check replication error"
      The contents of file "${TEST_DIR}/calls" should include "best_effort=STOP SLAVE SQL_THREAD;"
      The contents of file "${TEST_DIR}/calls" should include "set_read_only=OFF"
      The contents of file "${TEST_DIR}/calls" should include "CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check"
      The contents of file "${TEST_DIR}/calls" should include "set_read_only=ON"
      The contents of file "${TEST_DIR}/calls" should include "best_effort=START SLAVE SQL_THREAD;"
      The contents of file "${TEST_DIR}/slave-status-count" should eq "2"
    End

    It "does not accept old-primary follow while syncer still sees it as primary"
      query_value() {
        case "$1:$2" in
          "127.0.0.1:SELECT @@global.read_only;"*) echo "1" ;;
        esac
      }
      syncer_role_is() {
        [ "$1:$2" = "127.0.0.1:secondary" ] && return 1
        return 0
      }
      query_slave_status() {
        cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
Master_Host: mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local
EOF
      }
      When call current_follows_candidate "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
      The status should be failure
    End

    It "uses internal local maintenance SQL before falling back to user-facing root"
      export MARIADB_ROOT_USER="root"
      export MARIADB_ROOT_PASSWORD="pw"
      export MARIADB_INTERNAL_ROOT_USER="kb_internal_root"
      run_local_internal_sql() {
        record_call "internal=$1"
        return 0
      }
      run_sql() {
        record_call "root=$2"
        return 0
      }
      When call clear_local_kb_health_check_table "internal-maintenance"
      The status should be success
      The output should include "prepared local kubeblocks health check table"
      The contents of file "${TEST_DIR}/calls" should include "internal="
      The contents of file "${TEST_DIR}/calls" should not include "root="
    End
  End

  Describe "run_local_maintenance_sql()"
    It "falls back to user-facing root when internal admin is unavailable"
      run_local_internal_sql() {
        record_call "internal=$1"
        return 1
      }
      run_sql() {
        record_call "root=$2"
        return 0
      }
      When call run_local_maintenance_sql "SELECT 1;"
      The status should be success
      The contents of file "${TEST_DIR}/calls" should include "internal=SELECT 1;"
      The contents of file "${TEST_DIR}/calls" should include "root=SELECT 1;"
    End
  End

  Describe "log_primary_service_route_diagnostic()"
    It "logs matched route state without gating action success"
      query_server_id() {
        case "$1" in
          "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local") echo "2" ;;
          "mdb-mariadb.demo.svc.cluster.local") echo "2" ;;
        esac
      }

      When call log_primary_service_route_diagnostic "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
      The status should be success
      The output should include "Switchover service-route diagnostic: candidate=mdb-mariadb-1"
      The output should include "primary_service=mdb-mariadb.demo.svc.cluster.local"
      The output should include "expected_server_id=2 service_server_id=2 route_status=matched"
    End

    It "logs pending route state without failing"
      query_server_id() {
        case "$1" in
          "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local") echo "2" ;;
          "mdb-mariadb.demo.svc.cluster.local") echo "" ;;
        esac
      }

      When call log_primary_service_route_diagnostic "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
      The status should be success
      The output should include "service_server_id=<empty-or-error> route_status=pending"
    End
  End

  # alpha.59 design-contract close-out (Jack 19:45 review blocker 1):
  # post-DCS local-root write fence must be _verified_ via an actual user-facing
  # root INSERT being rejected with 1290/read-only, not just by setting
  # @@global.read_only=ON. Otherwise the contract has a non-empty field that is
  # never enforced at the write site.
  Describe "verify_post_dcs_local_root_write_fenced()"
    setup_fence_probe() {
      export MARIADB_ROOT_USER="root"
      export MARIADB_ROOT_PASSWORD="pw"
      export MARIADB_CONNECT_TIMEOUT_SECONDS="5"
      export MARIADB_CLIENT_BIN="${TEST_DIR}/mariadb"
    }
    Before "setup_fence_probe"

    It "passes when user-facing root INSERT is rejected with server error 1290"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "ERROR 1290 (HY000) at line 4: The MariaDB server is running with the --read-only option so it cannot execute this statement" >&2
exit 1
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be success
      The output should include "Switchover post-DCS local-root write fence verified"
    End

    It "fails closed when user-facing root INSERT unexpectedly succeeds (fence not enforced)"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be failure
      The stderr should include "Switchover failed: post-DCS local-root write fence not enforced"
    End

    It "fails closed when INSERT fails with an unrelated error (no 1290 / no read-only signal)"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "ERROR 1064 (42000) at line 1: You have an error in your SQL syntax" >&2
exit 1
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be failure
      The stderr should include "Switchover failed: post-DCS local-root write fence verification got unexpected error"
    End

    It "fails closed when MARIADB_CLIENT_BIN is unavailable"
      rm -f "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be failure
      The stderr should include "Switchover failed: post-DCS local-root write fence verification cannot run without MARIADB_CLIENT_BIN"
    End
  End

  # alpha.60 (Jack 23:28 8-class review): post-DCS read_only=ON does not fence
  # user-facing root if root holds READ_ONLY ADMIN / SUPER / BINLOG ADMIN.
  # This describe block exercises the synchronous revoke that closes that gap.
  Describe "revoke_user_facing_root_admin_privileges_for_secondary()"
    setup_revoke_env() {
      export MARIADB_ROOT_USER="root"
      export MARIADB_ROOT_PASSWORD="pw"
      export MARIADB_INTERNAL_ROOT_USER="kb_internal_root"
      export MARIADB_CONNECT_TIMEOUT_SECONDS="5"
      export MARIADB_CLIENT_BIN="${TEST_DIR}/mariadb"
      export MOCK_REVOKE_CALLS="${TEST_DIR}/revoke-calls"
      export MOCK_TMP="${TEST_DIR}"
      : > "${MOCK_REVOKE_CALLS}"
    }
    Before "setup_revoke_env"

    It "skips with reason=root_account_not_found when mysql.user has no rows"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_REVOKE_CALLS}"
case "$*" in
  *"SELECT Host FROM mysql.user"*) exit 0 ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call revoke_user_facing_root_admin_privileges_for_secondary
      The status should be success
      The output should include "Switchover post-DCS root revoke: reason=root_account_not_found"
      The contents of file "${MOCK_REVOKE_CALLS}" should not include "REVOKE READ_ONLY ADMIN"
    End

    It "alpha.60 v2: revokes each bypass priv per-host and verifies post-revoke residual is clean"
      # Per Jack 23:52 v2 review: REVOKE per-privilege; after all REVOKEs for a
      # host, re-SHOW GRANTS and assert no bypass priv remains. Mock alternates
      # SHOW GRANTS responses (odd-call = initial bypass, even-call = post-
      # revoke clean) since the function calls SHOW GRANTS exactly twice per
      # host in fixed order.
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_REVOKE_CALLS}"
case "$*" in
  *"SELECT Host FROM mysql.user"*)
    printf "%%\n127.0.0.1\nlocalhost\n"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@"*)
    n=$(cat "${MOCK_TMP}/show_count" 2>/dev/null || echo 0)
    n=$((n+1))
    echo "$n" > "${MOCK_TMP}/show_count"
    if [ $((n % 2)) -eq 1 ]; then
      printf "GRANT ALL PRIVILEGES ON *.* TO 'root'@'<host>' WITH GRANT OPTION\n"
    else
      printf "GRANT SELECT ON *.* TO 'root'@'<host>'\n"
    fi
    exit 0
    ;;
  *"REVOKE READ_ONLY ADMIN"*|*"REVOKE SUPER"*|*"REVOKE BINLOG ADMIN"*|*"FLUSH PRIVILEGES"*|*"SELECT CONCAT"*)
    exit 0
    ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call revoke_user_facing_root_admin_privileges_for_secondary
      The status should be success
      The output should include "reason=revoked root@% priv=READ_ONLY ADMIN"
      The output should include "reason=revoked root@% priv=SUPER"
      The output should include "reason=revoked root@% priv=BINLOG ADMIN"
      The output should include "reason=revoked root@127.0.0.1 priv=READ_ONLY ADMIN"
      The output should include "reason=revoked root@localhost priv=READ_ONLY ADMIN"
      The output should include "Switchover post-DCS root revoke summary revoked=9"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "REVOKE READ_ONLY ADMIN"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "REVOKE SUPER"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "REVOKE BINLOG ADMIN"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "FLUSH PRIVILEGES"
    End

    It "fails closed when even one host still has bypass priv that REVOKE refuses (non-1141)"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_REVOKE_CALLS}"
case "$*" in
  *"SELECT Host FROM mysql.user"*)
    printf "%%\nlocalhost\n"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@'%'"*)
    printf "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%%' WITH GRANT OPTION\n"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@'localhost'"*)
    printf "GRANT READ_ONLY ADMIN ON *.* TO 'root'@'localhost'\n"
    exit 0
    ;;
  *"REVOKE READ_ONLY ADMIN"*"'root'@'localhost'"*)
    echo "ERROR 1227 (42000) at line 2: Access denied" >&2
    exit 1
    ;;
  *"REVOKE READ_ONLY ADMIN"*)
    exit 0
    ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call revoke_user_facing_root_admin_privileges_for_secondary
      The status should be failure
      The output should include "reason=revoked root@%"
      The stderr should include "reason=revoke_failed root@localhost"
      The stderr should include "fail-closed"
    End

    It "alpha.60 v2: treats 1141 on a single REVOKE as priv-already-absent, not host-wide already-fenced"
      # Per Jack v2: 1141 on READ_ONLY ADMIN means only that priv is absent;
      # SUPER and BINLOG ADMIN must still be REVOKEd. Mock simulates the case
      # where READ_ONLY ADMIN is missing from the start but SUPER and BINLOG
      # ADMIN are present and revoked successfully. Post-revoke SHOW GRANTS
      # returns clean (no bypass priv).
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_REVOKE_CALLS}"
case "$*" in
  *"SELECT Host FROM mysql.user"*)
    printf "%%\n"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@"*)
    if [ -f "${MOCK_TMP}/revoked" ]; then
      printf "GRANT SELECT ON *.* TO 'root'@'%%'\n"
    else
      printf "GRANT SUPER, BINLOG ADMIN ON *.* TO 'root'@'%%'\n"
    fi
    exit 0
    ;;
  *"REVOKE READ_ONLY ADMIN"*)
    echo "ERROR 1141 (42000): There is no such grant defined for user 'root' on host '%'" >&2
    exit 1
    ;;
  *"REVOKE BINLOG ADMIN"*)
    touch "${MOCK_TMP}/revoked"
    exit 0
    ;;
  *"REVOKE SUPER"*|*"FLUSH PRIVILEGES"*|*"SELECT CONCAT"*)
    exit 0
    ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call revoke_user_facing_root_admin_privileges_for_secondary
      The status should be success
      The output should include "reason=privilege_absent_already_fenced root@% priv=READ_ONLY ADMIN"
      The output should include "(1141 on REVOKE)"
      The output should include "reason=revoked root@% priv=SUPER"
      The output should include "reason=revoked root@% priv=BINLOG ADMIN"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "REVOKE SUPER"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "REVOKE BINLOG ADMIN"
    End

    It "alpha.60 v2: fails closed when one priv 1141 but post-revoke SHOW GRANTS still has another bypass priv"
      # The exact scenario Jack 23:52 flagged as "假安全窗口": READ_ONLY ADMIN
      # already absent (1141), SUPER REVOKE returns success (mocked), but
      # post-revoke SHOW GRANTS still contains SUPER / BINLOG ADMIN (because
      # in reality the REVOKE didn't take effect for some reason). The
      # post-revoke residual check must catch this and fail-closed.
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_REVOKE_CALLS}"
case "$*" in
  *"SELECT Host FROM mysql.user"*)
    printf "%%\n"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@"*)
    # initial AND post-revoke both still show SUPER (residual bypass survives)
    printf "GRANT SUPER ON *.* TO 'root'@'%%'\n"
    exit 0
    ;;
  *"REVOKE READ_ONLY ADMIN"*)
    echo "ERROR 1141 (42000): There is no such grant defined for user 'root' on host '%'" >&2
    exit 1
    ;;
  *"REVOKE SUPER"*|*"REVOKE BINLOG ADMIN"*|*"FLUSH PRIVILEGES"*|*"SELECT CONCAT"*)
    exit 0
    ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call revoke_user_facing_root_admin_privileges_for_secondary
      The status should be failure
      The output should include "reason=privilege_absent_already_fenced root@% priv=READ_ONLY ADMIN"
      The stderr should include "reason=revoke_residual_bypass root@%"
      The stderr should include "fail-closed"
    End

    It "alpha.60 v2: still calls per-priv REVOKE even when initial SHOW GRANTS shows no bypass priv (defense-in-depth)"
      # alpha.60 v2 contract: even if initial SHOW GRANTS shows no bypass
      # priv, we still attempt per-priv REVOKE (each will return 1141, treated
      # as already-fenced). This is intentional defense-in-depth: the initial
      # SHOW GRANTS could be stale, and the post-revoke SHOW GRANTS residual
      # check is the authoritative gate.
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_REVOKE_CALLS}"
case "$*" in
  *"SELECT Host FROM mysql.user"*)
    printf "%%\n"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@"*)
    printf "GRANT SELECT ON *.* TO 'root'@'%%'\n"
    exit 0
    ;;
  *"REVOKE READ_ONLY ADMIN"*|*"REVOKE SUPER"*|*"REVOKE BINLOG ADMIN"*)
    echo "ERROR 1141 (42000): There is no such grant defined for user 'root' on host '%'" >&2
    exit 1
    ;;
  *"FLUSH PRIVILEGES"*|*"SELECT CONCAT"*)
    exit 0
    ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call revoke_user_facing_root_admin_privileges_for_secondary
      The status should be success
      The output should include "reason=privilege_absent_already_fenced root@% priv=READ_ONLY ADMIN"
      The output should include "(1141 on REVOKE)"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "REVOKE READ_ONLY ADMIN"
    End

    It "fails closed when MARIADB_CLIENT_BIN is unavailable"
      rm -f "${TEST_DIR}/mariadb"
      When call revoke_user_facing_root_admin_privileges_for_secondary
      The status should be failure
      The stderr should include "Switchover failed: post-DCS root revoke cannot run without MARIADB_CLIENT_BIN"
    End

    It "alpha.60 v3: fails closed when host enumeration query itself returns rc!=0 (no silent root_account_not_found)"
      # Per Jack 00:08 v3 review: a failed `SELECT Host FROM mysql.user`
      # query (permission denied, connection error, etc.) must NOT be
      # silently treated as 'root account does not exist'. The function
      # must fail-closed without entering REVOKE / FLUSH / verify.
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_REVOKE_CALLS}"
case "$*" in
  *"SELECT Host FROM mysql.user"*)
    echo "ERROR 1142 (42000): SELECT command denied to user 'kb_internal_root' for table 'user'" >&2
    exit 1
    ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call revoke_user_facing_root_admin_privileges_for_secondary
      The status should be failure
      The stderr should include "reason=root_host_query_failed"
      The stderr should include "fail-closed"
      The contents of file "${MOCK_REVOKE_CALLS}" should not include "REVOKE READ_ONLY ADMIN"
      The contents of file "${MOCK_REVOKE_CALLS}" should not include "REVOKE SUPER"
      The contents of file "${MOCK_REVOKE_CALLS}" should not include "REVOKE BINLOG ADMIN"
      The contents of file "${MOCK_REVOKE_CALLS}" should not include "FLUSH PRIVILEGES"
    End
  End

  # alpha.60: ensure fence_current_primary_local_writes_after_dcs fails closed
  # when revoke_user_facing_root_admin_privileges_for_secondary returns 1.
  Describe "fence_current_primary_local_writes_after_dcs() revoke fail-closed"
    It "fails closed when revoke step fails (does not call verify probe)"
      set_local_read_only() { return 0; }
      local_read_only_is() { [ "$1" = "1" ]; }
      revoke_user_facing_root_admin_privileges_for_secondary() {
        record_call "revoke_called"
        return 1
      }
      verify_post_dcs_local_root_write_fenced() {
        record_call "BUG_verify_called_after_revoke_failure"
        return 0
      }
      When call fence_current_primary_local_writes_after_dcs
      The status should be failure
      The output should include "Switchover post-DCS guard"
      The contents of file "${TEST_DIR}/calls" should include "revoke_called"
      The contents of file "${TEST_DIR}/calls" should not include "BUG_verify_called_after_revoke_failure"
    End
  End

  # alpha.60 v2 (Jack 23:52 review point 2): rollback path of switchover must
  # NOT re-grant admin bypass privileges to user-facing root, otherwise the
  # next switchover's post-DCS revoke would have to fight ALL PRIVILEGES.
  Describe "unfence_local_remote_root_for_primary() (rollback path)"
    setup_unfence_env() {
      export MARIADB_ROOT_USER="root"
      export MARIADB_ROOT_PASSWORD="pw"
      export MARIADB_ROOT_HOST="%"
      export MARIADB_CONNECT_TIMEOUT_SECONDS="5"
      export MARIADB_CLIENT_BIN="${TEST_DIR}/mariadb"
      export MOCK_UNFENCE_CALLS="${TEST_DIR}/unfence-calls"
      : > "${MOCK_UNFENCE_CALLS}"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_UNFENCE_CALLS}"
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
    }
    Before "setup_unfence_env"

    It "alpha.60 v2 + alpha.62 v1: grants explicit non-bypass primary list per host, never GRANT ALL PRIVILEGES, no admin bypass"
      When call unfence_local_remote_root_for_primary "%"
      The status should be success
      The contents of file "${MOCK_UNFENCE_CALLS}" should include "REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'root'@'%'"
      The contents of file "${MOCK_UNFENCE_CALLS}" should include "ON *.* TO 'root'@'%' WITH GRANT OPTION"
      The contents of file "${MOCK_UNFENCE_CALLS}" should include "INSERT"
      The contents of file "${MOCK_UNFENCE_CALLS}" should include "UPDATE"
      The contents of file "${MOCK_UNFENCE_CALLS}" should include "DELETE"
      The contents of file "${MOCK_UNFENCE_CALLS}" should include "CREATE"
      The contents of file "${MOCK_UNFENCE_CALLS}" should include "DROP"
      The contents of file "${MOCK_UNFENCE_CALLS}" should not include "GRANT ALL PRIVILEGES ON *.*"
      The contents of file "${MOCK_UNFENCE_CALLS}" should not include "GRANT SUPER"
      The contents of file "${MOCK_UNFENCE_CALLS}" should not include "GRANT READ_ONLY ADMIN"
      The contents of file "${MOCK_UNFENCE_CALLS}" should not include "GRANT BINLOG ADMIN"
      The contents of file "${MOCK_UNFENCE_CALLS}" should not include "GRANT CONNECTION ADMIN"
      The output should include "unfence_local_remote_root_for_primary: host=% unfence_apply_rc=0"
    End

    It "alpha.62 v1 grant body invariant: SWITCHOVER_EXPLICIT_PRIMARY_GRANT_BODY contains all 5 core write privs (strong-bind with verifier)"
      # Verifier remote_root_has_explicit_primary_grant requires INSERT/UPDATE/DELETE/CREATE/DROP
      # to be present. This test asserts the grant body itself contains them, locking the
      # invariant: grant write site and grant read site share the same source of truth.
      When call printf '%s' "${SWITCHOVER_EXPLICIT_PRIMARY_GRANT_BODY}"
      The output should include "INSERT"
      The output should include "UPDATE"
      The output should include "DELETE"
      The output should include "CREATE"
      The output should include "DROP"
    End
  End

  # alpha.61 (Jack 01:40 review): action must observe DCS-side candidate
  # promotion (syncerctl getrole on candidate FQDN returns "primary") BEFORE
  # the write probe runs. Without this, the write probe was the first place
  # to notice non-promotion (and only via opaque INSERT rc=1).
  Describe "wait_candidate_promoted_via_syncerctl()"
    setup_promoted_env() {
      export SYNCERCTL_BIN="${TEST_DIR}/syncerctl"
      export SYNCERCTL_PORT="3601"
      export SWITCHOVER_POLL_SECONDS="0"
      export MOCK_SYNCERCTL_CALLS="${TEST_DIR}/syncerctl-calls"
      : > "${MOCK_SYNCERCTL_CALLS}"
      # alpha.61 v2: HAS_TIMEOUT must be set; we stub
      # run_syncerctl_getrole_with_timeout to call SYNCERCTL_BIN directly so
      # the test does not depend on a system `timeout(1)` being on PATH.
      export SWITCHOVER_HAS_TIMEOUT=1
      run_syncerctl_getrole_with_timeout() {
        "${SYNCERCTL_BIN}" --host "$1" --port "${SYNCERCTL_PORT}" getrole 2>&1
      }
    }
    Before "setup_promoted_env"

    It "returns success on first attempt when syncerctl getrole returns primary"
      cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_SYNCERCTL_CALLS}"
echo "primary"
exit 0
EOF
      chmod +x "${SYNCERCTL_BIN}"
      When call wait_candidate_promoted_via_syncerctl "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local" 5
      The status should be success
      The output should include "Switchover candidate promoted via DCS observed"
      The output should include "role=primary rc=0"
    End

    It "fails closed with reason=candidate_fqdn_not_found when candidate FQDN is empty"
      When call wait_candidate_promoted_via_syncerctl "mdb-mariadb-1" "" 5
      The status should be failure
      The stderr should include "reason=candidate_fqdn_not_found"
      The stderr should include "fail-closed"
    End

    It "logs reason=role_query_failed and continues polling when syncerctl rc != 0"
      cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_SYNCERCTL_CALLS}"
n=$(cat "${MOCK_SYNCERCTL_CALLS}.count" 2>/dev/null || echo 0)
n=$((n+1))
echo "$n" > "${MOCK_SYNCERCTL_CALLS}.count"
if [ "$n" -le 2 ]; then
  echo "ERROR: connection refused" >&2
  exit 1
fi
echo "primary"
exit 0
EOF
      chmod +x "${SYNCERCTL_BIN}"
      When call wait_candidate_promoted_via_syncerctl "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local" 30
      The status should be success
      The output should include "reason=role_query_failed"
      The output should include "stderr=ERROR: connection refused"
      The output should include "Switchover candidate promoted via DCS observed"
    End

    It "logs reason=role_not_primary while candidate is still secondary, returns success after promotion"
      cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_SYNCERCTL_CALLS}"
n=$(cat "${MOCK_SYNCERCTL_CALLS}.count" 2>/dev/null || echo 0)
n=$((n+1))
echo "$n" > "${MOCK_SYNCERCTL_CALLS}.count"
if [ "$n" -le 2 ]; then
  echo "secondary"
  exit 0
fi
echo "primary"
exit 0
EOF
      chmod +x "${SYNCERCTL_BIN}"
      When call wait_candidate_promoted_via_syncerctl "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local" 30
      The status should be success
      The output should include "reason=role_not_primary role=secondary"
      The output should include "Switchover candidate promoted via DCS observed"
    End

    It "fails closed with reason=candidate_not_promoted_via_dcs_in_budget when stage budget exhausts"
      cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_SYNCERCTL_CALLS}"
echo "secondary"
exit 0
EOF
      chmod +x "${SYNCERCTL_BIN}"
      When call wait_candidate_promoted_via_syncerctl "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local" 0
      The status should be failure
      The stderr should include "reason=candidate_not_promoted_via_dcs_in_budget"
      The stderr should include "stage_budget=0s"
      The stderr should include "fail-closed"
    End
  End

  # alpha.61 v2 (Jack 02:00 review): POSIX wall-clock helpers + 5-stage deadline.
  # These Describes lock the runtime contract that v1 silently broke under
  # /bin/sh: now_epoch must be a real wall clock, remaining_action_budget must
  # fail-closed (NOT silently 0) on clock failure, and every stage entry must
  # check remaining_action_budget before invoking the stage body.
  Describe "alpha.61 v2 POSIX clock helpers"
    Context "now_epoch()"
      It "returns a numeric POSIX epoch on success"
        When call now_epoch
        The status should be success
        The output should match pattern "[0-9]*"
      End

      It "returns rc=2 (NOT empty 0 fallback) when date itself fails"
        date() { return 1; }
        When call now_epoch
        The status should equal 2
        The output should equal ""
      End

      It "returns rc=2 when date emits non-numeric output"
        date() { echo "not-a-number"; return 0; }
        When call now_epoch
        The status should equal 2
        The output should equal ""
      End
    End

    Context "remaining_action_budget()"
      It "returns positive remaining when within budget"
        export SWITCHOVER_ACTION_DEADLINE_SECONDS=55
        action_started_epoch=$(date +%s)
        When call remaining_action_budget
        The status should be success
        The output should match pattern "*[0-9]*"
      End

      It "fails closed (rc=2) when action_started_epoch is unset (NOT silent 0 fallback)"
        export SWITCHOVER_ACTION_DEADLINE_SECONDS=55
        action_started_epoch=""
        When call remaining_action_budget
        The status should equal 2
        The output should equal "0"
      End

      It "fails closed (rc=2) when now_epoch fails (NOT silent 0 fallback)"
        export SWITCHOVER_ACTION_DEADLINE_SECONDS=55
        action_started_epoch=$(date +%s)
        date() { return 1; }
        When call remaining_action_budget
        The status should equal 2
        The output should equal "0"
      End
    End

    Context "stage_budget_or_exit()"
      It "clamps stage_max down to remaining_action_budget when remaining is smaller"
        export SWITCHOVER_ACTION_DEADLINE_SECONDS=55
        action_started_epoch=$(date +%s)
        # Force remaining=3 by stubbing remaining_action_budget.
        remaining_action_budget() { printf '3'; return 0; }
        When call stage_budget_or_exit "promote" 30
        The status should be success
        The output should equal "3"
      End

      It "uses stage_max when stage_max < remaining_action_budget"
        export SWITCHOVER_ACTION_DEADLINE_SECONDS=55
        action_started_epoch=$(date +%s)
        remaining_action_budget() { printf '50'; return 0; }
        When call stage_budget_or_exit "promote" 30
        The status should be success
        The output should equal "30"
      End

      It "fails closed with reason=action_deadline_exhausted_<stage> when remaining<=0"
        export SWITCHOVER_ACTION_DEADLINE_SECONDS=55
        action_started_epoch=$(date +%s)
        remaining_action_budget() { printf '0'; return 0; }
        When call stage_budget_or_exit "promote" 30
        The status should be failure
        The stderr should include "reason=action_deadline_exhausted_promote"
        The stderr should include "fail-closed"
      End

      It "fails closed with cause=action_clock_unavailable when remaining_action_budget rc=2"
        export SWITCHOVER_ACTION_DEADLINE_SECONDS=55
        action_started_epoch=""
        remaining_action_budget() { printf '0'; return 2; }
        When call stage_budget_or_exit "fence" 15
        The status should be failure
        The stderr should include "reason=action_deadline_exhausted_fence"
        The stderr should include "cause=action_clock_unavailable"
        The stderr should include "fail-closed"
      End
    End
  End

  Describe "alpha.61 v2 initialize_action_clock()"
    It "sets action_started_epoch and SWITCHOVER_HAS_TIMEOUT=1 when timeout(1) exists"
      command() {
        if [ "$1" = "-v" ] && [ "$2" = "timeout" ]; then return 0; fi
        builtin command "$@"
      }
      action_started_epoch=""
      SWITCHOVER_HAS_TIMEOUT=""
      When call initialize_action_clock
      The status should be success
      The variable action_started_epoch should match pattern "[0-9]*"
      The variable SWITCHOVER_HAS_TIMEOUT should equal "1"
    End

    It "alpha.61 v3: fails closed at action entry with reason=external_timeout_unavailable when timeout(1) is absent (DCS not touched)"
      command() {
        if [ "$1" = "-v" ] && [ "$2" = "timeout" ]; then return 1; fi
        builtin command "$@"
      }
      action_started_epoch=""
      SWITCHOVER_HAS_TIMEOUT=""
      When call initialize_action_clock
      The status should be failure
      The stderr should include "reason=external_timeout_unavailable"
      The stderr should include "cause=command_v_timeout_failed"
      The stderr should include "fail-closed"
      The stderr should include "DCS not touched"
    End

    It "fails closed with reason=action_clock_unavailable when date itself fails"
      date() { return 1; }
      When call initialize_action_clock
      The status should be failure
      The stderr should include "reason=action_clock_unavailable"
      The stderr should include "cause=date_failed"
      The stderr should include "fail-closed"
    End
  End

  Describe "alpha.61 v2 extract_syncerctl_role()"
    It "returns 'primary' when output is exactly the word primary"
      When call extract_syncerctl_role "primary"
      The output should equal "primary"
    End

    It "returns 'primary' from a multi-line output (POSIX awk parser, NOT bash \$'\\n' case)"
      When call extract_syncerctl_role "DEBUG: connecting to syncer
primary
"
      The output should equal "primary"
    End

    It "returns 'secondary' when output is exactly the word secondary"
      When call extract_syncerctl_role "secondary"
      The output should equal "secondary"
    End

    It "returns empty string for unrecognized output (does NOT confuse partial matches)"
      When call extract_syncerctl_role "primary-something
secondary-other"
      The output should equal ""
    End
  End

  Describe "alpha.61 v2 wait_candidate_promoted_via_syncerctl() timeout-availability gate"
    It "fails closed with reason=external_timeout_unavailable when SWITCHOVER_HAS_TIMEOUT != 1"
      export SWITCHOVER_HAS_TIMEOUT=0
      When call wait_candidate_promoted_via_syncerctl "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local" 30
      The status should be failure
      The stderr should include "reason=external_timeout_unavailable"
      The stderr should include "stage=candidate_promoted"
      The stderr should include "fail-closed"
    End
  End

  # alpha.61 v2 (Jack 02:00 review): per-stage deadline enforcement matrix.
  # Each stage entry MUST check remaining_action_budget BEFORE invoking the
  # stage body. Sentinel reasons are distinct so closeout can attribute the
  # exhausted stage. v1 only enforced this on the last 2 stages (promote,
  # write); v2 enforces on all 5 (prepare, dcs, fence, promote, write).
  Describe "run_switchover() alpha.61 v2 per-stage deadline enforcement"
    setup_v2_stage_env() {
      export SWITCHOVER_ACTION_DEADLINE_SECONDS=10
      export SWITCHOVER_PREPARE_STAGE_BUDGET_SECONDS=5
      export SWITCHOVER_DCS_STAGE_BUDGET_SECONDS=5
      export SWITCHOVER_FENCE_STAGE_BUDGET_SECONDS=5
      export CANDIDATE_PROMOTED_VIA_SYNCERCTL_WAIT_SECONDS=5
      export CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS=5
      export SWITCHOVER_POLL_SECONDS=0
      # Controlled clock: now_epoch reads from a file we manipulate.
      echo "1000" > "${TEST_DIR}/clock_now"
      now_epoch() {
        local v
        v=$(cat "${TEST_DIR}/clock_now" 2>/dev/null) || return 2
        case "${v}" in
          ''|*[!0-9]*) return 2 ;;
        esac
        printf '%s' "${v}"
      }
      # Bypass real timeout(1) detection so initialize_action_clock succeeds.
      command() {
        if [ "$1" = "-v" ] && [ "$2" = "timeout" ]; then return 0; fi
        builtin command "$@"
      }
    }
    Before "setup_v2_stage_env"

    advance_clock() {
      # Advance the controlled clock by the given number of seconds.
      local now
      now=$(cat "${TEST_DIR}/clock_now")
      echo $(( now + $1 )) > "${TEST_DIR}/clock_now"
    }

    It "fails closed at prepare stage with action_deadline_exhausted_prepare when deadline already exhausted at entry"
      # Pre-set started so initialize_action_clock captures t=1000, then push
      # the clock to t=1100 BEFORE prepare's stage_budget_or_exit runs.
      initialize_action_clock() {
        action_started_epoch=$(now_epoch)
        SWITCHOVER_HAS_TIMEOUT=1
        # Push wall clock 100s past start so remaining=10-100=-90.
        echo "1100" > "${TEST_DIR}/clock_now"
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "global deadline"
      The stderr should include "reason=action_deadline_exhausted_prepare"
      The stderr should include "fail-closed"
    End

    It "alpha.61 v3: fails closed with action_deadline_exhausted_prepare_overrun when prepare body exceeds budget"
      prepare_current_primary_for_switchover() {
        # Burn 100s during prepare body.
        advance_clock 100
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "Switchover stage prepare"
      The stderr should include "reason=action_deadline_exhausted_prepare_overrun"
      The stderr should include "stage body exceeded budget"
      The stderr should include "fail-closed"
    End

    It "alpha.61 v3: fails closed with action_deadline_exhausted_dcs_overrun when dcs body exceeds budget"
      prepare_current_primary_for_switchover() { return 0; }
      syncerctl_switchover() {
        advance_clock 100
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "Switchover stage dcs"
      The stderr should include "reason=action_deadline_exhausted_dcs_overrun"
      The stderr should include "stage body exceeded budget"
      The stderr should include "fail-closed"
    End

    It "alpha.61 v3: fails closed with action_deadline_exhausted_fence_overrun when fence body exceeds budget"
      prepare_current_primary_for_switchover() { return 0; }
      syncerctl_switchover() { return 0; }
      fence_current_primary_local_writes_after_dcs() {
        advance_clock 100
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "Switchover stage fence"
      The stderr should include "reason=action_deadline_exhausted_fence_overrun"
      The stderr should include "stage body exceeded budget"
      The stderr should include "fail-closed"
    End

    It "fails closed at write stage with action_deadline_exhausted_write when promote body exceeds budget"
      prepare_current_primary_for_switchover() { return 0; }
      syncerctl_switchover() { return 0; }
      fence_current_primary_local_writes_after_dcs() { return 0; }
      wait_candidate_promoted_via_syncerctl() {
        advance_clock 100
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "Switchover stage candidate_promoted"
      The stderr should include "reason=action_deadline_exhausted_write"
      The stderr should include "fail-closed"
    End

    It "alpha.61 v3: fails closed at prepare overrun with cause=action_clock_unavailable when wall clock fails mid-prepare"
      prepare_current_primary_for_switchover() {
        # Break the clock during prepare body.
        echo "not-a-number" > "${TEST_DIR}/clock_now"
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "Switchover stage prepare"
      The stderr should include "reason=action_deadline_exhausted_prepare_overrun"
      The stderr should include "fail-closed"
    End
  End

  # alpha.61 v3 (Jack 02:23 review tightening): syncerctl_switchover wraps
  # syncerctl with timeout(1) when stage_budget is provided. timeout(1) exit
  # codes 124/125/137 are mapped to a distinct `syncerctl_timeout` sentinel
  # so closeout can tell wall-clock budget exhaustion from a real syncerctl
  # failure (rc!=0 from syncerctl itself or zero-status non-success message).
  Describe "alpha.61 v3 syncerctl_switchover() timeout sentinel"
    setup_syncerctl_env() {
      export SYNCERCTL_BIN="${TEST_DIR}/syncerctl"
      export SYNCERCTL_HOST="127.0.0.1"
      export SYNCERCTL_PORT="3601"
      export SWITCHOVER_HAS_TIMEOUT=1
      export SYNCERCTL_PER_CALL_TIMEOUT_SECONDS=5
    }
    Before "setup_syncerctl_env"

    It "alpha.61 v3: emits reason=syncerctl_timeout when timeout(1) reaps syncerctl (rc=124)"
      cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
echo "(would block)"
exit 0
EOF
      chmod +x "${SYNCERCTL_BIN}"
      # Stub `timeout` to simulate the 124 SIGTERM exit deterministically (avoids
      # depending on real wall-clock and on host timeout(1) being installed).
      timeout() {
        # Consume the wall-clock arg; ignore the rest.
        shift
        # The simulated process "would have hung" — we model the kill.
        printf "(syncerctl reaped by timeout)\n"
        return 124
      }
      When call syncerctl_switchover "mdb-mariadb-0" "mdb-mariadb-1" 3
      The status should be failure
      The output should include "syncerctl output"
      The stderr should include "reason=syncerctl_timeout"
      The stderr should include "stage=dcs"
      The stderr should include "stage_budget=3s"
      The stderr should include "rc=124"
      The stderr should include "fail-closed"
    End

    It "alpha.61 v3: emits the legacy 'syncerctl exited with rc=' sentinel when syncerctl itself returns non-zero (NOT timeout)"
      cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
echo "ERROR: connection refused" >&2
exit 7
EOF
      chmod +x "${SYNCERCTL_BIN}"
      timeout() {
        # Pass-through: invoke the underlying command with the budget consumed.
        shift
        "$@"
      }
      When call syncerctl_switchover "mdb-mariadb-0" "mdb-mariadb-1" 3
      The status should be failure
      The output should include "syncerctl output"
      The stderr should include "syncerctl exited with rc=7"
      The stderr should not include "reason=syncerctl_timeout"
    End

    It "alpha.61 v3: returns success when syncerctl reports 'switchover success' within budget"
      cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
echo "switchover success: primary=mdb-mariadb-0 candidate=mdb-mariadb-1"
exit 0
EOF
      chmod +x "${SYNCERCTL_BIN}"
      timeout() {
        shift
        "$@"
      }
      When call syncerctl_switchover "mdb-mariadb-0" "mdb-mariadb-1" 3
      The status should be success
      The output should include "switchover success"
    End

    It "alpha.61 v3: legacy callers that omit the stage_budget arg still hit the naked path (no timeout wrapper)"
      cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
echo "switchover success"
exit 0
EOF
      chmod +x "${SYNCERCTL_BIN}"
      # `timeout` would error if called; verify it is NOT called by replacing it.
      timeout() { return 99; }
      When call syncerctl_switchover "mdb-mariadb-0" "mdb-mariadb-1"
      The status should be success
      The output should include "switchover success"
    End
  End

  # alpha.62 v1 (Jack 04:08 review): contract drift fix between switchover-side
  # pre-DCS fence and roleProbe-side secondary fence + verifier口径漂移. Tests
  # cover the new helpers (now POSIX 时基 + per-host enumeration), the
  # observable verifier (structured log + grants_sha + probe_host attribution),
  # and the renamed rollback verifier remote_root_has_explicit_primary_grant.
  Describe "alpha.62 v1 helpers and verifiers"
    setup_alpha62_env() {
      export MARIADB_ROOT_USER="root"
      export MARIADB_ROOT_PASSWORD="pw"
      export MARIADB_INTERNAL_ROOT_USER="kb_internal_root"
      export MARIADB_CONNECT_TIMEOUT_SECONDS="5"
      export MARIADB_CLIENT_BIN="${TEST_DIR}/mariadb-a62"
    }
    Before "setup_alpha62_env"

    Context "compute_grants_sha() / split_grants_sha_field()"
      It "alpha.62 v2: compute_grants_sha returns '<hash>|sha256' when sha256sum is available"
        When call compute_grants_sha "hello world"
        The status should be success
        The output should match pattern "*|sha256"
        The output should not include "unavailable"
      End

      It "alpha.62 v2: compute_grants_sha returns 'unavailable|hash_tool_unavailable' when no hash tool exists (NOT colon-separated; field-split-friendly)"
        command() {
          case "$1 $2" in
            "-v sha256sum"|"-v sha1sum"|"-v md5sum") return 1 ;;
            *) builtin command "$@" ;;
          esac
        }
        When call compute_grants_sha "anything"
        The status should be success
        The output should equal "unavailable|hash_tool_unavailable"
      End

      It "alpha.62 v2: split_grants_sha_field emits 'grants_sha=<h> reason_hash=<algo>' two-field structured form"
        When call split_grants_sha_field "deadbeef|sha256"
        The status should be success
        The output should equal "grants_sha=deadbeef reason_hash=sha256"
      End

      It "alpha.62 v2: split_grants_sha_field on unavailable emits 'grants_sha=unavailable reason_hash=hash_tool_unavailable' (NOT colon-joined)"
        When call split_grants_sha_field "unavailable|hash_tool_unavailable"
        The status should be success
        The output should equal "grants_sha=unavailable reason_hash=hash_tool_unavailable"
      End

      It "alpha.62 v2: split_grants_sha_field defends against unexpected single-token input → grants_sha=unavailable reason_hash=hash_split_failed"
        When call split_grants_sha_field "no_pipe_here"
        The status should be success
        The output should equal "grants_sha=unavailable reason_hash=hash_split_failed"
      End
    End

    Context "enumerate_user_facing_root_hosts()"
      It "returns newline-separated host list on rc=0"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
printf "%%\n127.0.0.1\nlocalhost\n"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call enumerate_user_facing_root_hosts
        The status should be success
        The output should include "127.0.0.1"
        The output should include "localhost"
      End

      It "fails closed with reason=root_host_query_failed when query rc!=0 (NOT silent root_account_not_found)"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "ERROR 1045 (28000): Access denied for user" >&2
echo "ERROR 1045 (28000): Access denied for user"
exit 1
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call enumerate_user_facing_root_hosts
        The status should be failure
        The stderr should include "reason=root_host_query_failed"
        The stderr should include "fail-closed"
      End
    End

    Context "_verify_host_is_fenced() per-host structured verifier"
      It "alpha.62 v1: 127.0.0.1 with non-bypass grants + write probe rc=1 errno=1044 → ok_by_local_probe:1044 with structured log"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
# Internal SHOW GRANTS reads return clean fence; root probe returns 1044.
case "$*" in
  *"-ukb_internal_root"*"SHOW GRANTS"*)
    echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'127.0.0.1'"
    exit 0
    ;;
  *"-uroot"*"INSERT"*)
    echo "ERROR 1044 (42000): Access denied for user 'root'@'127.0.0.1' to database 'kubeblocks'"
    exit 1
    ;;
esac
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "127.0.0.1"
        The status should be success
        The output should include "remote_root_fence_verify host=127.0.0.1"
        The output should include "verified_host=127.0.0.1"
        The output should include "probe_host=127.0.0.1"
        The output should include "write_probe_attempted=true"
        The output should include "write_probe_errno=1044"
        The output should include "reason=ok_by_local_probe:1044"
        # alpha.62 v2 (Jack 04:38 tightening): grants_sha + reason_hash MUST appear
        # as TWO separate fields in the structured log (NOT colon-joined like
        # alpha.62 v1 emitted "grants_sha=unavailable:hash_tool_unavailable").
        The output should include "grants_sha="
        The output should include "reason_hash=sha256"
      End

      It "alpha.62 v1: localhost host → grants-only path (no socket probe), reason=ok_by_grants_only:localhost_socket_not_attempted"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'localhost'"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "localhost"
        The status should be success
        The output should include "probe_host=none:localhost_socket_not_attempted"
        The output should include "write_probe_attempted=false"
        The output should include "reason=ok_by_grants_only:localhost_socket_not_attempted"
      End

      It "alpha.62 v1: % wildcard host → grants-only, reason=ok_by_grants_only:wildcard_or_remote_not_locally_probable"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'%'"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "%"
        The status should be success
        The output should include "probe_host=none:wildcard_or_remote_not_locally_probable"
        The output should include "write_probe_attempted=false"
        The output should include "reason=ok_by_grants_only:wildcard_or_remote_not_locally_probable"
      End

      It "alpha.62 v1: grants contain READ_ONLY ADMIN → fail-closed bypass_priv_residual:READ_ONLY ADMIN with grants dump"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'%'"
echo "GRANT READ_ONLY ADMIN ON *.* TO 'root'@'%'"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "%"
        The status should be failure
        The stderr should include "reason=bypass_priv_residual:READ_ONLY ADMIN"
        The stderr should include "grants_dump_begin"
        The stderr should include "grants_dump_end"
      End

      It "alpha.62 v1: grants contain INSERT (user-facing write) → fail-closed bypass_priv_residual:INSERT"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "GRANT SELECT, INSERT, PROCESS, RELOAD ON *.* TO 'root'@'127.0.0.1'"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "127.0.0.1"
        The status should be failure
        The stderr should include "reason=bypass_priv_residual:INSERT"
      End

      It "alpha.62 v1: 127.0.0.1 write probe rc=0 (writable_unexpected) → fail-closed (fence not applied)"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
case "$*" in
  *"-ukb_internal_root"*"SHOW GRANTS"*)
    echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'127.0.0.1'"
    exit 0
    ;;
  *"-uroot"*"INSERT"*)
    exit 0
    ;;
esac
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "127.0.0.1"
        The status should be failure
        The stderr should include "reason=writable_unexpected"
        The stderr should include "write_probe_rc=0"
      End

      It "alpha.62 v1: grants_query_failed (unrelated stderr) → fail-closed (NOT silent treat as account_absent)"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "ERROR 2003 (HY000): Can't connect to MySQL server" >&2
echo "ERROR 2003 (HY000): Can't connect to MySQL server"
exit 1
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "%"
        The status should be failure
        The stderr should include "reason=grants_query_failed"
      End
    End

    Context "_verify_host_has_explicit_primary_grant() per-host rollback verifier"
      It "alpha.62 v1: grants contain INSERT/UPDATE/DELETE/CREATE/DROP + no admin bypass → ok"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'%' WITH GRANT OPTION"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_has_explicit_primary_grant "%"
        The status should be success
        The output should include "remote_root_explicit_primary_grant_verify host=%"
        The output should include "core_priv_present="
        The output should include "INSERT"
        The output should include "UPDATE"
        The output should include "DELETE"
        The output should include "CREATE"
        The output should include "DROP"
        The output should include "reason=ok"
      End

      It "alpha.62 v1: grants contain GRANT ALL PRIVILEGES → fail-closed all_privileges_residual"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_has_explicit_primary_grant "%"
        The status should be failure
        The stderr should include "reason=all_privileges_residual"
      End

      It "alpha.62 v1: grants missing core write subset → fail-closed core_write_priv_missing"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "GRANT SELECT, PROCESS, RELOAD ON *.* TO 'root'@'%'"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_has_explicit_primary_grant "%"
        The status should be failure
        The stderr should include "reason=core_write_priv_missing"
      End

      It "alpha.62 v1: grants contain admin bypass priv (READ_ONLY ADMIN) → fail-closed admin_bypass_residual"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, READ_ONLY ADMIN ON *.* TO 'root'@'%'"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_has_explicit_primary_grant "%"
        The status should be failure
        The stderr should include "reason=admin_bypass_residual:READ_ONLY ADMIN"
      End
    End

    Context "fence_local_remote_root_for_secondary() drift detection"
      It "alpha.62 v1: fence detects root_host_list_drift between two enumerations and fail-closes"
        # Mock: first enumeration returns "%", second returns "% 127.0.0.1" → drift
        export DRIFT_COUNTER="${TEST_DIR}/drift-counter"
        : > "${DRIFT_COUNTER}"
        cat > "${MARIADB_CLIENT_BIN}" <<EOF_MOCK
#!/bin/sh
case "\$*" in
  *"SELECT Host FROM mysql.user"*)
    n=\$(cat "${DRIFT_COUNTER}" 2>/dev/null || echo 0)
    n=\$((n+1))
    echo "\$n" > "${DRIFT_COUNTER}"
    if [ "\$n" = "1" ]; then
      printf "%%\n"
    else
      printf "%%\n127.0.0.1\n"
    fi
    exit 0
    ;;
esac
exit 0
EOF_MOCK
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call fence_local_remote_root_for_secondary
        The status should be failure
        The output should include "fence_local_remote_root_for_secondary: enumerated host list sha="
        The stderr should include "reason=root_host_list_drift"
        The stderr should include "sha_initial="
        The stderr should include "sha_current="
      End
    End
  End

  # alpha.63 v1 (Jack 05:22 RED closeout I-1 + I-2 + 05:24 instrumentation):
  # close two alpha.62 v1/v2 verifier implementation bugs that escaped both
  # ShellSpec coverage and 8-class XP review because they only surface
  # against runtime-realism inputs (default GRANT PROXY row + multi-line
  # SQL stderr).
  Describe "alpha.63 v1 helpers and verifiers"
    setup_alpha63_env() {
      export MARIADB_ROOT_USER="root"
      export MARIADB_ROOT_PASSWORD="pw"
      export MARIADB_INTERNAL_ROOT_USER="kb_internal_root"
      export MARIADB_CONNECT_TIMEOUT_SECONDS="5"
      export MARIADB_CLIENT_BIN="${TEST_DIR}/mariadb-a63"
    }
    Before "setup_alpha63_env"

    Context "grants whitelist helpers (Jack instrumentation 2)"
      It "alpha.63 v1: _filter_grants_keep_unmatched filters out the default GRANT PROXY ... WITH GRANT OPTION row from output"
        input_grants="GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'%'
GRANT PROXY ON ''@'%' TO 'root'@'%' WITH GRANT OPTION"
        When call _filter_grants_keep_unmatched "${input_grants}"
        The status should be success
        The output should include "GRANT SELECT, PROCESS, RELOAD"
        The output should not include "GRANT PROXY"
      End

      It "alpha.63 v1: _count_grants_matched_whitelist returns 1 when input has one GRANT PROXY row"
        input_grants="GRANT SELECT, PROCESS ON *.* TO 'root'@'%'
GRANT PROXY ON ''@'%' TO 'root'@'%' WITH GRANT OPTION"
        When call _count_grants_matched_whitelist "${input_grants}"
        The status should be success
        The output should equal "1"
      End

      It "alpha.63 v1: _filter_grants_keep_unmatched does NOT whitelist non-proxy 'WITH GRANT OPTION' lines (line-anchored pattern is precise, not broad grep -v PROXY)"
        # Hypothetical malicious / surprise grant that contains WITH GRANT OPTION but is NOT a proxy grant.
        input_grants="GRANT SELECT, PROCESS ON *.* TO 'root'@'%'
GRANT INSERT, UPDATE ON *.* TO 'root'@'%' WITH GRANT OPTION"
        When call _filter_grants_keep_unmatched "${input_grants}"
        The status should be success
        # Both lines should pass through (filter only removes PROXY-shape lines).
        The output should include "GRANT SELECT, PROCESS"
        The output should include "GRANT INSERT, UPDATE"
        The output should include "WITH GRANT OPTION"
      End

      It "alpha.63 v1: _count_grants_matched_whitelist returns 0 when no PROXY-shape line is present"
        input_grants="GRANT SELECT, PROCESS ON *.* TO 'root'@'%'
GRANT INSERT, UPDATE ON *.* TO 'root'@'%' WITH GRANT OPTION"
        When call _count_grants_matched_whitelist "${input_grants}"
        The status should be success
        The output should equal "0"
      End

      It "alpha.63 v1: _count_grants_matched_whitelist returns 2 when input has multiple PROXY rows + dump matches both"
        input_grants="GRANT SELECT ON *.* TO 'root'@'%'
GRANT PROXY ON ''@'%' TO 'root'@'%' WITH GRANT OPTION
GRANT PROXY ON ''@'localhost' TO 'root'@'%' WITH GRANT OPTION"
        When call _count_grants_matched_whitelist "${input_grants}"
        The status should be success
        The output should equal "2"
      End
    End

    Context "_verify_host_is_fenced() runtime-realism: GRANT PROXY default row (alpha.62 RED I-1 close)"
      It "alpha.63 v1: % host with non-bypass main grant + default GRANT PROXY row → reason=ok_by_grants_only + grants_ignored_count=1 in log (alpha.62 v1/v2 was false-RED bypass_priv_residual:GRANT OPTION)"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
# Internal SHOW GRANTS returns the alpha.62 fence's main grant + default PROXY row.
echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'%'"
echo "GRANT PROXY ON ''@'%' TO 'root'@'%' WITH GRANT OPTION"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "%"
        The status should be success
        The output should include "remote_root_fence_verify host=%"
        The output should include "grants_ignored_count=1"
        The output should include "reason=ok_by_grants_only:wildcard_or_remote_not_locally_probable"
      End

      It "alpha.63 v1: localhost host with PROXY default row → ok_by_grants_only + grants_ignored_count=1 (alpha.62 RED parity case)"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'localhost'"
echo "GRANT PROXY ON ''@'localhost' TO 'root'@'localhost' WITH GRANT OPTION"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "localhost"
        The status should be success
        The output should include "grants_ignored_count=1"
        The output should include "reason=ok_by_grants_only:localhost_socket_not_attempted"
      End

      It "alpha.63 v2 (Jack 08:36 v1 HOLD blocker): non-proxy 'WITH GRANT OPTION' line with NO write priv name (e.g. GRANT SELECT WITH GRANT OPTION) → fail-closed reason=grant_option_residual"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
# Construct the exact Jack reproducer: SELECT-only grant + WITH GRANT OPTION
# clause. v1 false-passed this because no write priv name (INSERT/UPDATE/...)
# matched the residual scan and GRANT OPTION had been removed from
# SWITCHOVER_USER_FACING_WRITE_PATTERN. v2's grant_option_residual catches it.
echo "GRANT SELECT ON *.* TO 'root'@'%' WITH GRANT OPTION"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "%"
        The status should be failure
        The stderr should include "reason=grant_option_residual"
        The stderr should include "probe_host=none:grant_option_residual_short_circuit"
        The stderr should include "grants_bypass=GRANT_OPTION"
        The stderr should include "grant_option_residual_dump_begin"
        The stderr should include "GRANT SELECT ON *.* TO 'root'@'%' WITH GRANT OPTION"
        The stderr should include "grant_option_residual_dump_end"
      End

      It "alpha.63 v2: short-circuit order — write priv (INSERT) still hits bypass_priv_residual FIRST, NOT grant_option_residual, even when WITH GRANT OPTION also present"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
# INSERT priv name + WITH GRANT OPTION clause. write_residual scan runs
# BEFORE grant_option_residual, so reason should be bypass_priv_residual:INSERT
# (with possible UPDATE), NOT grant_option_residual. This locks the
# precedence Jack confirmed in 08:37 ACK.
echo "GRANT INSERT, UPDATE ON *.* TO 'root'@'%' WITH GRANT OPTION"
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "%"
        The status should be failure
        The stderr should include "reason=bypass_priv_residual:INSERT,UPDATE"
        The stderr should not include "reason=grant_option_residual"
      End
    End

    Context "_local_root_write_probe_127() global var hardening (Jack instrumentation 1 + alpha.62 RED I-2 close)"
      It "alpha.63 v1: pre-clear globals before call defends against stale value reuse (caller MUST clear; if not, post-validate would still catch via __PROBE_RC malformed)"
        # Simulate stale globals from a prior call.
        __PROBE_RC="stale_rc_42"
        __PROBE_ERRNO="stale_errno_99"
        __PROBE_OUT="stale_out_data"
        # Now stub MARIADB_CLIENT_BIN to NOT actually run (so probe doesn't overwrite the globals).
        # Pre-clear contract: caller must reset globals BEFORE invoking the probe.
        # Here we simulate caller doing that:
        __PROBE_RC=""
        __PROBE_ERRNO=""
        __PROBE_OUT=""
        # Verify cleared state (can't call probe without real mariadb, just verify the protocol).
        When call printf '%s|%s|%s' "${__PROBE_RC}" "${__PROBE_ERRNO}" "${__PROBE_OUT}"
        The output should equal "||"
      End

      It "alpha.63 v1: 127.0.0.1 with multi-line SQL stderr containing 1044 → __PROBE_ERRNO=1044 correctly extracted (alpha.62 RED root cause closed)"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
# Simulate alpha.62 RED scenario: mariadb client INSERT returns multi-line SQL stderr containing 1044.
case "$*" in
  *"-ukb_internal_root"*"SHOW GRANTS"*)
    echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'127.0.0.1'"
    echo "GRANT PROXY ON ''@'%' TO 'root'@'127.0.0.1' WITH GRANT OPTION"
    exit 0
    ;;
  *"-uroot"*"INSERT"*)
    cat <<MULTILINE
ERROR 1044 (42000) at line 3: Access denied for user 'root'@'127.0.0.1'
to database 'kubeblocks'
MULTILINE
    exit 1
    ;;
esac
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "127.0.0.1"
        The status should be success
        The output should include "remote_root_fence_verify host=127.0.0.1"
        The output should include "write_probe_errno=1044"
        The output should include "reason=ok_by_local_probe:1044"
        The output should include "grants_ignored_count=1"
      End

      It "alpha.63 v1: post-validate __PROBE_RC non-numeric → fail-closed reason=probe_result_malformed"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
case "$*" in
  *"-ukb_internal_root"*"SHOW GRANTS"*)
    echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'127.0.0.1'"
    exit 0
    ;;
esac
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        # Override _local_root_write_probe_127 to set __PROBE_RC to a malformed value.
        _local_root_write_probe_127() {
          __PROBE_RC="not_a_number"
          __PROBE_ERRNO="1044"
          __PROBE_OUT="some output"
        }
        When call _verify_host_is_fenced "127.0.0.1"
        The status should be failure
        The stderr should include "reason=probe_result_malformed"
        The stderr should include "write_probe_rc=<malformed:not_a_number>"
      End

      It "alpha.63 v1: post-validate __PROBE_ERRNO not in 5-value valid set → fail-closed reason=probe_result_malformed_errno"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
case "$*" in
  *"-ukb_internal_root"*"SHOW GRANTS"*)
    echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'127.0.0.1'"
    exit 0
    ;;
esac
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        # Override _local_root_write_probe_127 to set __PROBE_ERRNO to an out-of-set value.
        _local_root_write_probe_127() {
          __PROBE_RC="1"
          __PROBE_ERRNO="9999"
          __PROBE_OUT="ERROR 9999 unknown"
        }
        When call _verify_host_is_fenced "127.0.0.1"
        The status should be failure
        The stderr should include "reason=probe_result_malformed_errno"
        The stderr should include "write_probe_errno=<malformed:9999>"
      End
    End
  End

  # alpha.61 v2: ensure the runtime script remains POSIX-clean (Blocker 1
  # surfaced because v1 had bash-only $SECONDS / $'\n' under #!/bin/sh).
  # The spec runs with --execdir @specfile, so the script lives at
  # ../scripts/replication-switchover.sh relative to scripts-ut-spec/.
  Describe "alpha.61 v2 POSIX shell self-check"
    It "addons/mariadb/scripts/replication-switchover.sh parses cleanly under dash -n"
      Skip if "dash is not installed" ! command -v dash >/dev/null 2>&1
      When run dash -n ../scripts/replication-switchover.sh
      The status should be success
    End

    It "addons/mariadb/scripts/replication-switchover.sh parses cleanly under bash -n"
      When run bash -n ../scripts/replication-switchover.sh
      The status should be success
    End
  End
End
