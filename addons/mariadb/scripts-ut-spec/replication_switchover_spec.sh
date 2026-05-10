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
      It "keeps follow-time admin privileges when fencing remote root DML"
        export MARIADB_ROOT_USER="root"
        export MARIADB_ROOT_PASSWORD="pw"
        export MARIADB_ROOT_HOST="%"
        run_sql() {
          record_call "run_sql=$2"
          return 0
        }
        run_local_sql_best_effort() {
          record_call "best_effort=$1"
          return 0
        }
        When call fence_local_remote_root_for_secondary
        The status should be success
        The output should include "optional REPLICATION MASTER ADMIN granted"
        The contents of file "${TEST_DIR}/calls" should include "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT"
        The contents of file "${TEST_DIR}/calls" should include "GRANT REPLICATION MASTER ADMIN"
        The contents of file "${TEST_DIR}/calls" should include "GRANT READ_ONLY ADMIN"
        The contents of file "${TEST_DIR}/calls" should include "best_effort=FLUSH PRIVILEGES;"
      End

      It "disconnects active remote root sessions around the grant fence"
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

    It "alpha.60 v2: grants explicit non-bypass privilege list, never GRANT ALL PRIVILEGES"
      run_sql() {
        record_call "run_sql=$2"
        return 0
      }
      When call unfence_local_remote_root_for_primary
      The status should be success
      The contents of file "${TEST_DIR}/calls" should include "REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'root'@'%'"
      The contents of file "${TEST_DIR}/calls" should include "ON *.* TO 'root'@'%' WITH GRANT OPTION"
      The contents of file "${TEST_DIR}/calls" should not include "GRANT ALL PRIVILEGES ON *.*"
      The contents of file "${TEST_DIR}/calls" should not include "SUPER"
      The contents of file "${TEST_DIR}/calls" should not include "READ_ONLY ADMIN"
      The contents of file "${TEST_DIR}/calls" should not include "BINLOG ADMIN"
      The contents of file "${TEST_DIR}/calls" should not include ", GRANT OPTION,"
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

    It "sets SWITCHOVER_HAS_TIMEOUT=0 when timeout(1) is absent (caller responsible for fail-closed)"
      command() {
        if [ "$1" = "-v" ] && [ "$2" = "timeout" ]; then return 1; fi
        builtin command "$@"
      }
      action_started_epoch=""
      SWITCHOVER_HAS_TIMEOUT=""
      When call initialize_action_clock
      The status should be success
      The variable SWITCHOVER_HAS_TIMEOUT should equal "0"
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

    It "fails closed at dcs stage with action_deadline_exhausted_dcs when prepare consumes the deadline"
      prepare_current_primary_for_switchover() {
        # Burn 100s during prepare.
        advance_clock 100
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "Switchover stage prepare"
      The stderr should include "reason=action_deadline_exhausted_dcs"
      The stderr should include "fail-closed"
    End

    It "fails closed at fence stage with action_deadline_exhausted_fence when dcs consumes the deadline"
      prepare_current_primary_for_switchover() { return 0; }
      syncerctl_switchover() {
        advance_clock 100
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "Switchover stage dcs"
      The stderr should include "reason=action_deadline_exhausted_fence"
      The stderr should include "fail-closed"
    End

    It "fails closed at promote stage with action_deadline_exhausted_promote when fence consumes the deadline"
      prepare_current_primary_for_switchover() { return 0; }
      syncerctl_switchover() { return 0; }
      fence_current_primary_local_writes_after_dcs() {
        advance_clock 100
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "Switchover stage fence"
      The stderr should include "reason=action_deadline_exhausted_promote"
      The stderr should include "fail-closed"
    End

    It "fails closed at write stage with action_deadline_exhausted_write when promote consumes the deadline"
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

    It "fails closed at any stage with cause=action_clock_unavailable when wall clock fails mid-action"
      prepare_current_primary_for_switchover() {
        # Break the clock mid-action.
        echo "not-a-number" > "${TEST_DIR}/clock_now"
        return 0
      }
      When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.headless.demo.svc.cluster.local"
      The status should be failure
      The output should include "Switchover stage prepare"
      The stderr should include "reason=action_deadline_exhausted_dcs"
      The stderr should include "cause=action_clock_unavailable"
      The stderr should include "fail-closed"
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
