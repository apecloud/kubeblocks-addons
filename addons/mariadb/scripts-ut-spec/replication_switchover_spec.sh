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
        The output should include "Switchover action returned: DCS recorded, current primary fenced, candidate writable. Post-DCS convergence delegated"
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
        The output should include "Switchover action returned: DCS recorded, current primary fenced, candidate writable. Post-DCS convergence delegated"
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
        The output should include "Switchover action returned: DCS recorded, current primary fenced, candidate writable. Post-DCS convergence delegated"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_switchover_done_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_post_switchover_stabilization_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_primary_service_routes_candidate_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_current_secondary_remote_root_fenced_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_current_follows_candidate_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_primary_service_routes_candidate_called"
      End

      It "alpha.59 contract: fails closed when candidate remote root write probe does not close in budget"
        export CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS=0
        export SWITCHOVER_POLL_SECONDS=1
        make_syncerctl
        prepare_current_primary_for_switchover() { return 0; }
        fence_local_remote_root_for_secondary() { return 0; }
        local_remote_root_is_fenced_for_secondary() { return 0; }
        remote_root_write_ready() { return 1; }
        query_value() {
          case "$1:$2" in
            "127.0.0.1:SELECT @@global.read_only;"*) echo "1" ;;
          esac
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be failure
        The output should include "Switchover post-DCS guard passed"
        The stderr should include "Switchover failed: candidate remote root write probe did not close for mdb-mariadb-1"
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
End
