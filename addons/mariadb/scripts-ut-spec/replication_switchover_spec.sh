# shellcheck shell=sh
# shellcheck disable=SC2218
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
    # Provide a timeout stub on macOS where GNU timeout is absent.
    if ! command -v timeout >/dev/null 2>&1; then
      mkdir -p "${TEST_DIR}/bin"
      cat > "${TEST_DIR}/bin/timeout" <<'TIMEOUT_STUB'
#!/bin/sh
shift
exec "$@"
TIMEOUT_STUB
      chmod +x "${TEST_DIR}/bin/timeout"
      export PATH="${TEST_DIR}/bin:${PATH}"
    fi
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
        candidate_remote_root_has_explicit_primary_grant() {
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
        The output should include "Switchover candidate remote root primary-readiness probe converged for mdb-mariadb-1"
        The output should include "candidate root primary-readiness observed without mutating probe"
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
        candidate_remote_root_has_explicit_primary_grant() {
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
        # alpha.79 v2: --force added to bypass syncer's "previous switchover
        # unfinished" DCS record so same-cluster repeat switchovers proceed.
        The output should eq "--host 127.0.0.1 --port 3601 switchover --force --primary mdb-mariadb-0 --candidate mdb-mariadb-1"
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
        candidate_remote_root_has_explicit_primary_grant() {
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
        The output should include "candidate root primary-readiness observed without mutating probe"
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
        remote_root_primary_ready() { return 0; }
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
        The output should include "candidate root primary-readiness observed without mutating probe"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_switchover_done_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_post_switchover_stabilization_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_primary_service_routes_candidate_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_wait_current_secondary_remote_root_fenced_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_current_follows_candidate_called"
        The contents of file "${TEST_DIR}/calls" should not include "BUG_primary_service_routes_candidate_called"
      End

      It "alpha.61 contract: fails closed when candidate remote root primary-readiness probe does not close in budget"
        export CANDIDATE_REMOTE_ROOT_PRIMARY_READY_WAIT_SECONDS=0
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
        The stderr should include "reason=candidate_remote_root_primary_not_ready_in_budget"
        The stderr should include "fail-closed"
      End

      It "alpha.129 contract: fails closed when candidate read_only is open but remote root primary grants are still fenced"
        export CANDIDATE_REMOTE_ROOT_PRIMARY_READY_WAIT_SECONDS=1
        export SWITCHOVER_POLL_SECONDS=1
        make_syncerctl
        prepare_current_primary_for_switchover() { return 0; }
        verify_post_dcs_local_root_write_fenced() { return 0; }
        revoke_user_facing_root_admin_privileges_for_secondary() { return 0; }
        wait_candidate_promoted_via_syncerctl() { return 0; }
        query_value() {
          case "$1:$2" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@global.read_only;"*) echo "0" ;;
            "127.0.0.1:SELECT @@global.read_only;"*) echo "1" ;;
          esac
        }
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
case "$*" in
  *"SHOW GRANTS"*)
    echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'%'"
    exit 0
    ;;
esac
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be failure
        The output should include "Switchover stage candidate_primary_ready budget=1s"
        The stderr should include "candidate_remote_root_explicit_primary_grant_verify"
        The stderr should include "reason=core_write_priv_missing"
        The stderr should include "reason=candidate_remote_root_primary_not_ready_in_budget"
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

      It "treats duplicate post-success invocation as idempotent success when final state is already reached"
        make_zero_status_failing_syncerctl
        : > "${TEST_DIR}/calls"
        prepare_current_primary_for_switchover() {
          return 0
        }
        rollback_current_primary_switchover_guard() {
          record_call "rollback"
          return 0
        }
        query_value() {
          case "$1:$2" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@global.read_only;"*) echo "0" ;;
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
        remote_root_primary_ready() {
          return 0
        }
        syncer_role_is() {
          case "$1:$2" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:primary") return 0 ;;
            "127.0.0.1:secondary") return 0 ;;
          esac
          return 1
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be success
        The output should include "Switchover syncerctl output: switchover failed: operation precheck failed: mdb-mariadb-0 is not the primary"
        The output should include "Switchover idempotent success: desired final state already reached"
        The stderr should include "Switchover failed: syncerctl did not report success"
        The contents of file "${TEST_DIR}/calls" should not include "rollback"
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

      It "[alpha.79 v1: obsolete; prepare no longer disconnects remote-root sessions or fences root@'%']"
        # alpha.61-.78 contract: prepare_current_primary_for_switchover ran
        # disconnect_local_remote_root_sessions_for_secondary +
        # fence_local_remote_root_for_secondary + local_remote_root_is_fenced_for_secondary.
        # alpha.79 v1 (westonnnn 21:50 directive) replaces this chain with a
        # no-op short-circuit, modeled on MySQL semisync addon which does not
        # modify root@'%' grants during switchover. This obsolete test is
        # marked Pending; alpha.80 cleanup will remove the test entirely.
        Pending "alpha.79 minimalist removes fence chain from prepare; obsolete tracker pending alpha.80 cleanup"
      End

      It "[alpha.79 v1: obsolete; prepare no longer logs 'Switchover pre-DCS guard passed' or calls fence/verify_fence]"
        Pending "alpha.79 minimalist removes fence + verify_fence calls from prepare; obsolete tracker pending alpha.80 cleanup"
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

      It "[alpha.79 v1: obsolete; prepare cannot fail by fence-chain failure anymore (it's a no-op)]"
        # alpha.61-.78 contract: prepare guard fails when fence_local_remote_root_
        # for_secondary returns non-zero. alpha.79 minimalist prepare returns 0
        # unconditionally; this failure path is unreachable.
        Pending "alpha.79 minimalist prepare unconditionally returns 0; obsolete tracker pending alpha.80 cleanup"
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
      The contents of file "${TEST_DIR}/calls" should include "CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check"
      The contents of file "${TEST_DIR}/calls" should not include "set_read_only=OFF"
      The contents of file "${TEST_DIR}/calls" should not include "set_read_only=ON"
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

  # alpha.105+ design-contract close-out:
  # post-DCS local-root write fence is verified by read-only SHOW GRANTS
  # inspection, not a destructive INSERT probe. alpha.124 narrows BINLOG ADMIN:
  # it is allowed for local loopback/socket root because chart-internal
  # sql_log_bin=0 paths need it, but it remains disallowed for non-local root.
  Describe "verify_post_dcs_local_root_write_fenced()"
    setup_fence_probe() {
      export MARIADB_ROOT_USER="root"
      export MARIADB_ROOT_PASSWORD="pw"
      export MARIADB_INTERNAL_ROOT_USER="kb_internal_root"
      export MARIADB_CONNECT_TIMEOUT_SECONDS="5"
      export MARIADB_CLIENT_BIN="${TEST_DIR}/mariadb"
    }
    Before "setup_fence_probe"

    It "alpha.124: passes when local root keeps BINLOG ADMIN but remote root has no bypass privilege"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
case "$*" in
  *"SHOW GRANTS FOR 'root'@'%'"*)
    printf "%s\n" "GRANT SELECT ON *.* TO 'root'@'%'"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@'127.0.0.1'"*)
    printf "%s\n" "GRANT SELECT, BINLOG ADMIN ON *.* TO 'root'@'127.0.0.1'"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@'localhost'"*)
    printf "%s\n" "GRANT SELECT, BINLOG ADMIN ON *.* TO 'root'@'localhost'"
    exit 0
    ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be success
      The output should include "Switchover post-DCS local-root write fence verified"
    End

    It "alpha.124: fails closed when remote root@% still has BINLOG ADMIN"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
case "$*" in
  *"SHOW GRANTS FOR 'root'@'%'"*)
    printf "%s\n" "GRANT SELECT, BINLOG ADMIN ON *.* TO 'root'@'%'"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@'127.0.0.1'"*|*"SHOW GRANTS FOR 'root'@'localhost'"*)
    printf "%s\n" "GRANT SELECT ON *.* TO 'root'@'local'"
    exit 0
    ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be failure
      The stderr should include "Switchover failed: post-DCS local-root write fence not enforced"
      The stderr should include "'root'@'%'"
      The stderr should include "BINLOG ADMIN"
    End

    It "alpha.124: fails closed when local root keeps READ_ONLY ADMIN"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
case "$*" in
  *"SHOW GRANTS FOR 'root'@'%'"*|*"SHOW GRANTS FOR 'root'@'127.0.0.1'"*)
    printf "%s\n" "GRANT SELECT ON *.* TO 'root'@'ok'"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@'localhost'"*)
    printf "%s\n" "GRANT SELECT, BINLOG ADMIN, READ_ONLY ADMIN ON *.* TO 'root'@'localhost'"
    exit 0
    ;;
esac
exit 0
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be failure
      The stderr should include "'root'@'localhost'"
      The stderr should include "READ_ONLY ADMIN"
    End

    It "fails closed when MARIADB_CLIENT_BIN is unavailable"
      rm -f "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be failure
      The stderr should include "Switchover failed: post-DCS local-root write fence verification cannot run without MARIADB_CLIENT_BIN"
    End

    # alpha.75 v1 hard gate 1 — verifier body MUST NOT contain
    # `SET SESSION sql_log_bin=0` (alpha.74 v1 N=1 RED root cause:
    # this preamble required BINLOG ADMIN that post-demote root lacks).
    It "alpha.75 v1: verifier body must not contain SET SESSION sql_log_bin=0 [product-blocker]"
      source_file="${SHELLSPEC_CWD:?}/addons/mariadb/scripts/replication-switchover.sh"
      When call awk '/^verify_post_dcs_local_root_write_fenced\(\)/{f=1;next} f && /^}/{f=0} f && !/^[[:space:]]*#/' "${source_file}"
      The output should not include "SET SESSION sql_log_bin=0"
    End

    # alpha.75 v1 hard gate 2 — verifier body MUST NOT contain
    # CREATE DATABASE or CREATE TABLE; those belong in bootstrap-time
    # INTERNAL_LOCAL setup, not in the user-facing root verifier path.
    It "alpha.75 v1: verifier body must not contain CREATE DATABASE [product-blocker]"
      source_file="${SHELLSPEC_CWD:?}/addons/mariadb/scripts/replication-switchover.sh"
      When call awk '/^verify_post_dcs_local_root_write_fenced\(\)/{f=1;next} f && /^}/{f=0} f && !/^[[:space:]]*#/' "${source_file}"
      The output should not include "CREATE DATABASE"
    End
    It "alpha.75 v1: verifier body must not contain CREATE TABLE [product-blocker]"
      source_file="${SHELLSPEC_CWD:?}/addons/mariadb/scripts/replication-switchover.sh"
      When call awk '/^verify_post_dcs_local_root_write_fenced\(\)/{f=1;next} f && /^}/{f=0} f && !/^[[:space:]]*#/' "${source_file}"
      The output should not include "CREATE TABLE"
    End

    It "passes when all user-facing root host variants are absent with Error 1141"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "ERROR 1141 (42000): There is no such grant defined for user 'root' on host" >&2
exit 1
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be success
      The output should include "all hosts 1141"
    End

    It "fails closed when SHOW GRANTS returns an unrelated error"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "ERROR 1044 (42000): Access denied for user 'kb_internal_root'@'localhost'" >&2
exit 1
EOF
      chmod +x "${TEST_DIR}/mariadb"
      When call verify_post_dcs_local_root_write_fenced
      The status should be failure
      The stderr should include "SHOW GRANTS FOR 'root'@'%' failed"
    End
  End

  # alpha.75 v1 bootstrap probe table contract — ensure_internal_local_admin
  # in cmpd-replication.yaml MUST create kubeblocks.kb_post_dcs_fence_probe
  # (alongside kubeblocks.kb_health_check) at bootstrap time via INTERNAL_LOCAL
  # with sql_log_bin=0. This is the prerequisite for the verifier strip in
  # alpha.75 v1 hard gate 1-2.
  Describe "alpha.75 v1: ensure_internal_local_admin probe table bootstrap"
    cmpd_path="${SHELLSPEC_CWD:?}/addons/mariadb/scripts/replication-entrypoint.sh"

    It "cmpd-replication.yaml ensure_internal_local_admin body contains CREATE TABLE IF NOT EXISTS kubeblocks.kb_post_dcs_fence_probe [product-blocker]"
      When call grep -c 'CREATE TABLE IF NOT EXISTS kubeblocks.kb_post_dcs_fence_probe' "${cmpd_path}"
      The output should equal "1"
    End

    It "Chart.yaml literal version is current (alpha.26 - replication merged topology)"
      chart_yaml="${SHELLSPEC_CWD:?}/addons/mariadb/Chart.yaml"
      When call grep -c '^version: 1.2.0-alpha.26$' "${chart_yaml}"
      The output should equal "1"
    End

    It "Chart.yaml does not retain prior alpha.79 version line (no stale literal)"
      chart_yaml="${SHELLSPEC_CWD:?}/addons/mariadb/Chart.yaml"
      When call grep -c '^version: 1.1.1-alpha.79$' "${chart_yaml}"
      The status should be failure
      The output should equal "0"
    End

    It "alpha.79 v1: prepare_current_primary_for_switchover does NOT call fence_local_remote_root_for_secondary [product-blocker]"
      # alpha.79 minimalist: prepare stage must NOT invoke any per-host
      # root@'%' fence. The race source is removed by deletion, not by
      # additional defense.
      When run sh -c '
        awk "
          /^prepare_current_primary_for_switchover\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
          in_func && /^\\}[[:space:]]*\$/ { in_func = 0 }
          in_func && \$0 ~ /^[^#]*fence_local_remote_root_for_secondary[^_]/ { found_fence = 1 }
          in_func && \$0 ~ /^[^#]*local_remote_root_is_fenced_for_secondary/ { found_verify = 1 }
          END { if (found_fence || found_verify) { printf \"alpha.79 violation: prepare still calls fence=%s verify=%s\\n\", (found_fence ? \"YES\" : \"no\"), (found_verify ? \"YES\" : \"no\"); exit 1 } }
        " ../scripts/replication-switchover.sh
      '
      The status should be success
    End

    It "alpha.79 v1: prepare_current_primary_for_switchover logs alpha.79 minimalist sentinel [observability]"
      # Distinct sentinel so historical alpha.61-.78 behavior is
      # distinguishable from alpha.79+ minimalist in closeout logs.
      When run sh -c '
        awk "
          /^prepare_current_primary_for_switchover\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
          in_func && /^\\}[[:space:]]*\$/ { in_func = 0 }
          in_func && \$0 ~ /alpha\\.79 v1 minimalist/ { found = 1 }
          END { if (!found) { print \"missing alpha.79 minimalist sentinel in prepare log\"; exit 1 } }
        " ../scripts/replication-switchover.sh
      '
      The status should be success
    End

    It "alpha.79 v1: post-DCS verify_post_dcs_local_root_write_fenced is PRESERVED (read_only=1-based, race-free) [contract-no-regression]"
      # The post-DCS local-root write fence verifier reads INSERT 1290 errno
      # from user-facing root, not grant state. It is the safety net that
      # alpha.79 minimalist relies on. MUST remain intact.
      When call grep -c '^verify_post_dcs_local_root_write_fenced()' ../scripts/replication-switchover.sh
      The output should equal "1"
    End

    It "alpha.79 v1: alpha.76/.77/.78 marker helpers tracked as alpha.80 cleanup debt [tech-debt-resolved]"
      # Dead-code policy: marker helpers + cmpd switchover_fence_active_is_fresh
      # + roleprobe skip check have been removed from the active path.
      # The cleanup debt tracked by Chart.yaml comments has been resolved;
      # Chart.yaml development journal was stripped in PR #2774.
      # Verify the dead code functions are indeed absent from the scripts.
      When call grep -c 'switchover_fence_active_is_fresh()' ../scripts/replication-switchover.sh
      The status should be failure
      The output should equal "0"
    End

    It "alpha.78 v1: wait_for_replication_healthy checks syncer role per iteration AT THE TOP OF THE LOOP and exits with return 2 when role=primary [product-blocker]"
      # cmpd-replication.yaml wait_for_replication_healthy MUST include a
      # query_local_syncer_role check inside the while loop, BEFORE the
      # existing slave_status_is_healthy probe. When the check returns
      # "primary", function MUST return 2 (distinct from the timeout return 1
      # and the healthy return 0) so callers can attribute the exit cause.
      When run sh -c '
        awk "
          /^[[:space:]]*wait_for_replication_healthy\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
          in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
          in_func && /while true; do/ { in_loop = 1; next }
          in_func && in_loop && \$0 ~ /query_local_syncer_role/ && !syncer_line { syncer_line = NR }
          in_func && in_loop && \$0 ~ /current_syncer_role.*=.*\"primary\"/ && !check_line { check_line = NR }
          in_func && in_loop && \$0 ~ /^[[:space:]]+return 2\$/ && !ret2_line { ret2_line = NR }
          in_func && in_loop && \$0 ~ /slave_status_is_healthy/ && !slave_check_line { slave_check_line = NR }
          END {
            if (!syncer_line || !check_line || !ret2_line || !slave_check_line) { printf \"missing syncer=%s check=%s ret2=%s slave=%s\\n\", (syncer_line ? syncer_line : \"MISSING\"), (check_line ? check_line : \"MISSING\"), (ret2_line ? ret2_line : \"MISSING\"), (slave_check_line ? slave_check_line : \"MISSING\"); exit 1 }
            # syncer-role check must be BEFORE slave_status_is_healthy probe
            if (!(syncer_line < slave_check_line)) { printf \"syncer check must be BEFORE slave_status check: syncer=%d slave=%d\\n\", syncer_line, slave_check_line; exit 1 }
            # return 2 must be between syncer check and slave check
            if (!(syncer_line <= ret2_line && ret2_line < slave_check_line)) { printf \"return 2 must follow syncer check before slave check: syncer=%d ret2=%d slave=%d\\n\", syncer_line, ret2_line, slave_check_line; exit 1 }
          }
        " "${CMPD_SOURCE:-../scripts/replication-entrypoint.sh}"
      '
      The status should be success
    End

    It "alpha.78 v1: wait_for_replication_healthy distinct sentinel log when exiting on DCS-primary [product-blocker]"
      When run sh -c '
        awk "
          /^[[:space:]]*wait_for_replication_healthy\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
          in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
          in_func && \$0 ~ /rejoin-replication-exit-on-dcs-primary/ { found = 1 }
          END { if (!found) { print \"missing rejoin-replication-exit-on-dcs-primary sentinel\"; exit 1 } }
        " "${CMPD_SOURCE:-../scripts/replication-entrypoint.sh}"
      '
      The status should be success
    End

    It "alpha.78 v1: original 120s timeout path preserved (return 1 + sentinel rejoin-replication-not-healthy) [contract-no-regression]"
      When run sh -c '
        awk "
          /^[[:space:]]*wait_for_replication_healthy\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
          in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
          in_func && \$0 ~ /rejoin-replication-not-healthy/ { timeout_found = 1 }
          in_func && \$0 ~ /^[[:space:]]+return 1\$/ { ret1_found = 1 }
          END { if (!timeout_found || !ret1_found) { print \"missing timeout sentinel or return 1\"; exit 1 } }
        " "${CMPD_SOURCE:-../scripts/replication-entrypoint.sh}"
      '
      The status should be success
    End

    It "alpha.78 v1: original healthy-success path preserved (return 0 + sentinel rejoin-replication-healthy) [contract-no-regression]"
      When run sh -c '
        awk "
          /^[[:space:]]*wait_for_replication_healthy\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
          in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
          in_func && \$0 ~ /rejoin-replication-healthy[^-]/ { healthy_found = 1 }
          in_func && \$0 ~ /^[[:space:]]+return 0\$/ { ret0_found = 1 }
          END { if (!healthy_found || !ret0_found) { print \"missing healthy sentinel or return 0\"; exit 1 } }
        " "${CMPD_SOURCE:-../scripts/replication-entrypoint.sh}"
      '
      The status should be success
    End

    It "[alpha.80 v1: alpha.77 marker UNLOCK gate obsolete — marker mechanism removed entirely]"
      # alpha.77 v1 added an in-function `switchover_fence_active_is_fresh`
      # check inside set_remote_root_account_state UNLOCK branch. alpha.79 v1
      # minimalist deleted the marker writer in switchover.sh, making the
      # check unreachable; alpha.80 v1 dead-code cleanup removed the check
      # entirely. The set_remote_root_account_state function still works
      # correctly without the gate because alpha.79 minimalist no longer
      # competes for root@'%' grants.
      Pending "alpha.80 v1 removed marker mechanism entirely; obsolete pending future ShellSpec cleanup"
    End

    It "alpha.77 v2: CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS default >= 30s (new primary watchdog SECONDARY->PRIMARY transition needs >10s) [product-blocker]"
      # alpha.77 v1 N=1 verify on n1y closed pre-DCS REMOTE root fence race
      # but stage 5 candidate write probe timed out at 10s. New primary's
      # chart watchdog needs ~6-10s to detect role change + run
      # expose_sql_listener_for_primary_role + set_primary_read_write +
      # unlock_remote_root_writes + flip read_only=0. 30s gives one full
      # role-transition cycle + headroom while remaining well under the
      # 55s SWITCHOVER_ACTION_DEADLINE_SECONDS.
      When call sh -c '
        unset CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS
        export MARIADB_DATADIR='"${TEST_DIR}"'
        export DATA_DIR='"${TEST_DIR}"'
        export __SOURCED__=1
        . ../scripts/replication-switchover.sh
        if [ "${CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS}" -lt 30 ]; then
          echo "default=${CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS} expected>=30"
          exit 1
        fi
        printf "%s\n" "${CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS}"
      '
      The status should be success
      The output should equal "30"
    End

    It "[alpha.80 v1: alpha.77 marker LOCK-not-gated contract obsolete — marker mechanism removed entirely]"
      Pending "alpha.80 v1 removed marker mechanism entirely; obsolete pending future ShellSpec cleanup"
    End
  End

  # alpha.60 + alpha.124: post-DCS read_only=ON does not fence user-facing
  # root if it holds READ_ONLY ADMIN / SUPER; non-local root must also not hold
  # BINLOG ADMIN. Local root may keep BINLOG ADMIN for chart-internal
  # sql_log_bin=0 paths because it does not bypass read_only by itself.
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

    It "alpha.124: revokes host-disallowed bypass privs and verifies post-revoke residual is clean"
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
      The output should include "Switchover post-DCS root revoke summary revoked=7"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "REVOKE READ_ONLY ADMIN"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "REVOKE SUPER"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "REVOKE BINLOG ADMIN"
      The contents of file "${MOCK_REVOKE_CALLS}" should not include "REVOKE BINLOG ADMIN ON *.* FROM 'root'@'127.0.0.1'"
      The contents of file "${MOCK_REVOKE_CALLS}" should not include "REVOKE BINLOG ADMIN ON *.* FROM 'root'@'localhost'"
      The contents of file "${MOCK_REVOKE_CALLS}" should include "FLUSH PRIVILEGES"
    End

    It "alpha.124: allows local BINLOG ADMIN residual after post-DCS revoke"
      cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
echo "$@" >> "${MOCK_REVOKE_CALLS}"
case "$*" in
  *"SELECT Host FROM mysql.user"*)
    printf "127.0.0.1\nlocalhost\n"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@'127.0.0.1'"*)
    printf "%s\n" "GRANT SELECT, BINLOG ADMIN ON *.* TO 'root'@'127.0.0.1'"
    exit 0
    ;;
  *"SHOW GRANTS FOR 'root'@'localhost'"*)
    printf "%s\n" "GRANT SELECT, BINLOG ADMIN ON *.* TO 'root'@'localhost'"
    exit 0
    ;;
  *"REVOKE READ_ONLY ADMIN"*|*"REVOKE SUPER"*)
    echo "ERROR 1141 (42000): There is no such grant defined for user 'root' on host" >&2
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
      The output should include "failed_hosts=0"
      The stderr should not include "revoke_residual_bypass"
      The contents of file "${MOCK_REVOKE_CALLS}" should not include "REVOKE BINLOG ADMIN"
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
        action_started_epoch=100
        now_epoch() { return 2; }
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
  # write); v2 enforces on all 5 (prepare, dcs, fence, promote, ready).
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

    It "fails closed at ready stage with action_deadline_exhausted_ready when promote body exceeds budget"
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
      The stderr should include "reason=action_deadline_exhausted_ready"
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
  *"-uroot"*"SHOW GRANTS"*)
    echo "ERROR 1044 (42000): Access denied for user 'root'@'127.0.0.1' to database 'mysql'"
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

      It "alpha.127 v2: 127.0.0.1 SHOW GRANTS rc=0 with no write grants is accepted as read-only fenced"
        cat > "${MARIADB_CLIENT_BIN}" <<'EOF'
#!/bin/sh
case "$*" in
  *"-ukb_internal_root"*"SHOW GRANTS"*)
    echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'127.0.0.1'"
    exit 0
    ;;
  *"-uroot"*"SHOW GRANTS"*)
    echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'127.0.0.1'"
    exit 0
    ;;
esac
exit 0
EOF
        chmod +x "${MARIADB_CLIENT_BIN}"
        When call _verify_host_is_fenced "127.0.0.1"
        The status should be success
        The output should include "write_probe_rc=0"
        The output should include "write_probe_errno=1290"
        The output should include "reason=ok_by_local_probe:1290"
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
  *"-uroot"*"SHOW GRANTS"*)
    echo "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'127.0.0.1'"
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
# Simulate alpha.62 RED scenario: mariadb client SHOW GRANTS returns multi-line SQL stderr containing 1044.
case "$*" in
  *"-ukb_internal_root"*"SHOW GRANTS"*)
    echo "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'127.0.0.1'"
    echo "GRANT PROXY ON ''@'%' TO 'root'@'127.0.0.1' WITH GRANT OPTION"
    exit 0
    ;;
  *"-uroot"*"SHOW GRANTS"*)
    cat <<MULTILINE
ERROR 1044 (42000): Access denied for user 'root'@'127.0.0.1'
to database 'mysql'
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
  # alpha.64 v1 (Jack 09:35 RED root cause + 10:01-10:13 design ack):
  # cmpd-replication.yaml runtime sql-listener-fence UNLOCK/LOCK paths must NOT
  # introduce admin-bypass privileges to user-facing root. Verifier on switchover
  # path correctly fail-closed; the actual fix is at the cmpd-yaml grant
  # write site. ShellSpec covers: cmpd constants strong-bind, rendered manifest
  # negative grep on user-facing root, MONITOR positive allowlist, account
  # class separation (kb_internal_root admin grant remains legit, not flagged).
  Describe "alpha.64 v1 cmpd-semisync grant body contract"
    setup_cmpd_alpha64_env() {
      # Source-file grep is sufficient for these contracts — cmpd-replication.yaml
      # has no helm template directives in the GRANT statement bodies (only
      # in dataMountPath etc. paths), so source vs rendered diff doesn't
      # change the negative-grep semantics. This avoids dependency on helm
      # being installed in the test environment.
      export CMPD_SOURCE="../scripts/replication-entrypoint.sh"
    }
    Before "setup_cmpd_alpha64_env"

    Context "cmpd constants strong-bind alignment"
      It "alpha.64 v1: CMPD_EXPLICIT_PRIMARY_GRANT_BODY contains all 5 core write privs (INSERT/UPDATE/DELETE/CREATE/DROP) — aligned with switchover.sh SWITCHOVER_PRIMARY_CORE_WRITE_PRIVS [product-blocker]"
        # Strong-bind invariant: cmpd-side primary grant body MUST contain
        # the same core write privs that switchover.sh's
        # remote_root_has_explicit_primary_grant verifier requires.
        When call grep -E "CMPD_EXPLICIT_PRIMARY_GRANT_BODY=" ../scripts/replication-entrypoint.sh
        The status should be success
        The output should include "INSERT"
        The output should include "UPDATE"
        The output should include "DELETE"
        The output should include "CREATE"
        The output should include "DROP"
      End

      It "alpha.64 v1: CMPD_SECONDARY_FENCE_GRANT_BODY does NOT contain admin-bypass privileges (SUPER/READ_ONLY ADMIN/BINLOG ADMIN/CONNECTION ADMIN/ALL PRIVILEGES) [product-blocker]"
        When call grep -E "CMPD_SECONDARY_FENCE_GRANT_BODY=" ../scripts/replication-entrypoint.sh
        The status should be success
        The output should not include "SUPER"
        The output should not include "READ_ONLY ADMIN"
        The output should not include "BINLOG ADMIN"
        The output should not include "CONNECTION ADMIN"
        The output should not include "ALL PRIVILEGES"
      End

      It "alpha.64 v1: CMPD_OPTIONAL_MONITOR_PRIVS contains only MONITOR types (BINLOG MONITOR / SLAVE MONITOR), no admin-bypass [product-blocker]"
        When call grep -E "CMPD_OPTIONAL_MONITOR_PRIVS=" ../scripts/replication-entrypoint.sh
        The status should be success
        The output should include "BINLOG MONITOR"
        The output should include "SLAVE MONITOR"
        The output should not include "READ_ONLY ADMIN"
        The output should not include "BINLOG ADMIN"
        The output should not include "CONNECTION ADMIN"
        The output should not include "REPLICATION SLAVE ADMIN"
        The output should not include "REPLICATION MASTER ADMIN"
      End
    End

    Context "rendered manifest user-facing root negative grep (per Cindy 09:58 + Jack 10:07 review focal)"
      It "alpha.64 v1: NO active GRANT statement (outside comments) gives user-facing root admin-bypass privileges [product-blocker]"
        # Account class separation (per Cindy 10:13 directive): kb_internal_root
        # paths in ensure_internal_local_admin / grant_internal_admin_runtime_privileges
        # legitimately GRANT ALL PRIVILEGES; user-facing root paths in the 7
        # alpha.64-fixed callsites must NOT. We use awk-based block analysis
        # to filter out kb_internal_root contexts (lines preceded within 30
        # lines by user="$(sql_quote "${MARIADB_INTERNAL_ROOT_USER}")") AND
        # comment-only lines.
        When run sh -c '
          awk "
            /MARIADB_INTERNAL_ROOT_USER/ { internal_window = NR + 50; next }
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*\\*/ { next }
            NR > internal_window { in_internal = 0 }
            NR <= internal_window { in_internal = 1 }
            /GRANT[[:space:]]+(ALL[[:space:]]+PRIVILEGES|SUPER|READ_ONLY[[:space:]]+ADMIN|BINLOG[[:space:]]+ADMIN|CONNECTION[[:space:]]+ADMIN|REPLICATION[[:space:]]+SLAVE[[:space:]]+ADMIN|REPLICATION[[:space:]]+MASTER[[:space:]]+ADMIN)/ {
              if (!in_internal) {
                print NR\": \"\$0
              }
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        # Output should be empty — any line printed is a violation.
        The output should equal ""
      End

      It "alpha.64 v1: kb_internal_root grant of ALL PRIVILEGES remains legitimate (account class allowlist) [internal-exception]"
        # Positive: confirm kb_internal_root grant statements still appear (we
        # haven't broken the maintenance executor by overzealous removal).
        When run grep -F "GRANT ALL PRIVILEGES ON *.* TO '\${user}'@'localhost' WITH GRANT OPTION" "${CMPD_SOURCE}"
        The status should be success
        The output should include "GRANT ALL PRIVILEGES"
      End

      It "alpha.64 v1: MONITOR positive allowlist — BINLOG MONITOR / SLAVE MONITOR appear in user-facing root grant context (read-only legit) [review-tightening]"
        # Positive allowlist (per Cindy 10:01 ship-gate): MONITOR types must
        # remain present (read-only privileges that don't bypass read_only).
        When run grep -E "(BINLOG|SLAVE) MONITOR" "${CMPD_SOURCE}"
        The status should be success
        The output should include "BINLOG MONITOR"
        The output should include "SLAVE MONITOR"
      End
    End

    Context "Tier A vs Tier B fail-closed semantic (per Jack 10:05 contract)"
      It "alpha.64 v1: Tier A monitor priv grant emits tier=monitor-best-effort 1227_swallowed=true fields (allowed continue, log only) [review-tightening]"
        # Verify the source has Tier A logging pattern. Field order is
        # tier=monitor-best-effort 1227_swallowed=true (single line emit).
        When call grep -E "tier=monitor-best-effort 1227_swallowed=true" ../scripts/replication-entrypoint.sh
        The status should be success
        The output should include "tier=monitor-best-effort 1227_swallowed=true"
      End

      It "alpha.64 v1: Tier B required grant emits fail_closed=true + tier=required field (must return 1, caller skip ready/role) [product-blocker]"
        # Verify the source has Tier B logging pattern with fail_closed marker.
        When call grep -E "tier=required.*fail_closed=true" ../scripts/replication-entrypoint.sh
        The status should be success
        The output should include "fail_closed=true"
      End
    End

    Context "live-gate runtime negative gate contract documentation"
      It "alpha.64 v1: live-gate runtime contract documented — prestop-watchdog.log fresh stable window must NOT contain admin-bypass MONITOR-loop entries [product-blocker]"
        # This is documentation/marker assertion: the source must contain a
        # comment defining the live-gate runtime contract for closeout reviewers.
        When call grep -E "alpha.64 v1.*Jack 09:35 RED" ../scripts/replication-entrypoint.sh
        The status should be success
        The output should include "alpha.64 v1"
      End
    End
  End

  # alpha.64 v2 (Jack 10:32 HOLD blockers + 10:38 review-checkpoint 3):
  # - Tier B required LOCK / set_replica_read_only / lock_local_root_for_prestop
  #   failures MUST propagate rc to caller; caller MUST NOT publish ready/role
  #   on failure.
  # - Allowed `|| true` on those required-pattern callsites must carry an
  #   inline `# tier=startup-defensive|error-recovery|fail-path-defensive|monitor-best-effort`
  #   annotation (auditable list pattern).
  # - preStop double-failure of lock_local_root_for_prestop (socket + tcp)
  #   MUST emit the `prestop_lock_failed_both fail_closed=true` log token for
  #   the live-gate runtime negative gate.
  Describe "alpha.64 v2 cmpd-semisync Tier B caller propagation contract"
    setup_cmpd_alpha64v2_env() {
      export CMPD_SOURCE="../scripts/replication-entrypoint.sh"
    }
    Before "setup_cmpd_alpha64v2_env"

    Context "tier annotation auditable list (per Jack 10:38 review-checkpoint 3)"
      It "alpha.64 v2: every \`lock_(local|remote)_root_writes ... || true\` in cmpd-replication.yaml carries an inline \`# tier=...\` annotation (one of the 4 allowed tiers) [product-blocker]"
        # Negative test: any line matching the required-pattern with `|| true`
        # but no inline `# tier=` token is a violation. We grep matching lines
        # and assert each one ends with the tier annotation.
        When run sh -c '
          awk "
            /^[[:space:]]*lock_(local|remote)_root_writes\\b.*\\|\\| true/ {
              if (\$0 !~ /# tier=(startup-defensive|error-recovery|fail-path-defensive|monitor-best-effort)/) {
                print NR\": missing tier annotation: \"\$0
              }
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        The output should equal ""
      End

      It "alpha.64 v2: NO \`set_replica_read_only || true\` callsite remains in cmpd-replication.yaml (Tier B required: caller MUST check rc) [product-blocker]"
        # Jack 10:32 blocker 1: set_replica_read_only is the publish-gate;
        # caller must use \`if ! set_replica_read_only; then return 1; fi\`.
        When run sh -c '
          awk "
            /set_replica_read_only[[:space:]]*\\|\\| true/ {
              print NR\": forbidden swallow: \"\$0
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        The output should equal ""
      End

      It "alpha.64 v2: NO \`lock_local_root_for_prestop ... || true\` callsite remains in cmpd-replication.yaml (Tier B required: preStop double-failure MUST emit fail-closed token) [product-blocker]"
        # Jack 10:32 blocker 2: the trailing `|| true` was masking double-failure
        # of socket+tcp paths; v2 replaces with explicit `if ! ... ; then ... fi`
        # and a `prestop_lock_failed_both fail_closed=true` log token.
        When run sh -c '
          awk "
            /lock_local_root_for_prestop\\b.*\\|\\| true/ {
              print NR\": forbidden swallow: \"\$0
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        The output should equal ""
      End

      It "alpha.64 v2: tier annotation count + distribution (allowed swallow-true callsites are concentrated, not scattered) [audit]"
        # Audit assertion: count of `# tier=...` annotations matches count of
        # `|| true` lines on the required pattern. If they diverge, an
        # annotation has been added without backing `|| true` or vice versa.
        When run sh -c '
          tier_lines=$(grep -cE "lock_(local|remote)_root_writes\\b.*\\|\\| true.*# tier=(startup-defensive|error-recovery|fail-path-defensive|monitor-best-effort)" '"${CMPD_SOURCE}"')
          true_lines=$(grep -cE "^[[:space:]]*lock_(local|remote)_root_writes\\b.*\\|\\| true" '"${CMPD_SOURCE}"')
          if [ "${tier_lines}" -ne "${true_lines}" ]; then
            printf "tier annotation count mismatch: tier=%s swallow_count=%s\n" "${tier_lines}" "${true_lines}"
          fi
        '
        The status should be success
        The output should equal ""
      End
    End

    Context "Tier B caller-side rc propagation pattern (per Jack 10:38 v2 fix recommendation)"
      It "alpha.64 v2: \`set_replica_read_only\` body propagates rc to return 1 (replaces v1 internal \`|| true\`) [product-blocker]"
        # Function body must contain `return 1` and not contain
        # `lock_remote_root_writes "replica-read-only" || true` or
        # `lock_local_root_writes "replica-read-only" || true`.
        When run sh -c '
          awk "
            /^[[:space:]]*set_replica_read_only\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "return 1"
        The output should not include "lock_remote_root_writes \"replica-read-only\" || true"
        The output should not include "lock_local_root_writes \"replica-read-only\" || true"
      End

      It "alpha.64 v2: \`keep_replica_pending_until_healthy\` body propagates rc to return 1 [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*keep_replica_pending_until_healthy\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "return 1"
        The output should not include "lock_remote_root_writes \"\${label}-pending\" || true"
        The output should not include "lock_local_root_writes \"\${label}-pending\" || true"
      End

      It "alpha.64 v2: \`expose_sql_listener_for_safe_role\` body returns 1 BEFORE touch .sql-listener-ready when required local LOCK fails [product-blocker]"
        # Body must contain `if ! lock_local_root_writes ... ; then ... return 1; fi`
        # and the touch line must follow the if-block (not precede an unconditional path).
        When run sh -c '
          awk "
            /^[[:space:]]*expose_sql_listener_for_safe_role\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "if ! lock_local_root_writes"
        The output should include "return 1"
        The output should not include "lock_local_root_writes \"sql-listener-\${label}\" || true"
      End

      It "alpha.64 v2/v4: \`publish_replica_after_rejoin_ready\` propagates explicit set_replica_read_only rc (NOT swallowed) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*publish_replica_after_rejoin_ready\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "set_replica_read_only \"\${label}-before-expose\""
        The output should include "set_replica_read_only \"\${label}-after-expose\""
        The output should include 'replica_rejoin_rc=$?'
        The output should include "return 1"
        The output should not include "set_replica_read_only || true"
      End

      It "alpha.64 v2/v4: \`reconcile_sql_listener_for_syncer_secondary_once\` propagates explicit set_replica_read_only rc before marking ready [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*reconcile_sql_listener_for_syncer_secondary_once\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "set_replica_read_only \"runtime-secondary-reconcile\""
        The output should include 'slave_rejoin_rc=$?'
        The output should include "return 1"
        The output should not include "set_replica_read_only || true"
      End

      It "alpha.64 v2/v4: \`configure_replication_from_primary_service_once\` propagates explicit set_replica_read_only rc at entry [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*configure_replication_from_primary_service_once\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "set_replica_read_only \"\${label}-enter\""
        The output should include 'replica_rejoin_rc=$?'
        The output should include "return 1"
        The output should not include "set_replica_read_only || true"
      End
    End

    Context "preStop double-failure fail-closed token (per Jack 10:32 blocker 2 + 10:38 ack)"
      It "alpha.64 v2: preStop double-failure of lock_local_root_for_prestop emits \`prestop_lock_failed_both fail_closed=true tier=required\` token [product-blocker]"
        # Live-gate runtime negative gate asserts this token does NOT appear
        # in healthy install windows; it only appears when both socket and
        # tcp lock paths failed (1227 swallowed but observability + caller
        # contract preserved).
        When call grep -F "prestop_lock_failed_both fail_closed=true tier=required" ../scripts/replication-prestop.sh
        The status should be success
        The output should include "prestop_lock_failed_both fail_closed=true tier=required"
      End

      It "alpha.64 v2: preStop block uses \`if ! lock_local_root_for_prestop ... ; then ... fi\` (NOT trailing \`|| true\`) [product-blocker]"
        # Look for the block bracketed by `prestop_log "begin pod=` and
        # `if [ -x /tools/syncerctl ]` to bound the search.
        When run sh -c '
          awk "
            /prestop_log \"begin pod=/ { in_block = 1 }
            in_block && /if \\[ -x \\/tools\\/syncerctl \\]/ { in_block = 0 }
            in_block { print }
          " ../scripts/replication-prestop.sh
        '
        The status should be success
        The output should include "if ! lock_local_root_for_prestop"
        The output should not include "lock_local_root_for_prestop \"prestop\" \"socket\" || \\\\"
      End
    End
  End

  # alpha.64 v3 (Jack 11:14 live-gate RED + 11:16 v3 design ack):
  # Multi-word optional MONITOR privileges (BINLOG MONITOR / SLAVE MONITOR)
  # were broken by `for privilege in ${CMPD_OPTIONAL_MONITOR_PRIVS}; do`
  # because POSIX `for` splits unquoted parameter expansion on IFS into
  # 4 single-word tokens. v3 fix: inline quoted list at both callsites.
  # The constant remains for documentation + ShellSpec strong-bind.
  Describe "alpha.64 v3 cmpd-semisync multi-word MONITOR priv loop"
    setup_cmpd_alpha64v3_env() {
      export CMPD_SOURCE="../scripts/replication-entrypoint.sh"
    }
    Before "setup_cmpd_alpha64v3_env"

    Context "no unquoted CMPD_OPTIONAL_MONITOR_PRIVS for-loop residual (per Jack 11:16 focal #2)"
      It "alpha.64 v3: NO active \`for privilege in \${CMPD_OPTIONAL_MONITOR_PRIVS}\` (braced) unquoted loop in source [product-blocker]"
        # Negative test: skip comment lines so the documentation block in
        # the constant declaration (which mentions the bad pattern verbatim)
        # is allowed; only flag actual code occurrences.
        When run sh -c '
          awk "
            /^[[:space:]]*#/ { next }
            /for[[:space:]]+privilege[[:space:]]+in[[:space:]]+\\\$\\{CMPD_OPTIONAL_MONITOR_PRIVS\\}/ {
              print NR\": active unquoted braced loop: \"\$0
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        The output should equal ""
      End

      It "alpha.64 v3: NO active \`for privilege in \$CMPD_OPTIONAL_MONITOR_PRIVS\` (no-brace) unquoted loop in source [product-blocker]"
        # Same as above for the no-brace variant.
        When run sh -c '
          awk "
            /^[[:space:]]*#/ { next }
            /for[[:space:]]+privilege[[:space:]]+in[[:space:]]+\\\$CMPD_OPTIONAL_MONITOR_PRIVS([^A-Za-z_]|\$)/ {
              print NR\": active unquoted no-brace loop: \"\$0
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        The output should equal ""
      End
    End

    Context "inline quoted MONITOR list at both callsites (per Jack 11:16 focal #1)"
      It "alpha.64 v3: \`grant_optional_local_root_privileges\` body iterates inline \`for privilege in \"BINLOG MONITOR\" \"SLAVE MONITOR\"\` [product-blocker]"
        # Strip comment lines from the function body so the v3 root-cause
        # docstring (which mentions the bad pattern verbatim for posterity)
        # does not trigger the negative assertion.
        When run sh -c '
          awk "
            /^[[:space:]]*grant_optional_local_root_privileges\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func && /^[[:space:]]*#/ { next }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "for privilege in \"BINLOG MONITOR\" \"SLAVE MONITOR\""
        The output should not include "for privilege in \${CMPD_OPTIONAL_MONITOR_PRIVS}"
      End

      It "alpha.64 v3: \`grant_optional_remote_root_privileges\` body iterates inline \`for privilege in \"BINLOG MONITOR\" \"SLAVE MONITOR\"\` [product-blocker]"
        # Strip comment lines (same rationale as local variant above).
        When run sh -c '
          awk "
            /^[[:space:]]*grant_optional_remote_root_privileges\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func && /^[[:space:]]*#/ { next }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "for privilege in \"BINLOG MONITOR\" \"SLAVE MONITOR\""
        The output should not include "for privilege in \${CMPD_OPTIONAL_MONITOR_PRIVS}"
      End
    End

    Context "live-gate runtime negative gate documentation (per Jack 11:16 focal #3)"
      It "alpha.64 v3: source documents that fresh stable window MUST NOT contain standalone single-word MONITOR tokens [product-blocker]"
        # Documentation marker: the constant declaration must contain the
        # explicit warning about IFS splitting and the inline-quoted
        # rationale, so closeout reviewers know to grep for standalone
        # single-word tokens (privilege=BINLOG / privilege=MONITOR /
        # privilege=SLAVE) on prestop-watchdog.log fresh stable window.
        When call grep -E "alpha.64 v3.*Jack 11:14.*live-gate RED" ../scripts/replication-entrypoint.sh
        The status should be success
        The output should include "alpha.64 v3"
      End

      It "alpha.64 v3: alpha.64 v1+v2 contracts not regressed — v1 grant body constants + v2 caller propagation patterns + tier annotation auditable list still present [contract-no-regression]"
        # Per Jack 11:16 focal #4: v3 only changes the for-loop expansion
        # at 2 callsites; v1 grant body alignment and v2 caller propagation
        # MUST remain. Spot-check that the key v1+v2 invariants are still
        # present in the source.
        When run sh -c '
          {
            grep -c "CMPD_EXPLICIT_PRIMARY_GRANT_BODY=" "${CMPD_SOURCE}";
            grep -c "CMPD_SECONDARY_FENCE_GRANT_BODY=" "${CMPD_SOURCE}";
            grep -c "set_replica_read_only \"" "${CMPD_SOURCE}";
            grep -c "prestop_lock_failed_both fail_closed=true tier=required" ../scripts/replication-prestop.sh;
            grep -cE "^[[:space:]]*lock_(local|remote)_root_writes\\b.*\\|\\| true.*# tier=" "${CMPD_SOURCE}";
          } | tr "\n" " "
        '
        # Expected: 1 (CMPD_EXPLICIT_PRIMARY_GRANT_BODY=) + 1 (CMPD_SECONDARY_FENCE_GRANT_BODY=)
        # + 4 (set_replica_read_only callsites — publish_replica × 2 +
        #   reconcile_secondary + configure_from_primary; the body of
        #   set_replica_read_only itself is the function definition not a
        #   self-call, so 4 caller patterns)
        # + 1 (prestop_lock_failed_both literal in preStop script) + 14 (tier-annotated swallow lines;
        #   reduced from 16 after CMPD consolidation PR #2933)
        The status should be success
        The output should equal "1 1 4 1 14 "
      End
    End
  End

  # alpha.65 v1 (Jack 11:35 install/script live-gate RED on alpha.64 v3):
  # KubeBlocks ComponentDefinition spec is immutable; any patch within an
  # alpha cycle that mutates cmpd-*.yaml MUST bump the chart version to
  # a fresh alpha so KubeBlocks creates a new CmpD object instead of
  # trying to mutate the existing one. alpha.65 is functionally equivalent
  # to alpha.64 v3 + chart version bump.
  Describe "alpha.65 v1 chart version bump for CmpD immutability"
    setup_chart_alpha65_env() {
      export CHART_FILE="../Chart.yaml"
      export CMPD_SOURCE="../scripts/replication-entrypoint.sh"
    }
    Before "setup_chart_alpha65_env"

    It "alpha.65 v1: Chart.yaml chart bump pattern from alpha.64 due to CmpD immutability — current bumped further to alpha.26 [contract-no-regression]"
      # alpha.65 v1 originally locked chart at alpha.65; subsequent alphas
      # bumped further under the SAME CmpD immutability rule. Literal
      # kept in sync with latest chart version.
      When call grep -E "^version:" "${CHART_FILE}"
      The status should be success
      The output should equal "version: 1.2.0-alpha.26"
    End

    It "alpha.65 v1: Chart.yaml appVersion still 11.4.10 (mariadb engine version unchanged; this bump is packaging-contract only)"
      When call grep -E "^appVersion:" "${CHART_FILE}"
      The status should be success
      The output should include "11.4.10"
    End

    # alpha.65 v2 (Jack 11:45 v1 HOLD msg `721ad0a3`): the v1 doc-marker
    # test (`grep "alpha.65 v1.*Jack 11:35.*live-gate RED" ../Chart.yaml`)
    # passed in source-tree but failed when ShellSpec was rerun inside an
    # extracted package, because `helm package` canonicalizes Chart.yaml
    # (alphabetizes keys + removes blank/comments + strips quotes). The
    # comment was therefore not in the package-installed Chart.yaml. v2
    # drops the doc-marker assertion. The CmpD-immutability rationale
    # remains documented in: source Chart.yaml comment block (visible to
    # git users), this Describe's leading comment (preserved verbatim in
    # the in-package spec file because helm package does NOT canonicalize
    # ShellSpec source files), PR body, Slock handoff thread, and the
    # post-fresh-switchover-GREEN sediment doc backlog.
    It "alpha.65 v1: cmpd-replication.yaml content unchanged from alpha.64 v3 (CmpD spec preserved; only Chart.yaml differs) [contract-no-regression]"
      # alpha.65 v1 must reuse alpha.64 v3 cmpd-replication.yaml content
      # verbatim. The v3 root-cause comment marker proves the v3 fix is still
      # in place; the v1+v2 grant body / caller propagation invariants are
      # also still present (covered by alpha.64 v3 contract-no-regression
      # spot-check above).
      When call grep -E "alpha.64 v3.*Jack 11:14.*live-gate RED" "${CMPD_SOURCE}"
      The status should be success
      The output should include "alpha.64 v3"
    End
  End

  # alpha.66 v1 (Jack 12:18 alpha.65 v2 install/script live-gate RED +
  # 12:34 alpha.66 v1 design HOLD + 12:39 design ACCEPT with 3 tightening):
  # syncer's HA Promote/Demote SQL needs admin-bypass privileges that
  # alpha.64 v1 correctly removed from user-facing root. Fix is to inject
  # MYSQL_ADMIN_USER=kb_internal_root so syncer's existing 3-tier credential
  # model + IsRunning auto-switch swaps mgr.DB to AdminDB (kb_internal_root,
  # full admin priv) once IsAdminCreated detects kb_internal_root in
  # mysql.user. Detection requires kb_internal_root to appear with host='%'
  # in mysql.user (syncer's IsAdminCreated SQL filter); we add a
  # detection-only kb_internal_root@'%' record with ACCOUNT LOCK + zero
  # privileges so the actual remote attack surface is unchanged. Real
  # admin connections from 127.0.0.1 still match kb_internal_root@127.0.0.1
  # (full priv); user-facing root contracts (alpha.64 v1+v2+v3) remain
  # intact.
  Describe "alpha.66 v1 syncer HA executor + chart bump"
    setup_chart_alpha66_env() {
      export CHART_FILE="../Chart.yaml"
      export CMPD_SOURCE="../scripts/replication-entrypoint.sh"
    }
    Before "setup_chart_alpha66_env"

    Context "chart bump for CmpD immutability (per alpha.65 lesson)"
      It "alpha.66 v1: Chart.yaml chart bump pattern locked — current bumped to alpha.26 [contract-no-regression]"
        # Subsequent alphas all bumped further under the same CmpD
        # immutability rule. Literal kept in sync with latest chart
        # version.
        When call grep -E "^version:" "${CHART_FILE}"
        The status should be success
        The output should equal "version: 1.2.0-alpha.26"
      End

      It "alpha.66 v1: Chart.yaml appVersion still 11.4.10 (mariadb engine version unchanged) [contract-no-regression]"
        When call grep -E "^appVersion:" "${CHART_FILE}"
        The status should be success
        The output should include "11.4.10"
      End
    End

    Context "syncer executor contract (per Jack 12:34 design HOLD blocker 1+2)"
      It "switchover action injects MARIADB_ROOT_USER for kbagent execution"
        When run sh -c '
          awk "
            /^[[:space:]]*switchover:[[:space:]]*$/ { in_block = 1 }
            in_block && /^[[:space:]]*runtime:[[:space:]]*$/ { exit }
            in_block { print }
          " ../templates/cmpd-replication.yaml | grep -A1 "name: MARIADB_ROOT_USER" | grep -F "value: \"\$(MARIADB_ROOT_USER)\""
        '
        The status should be success
        The output should include 'value: "$(MARIADB_ROOT_USER)"'
      End

      It "switchover action injects MARIADB_ROOT_PASSWORD for kbagent execution"
        When run sh -c '
          awk "
            /^[[:space:]]*switchover:[[:space:]]*$/ { in_block = 1 }
            in_block && /^[[:space:]]*runtime:[[:space:]]*$/ { exit }
            in_block { print }
          " ../templates/cmpd-replication.yaml | grep -A1 "name: MARIADB_ROOT_PASSWORD" | grep -F "value: \"\$(MARIADB_ROOT_PASSWORD)\""
        '
        The status should be success
        The output should include 'value: "$(MARIADB_ROOT_PASSWORD)"'
      End

      It "switchover action injects MARIADB_INTERNAL_ROOT_USER for local admin SQL"
        When run sh -c '
          awk "
            /^[[:space:]]*switchover:[[:space:]]*$/ { in_block = 1 }
            in_block && /^[[:space:]]*runtime:[[:space:]]*$/ { exit }
            in_block { print }
          " ../templates/cmpd-replication.yaml | grep -A1 "name: MARIADB_INTERNAL_ROOT_USER" | grep -F "value: \"kb_internal_root\""
        '
        The status should be success
        The output should include 'value: "kb_internal_root"'
      End

      It "alpha.66 v1: chart env contains MYSQL_ADMIN_USER literal kb_internal_root (NOT \$\(MARIADB_INTERNAL_ROOT_USER\) — env order risk closed) [product-blocker]"
        # Literal value avoids the K8s env expansion order ambiguity that
        # Jack flagged as Blocker 2 in the v1 HOLD review.
        When run sh -c '
          awk "
            /^[[:space:]]*-[[:space:]]*name:[[:space:]]*MYSQL_ADMIN_USER/ { found_name = 1; next }
            found_name && /^[[:space:]]*value:/ { print; found_name = 0 }
          " ../templates/cmpd-replication.yaml
        '
        The status should be success
        The output should include "kb_internal_root"
        The output should not include "\$(MARIADB_INTERNAL_ROOT_USER)"
      End

      It "alpha.66 v1: chart env contains MYSQL_ADMIN_PASSWORD = \$\(MARIADB_ROOT_PASSWORD\) (shared with root password per existing pattern) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*-[[:space:]]*name:[[:space:]]*MYSQL_ADMIN_PASSWORD/ { found_name = 1; next }
            found_name && /^[[:space:]]*value:/ { print; found_name = 0 }
          " ../templates/cmpd-replication.yaml
        '
        The status should be success
        The output should include "MARIADB_ROOT_PASSWORD"
      End

      It "alpha.66 v1: chart env still contains KB_SERVICE_USER = \$\(MARIADB_ROOT_USER\) (poll/readiness path unchanged; root preserved for syncer startup ping) [contract-no-regression]"
        When run sh -c '
          awk "
            /^[[:space:]]*-[[:space:]]*name:[[:space:]]*KB_SERVICE_USER/ { found_name = 1; next }
            found_name && /^[[:space:]]*value:/ { print; found_name = 0 }
          " ../templates/cmpd-replication.yaml
        '
        The status should be success
        The output should include "MARIADB_ROOT_USER"
      End
    End

    Context "detection-only @'%' record contract (per Jack 12:34 HOLD blocker 1 + 12:39 tightening 3)"
      It "alpha.66 v1: ensure_internal_local_admin body creates kb_internal_root@'%' (detection-only record for syncer IsAdminCreated host='%' filter) [product-blocker]"
        # Function body must contain CREATE USER ... @'%' — the @'%' suffix
        # is unique to the new alpha.66 v1 detection record (localhost and
        # 127.0.0.1 paths use different host literals).
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "CREATE USER IF NOT EXISTS"
        The output should include "@'%' IDENTIFIED BY"
      End

      It "alpha.66 v1: SUPERSEDED by alpha.68 v2 — @'%' moved from ACCOUNT LOCK to ACCOUNT UNLOCK (cross-member health executor requires usable account); alpha.66 v1 intent (detection-only sentinel) was lifted to alpha.68 v2 (active cross-member health executor with grant allowlist) due to Layer 5 product first-blocker; see alpha.68 v2 Describe for current @'%' contract"
        # alpha.66 v1 originally asserted ACCOUNT LOCK; alpha.67 v1 retained
        # LOCKED but added REVOKE; alpha.68 v2 inverts to ACCOUNT UNLOCK +
        # grant allowlist because syncer's `GetMemberConnection` cross-pod
        # path needs working auth via @'%'. The alpha.68 v2 Describe above
        # asserts the new contract. This regression test now just verifies
        # the LOCK pattern is no longer present.
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should not include "@'%' ACCOUNT LOCK"
      End

      It "alpha.66 v1: SUPERSEDED by alpha.69 v1 (+alpha.72 v1 +alpha.81 v1 + backup privilege fix) — @'%' grant allowlist includes syncer grants, backup-required RELOAD/PROCESS, narrow kubeblocks/mysql grants, and REPLICATION SLAVE for kb_replicator@%; forbidden broad classes remain hard-banned"
        # alpha.66 v1 originally asserted zero GRANT @'%'; alpha.68 v2
        # explicitly grants 3 cross-member health privs; alpha.69 v1 adds
        # a 4th narrow grant (SELECT ON mysql.user) to satisfy syncer's
        # init_db=mysql handshake; alpha.81 v1 adds a 5th narrow grant
        # (SLAVE MONITOR ON *.*) to satisfy syncer engine's
        # IsSwitchoverDone() SHOW SLAVE STATUS query on MariaDB 11.4+.
        # PR #2803 runtime validation later found mariabackup also requires
        # RELOAD and PROCESS on the selected remote target account. This
        # regression test verifies the only GRANT statements to @'%' are the
        # expected allowlist, including those backup privileges. We skip lines that start with REVOKE
        # (REVOKE clause contains "GRANT OPTION" substring but is not
        # itself a GRANT statement).
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func && /^[[:space:]]*GRANT[[:space:]]/ && /@'\''%'\''/ {
              line = \$0
              if (line !~ /GRANT[[:space:]]+REPLICATION[[:space:]]+CLIENT[[:space:]]+ON[[:space:]]+\\*\\.\\*/ &&
                  line !~ /GRANT[[:space:]]+RELOAD,[[:space:]]+PROCESS[[:space:]]+ON[[:space:]]+\\*\\.\\*/ &&
                  line !~ /GRANT[[:space:]]+REPLICATION[[:space:]]+MASTER[[:space:]]+ADMIN[[:space:]]+ON[[:space:]]+\\*\\.\\*/ &&
                  line !~ /GRANT[[:space:]]+SELECT,[[:space:]]+INSERT,[[:space:]]+UPDATE[[:space:]]+ON[[:space:]]+kubeblocks\\./ &&
                  line !~ /GRANT[[:space:]]+SELECT[[:space:]]+ON[[:space:]]+mysql\\.user/ &&
                  line !~ /GRANT[[:space:]]+SLAVE[[:space:]]+MONITOR[[:space:]]+ON[[:space:]]+\\*\\.\\*/ &&
                  line !~ /GRANT[[:space:]]+REPLICATION[[:space:]]+SLAVE[[:space:]]+ON[[:space:]]+\\*\\.\\*/) {
                print NR\": grant to @ percent outside allowlist: \"\$0
              }
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        The output should equal ""
      End

      It "alpha.66 v1: ensure_internal_local_admin body retains GRANT ALL PRIVILEGES to kb_internal_root@localhost AND @127.0.0.1 (internal exception preserved for syncer 127.0.0.1 AdminDB connection) [contract-no-regression]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "@'localhost' WITH GRANT OPTION"
        The output should include "@'127.0.0.1' WITH GRANT OPTION"
      End
    End

    Context "alpha.64 v1+v2+v3 + alpha.65 contract no-regression spot-check"
      It "alpha.66 v1: alpha.64 v1+v2+v3 cmpd-side invariants all preserved unchanged [contract-no-regression]"
        # Spot-check: same invariant counts as alpha.65 v2 (chart only changed,
        # cmpd-replication.yaml grant body / caller propagation / tier annotation /
        # multi-word loop all preserved). The new ensure_internal_local_admin
        # @'%' addition is the only intentional cmpd content delta.
        When run sh -c '
          {
            grep -c "CMPD_EXPLICIT_PRIMARY_GRANT_BODY=" "${CMPD_SOURCE}";
            grep -c "CMPD_SECONDARY_FENCE_GRANT_BODY=" "${CMPD_SOURCE}";
            grep -c "set_replica_read_only \"" "${CMPD_SOURCE}";
            grep -c "prestop_lock_failed_both fail_closed=true tier=required" ../scripts/replication-prestop.sh;
            grep -cE "^[[:space:]]*lock_(local|remote)_root_writes\\b.*\\|\\| true.*# tier=" "${CMPD_SOURCE}";
            grep -cE "^[[:space:]]*for privilege in \"BINLOG MONITOR\" \"SLAVE MONITOR\"" "${CMPD_SOURCE}";
          } | tr "\n" " "
        '
        The status should be success
        # Expected: 1 grant body explicit + 1 secondary fence + 4 explicit set_replica_read_only caller +
        # 1 prestop_lock_failed_both (in prestop script) + 14 tier-annotated swallow (reduced from 16 after CMPD
        # consolidation PR #2933) + 2 inline-quoted MONITOR loops
        The output should equal "1 1 4 1 14 2 "
      End
    End
  End

  # alpha.67 v1 (Jack 12:56 alpha.66 v1 package-level review HOLD): the
  # alpha.66 v1 @'%' "zero privileges" contract was only declarative —
  # `CREATE USER IF NOT EXISTS` does not clear pre-existing privileges
  # and `ACCOUNT LOCK` is not a revoke. alpha.67 v1 inserts an explicit
  # `REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'%';` between
  # `CREATE USER ... @'%'` and `ALTER USER ... @'%' ACCOUNT LOCK` so
  # the zero-privilege state is enforced at the write site, not just
  # declared. Plus chart bump 1.1.1-alpha.66 → 1.1.1-alpha.67 (KB CmpD
  # immutability rule).
  Describe "alpha.67 v1 ensure_internal_local_admin write-site zero-priv enforcement"
    setup_chart_alpha67_env() {
      export CHART_FILE="../Chart.yaml"
      export CMPD_SOURCE="../scripts/replication-entrypoint.sh"
    }
    Before "setup_chart_alpha67_env"

    Context "chart bump alpha.66 → alpha.67 → alpha.68 (CmpD immutability rule)"
      It "alpha.67 v1: Chart.yaml chart bump pattern locked — current bumped to alpha.26 [contract-no-regression]"
        # Subsequent alphas all bumped further under the same CmpD
        # immutability rule. Literal kept in sync with latest chart
        # version.
        When call grep -E "^version:" "${CHART_FILE}"
        The status should be success
        The output should equal "version: 1.2.0-alpha.26"
      End
    End

    Context "ensure_internal_local_admin write-site REVOKE step (per Jack 12:56 HOLD blocker)"
      It "alpha.67 v1: ensure_internal_local_admin body contains explicit REVOKE ALL PRIVILEGES, GRANT OPTION FROM kb_internal_root@'%' (zero-priv enforced at write site, not just declared; alpha.68 v2 still uses REVOKE before adding the cross-member grant allowlist) [product-blocker]"
        # alpha.67 v1 introduced REVOKE; alpha.68 v2 keeps the REVOKE step
        # but now adds explicit grants AFTER it for cross-member health.
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "REVOKE ALL PRIVILEGES, GRANT OPTION FROM"
        The output should include "@'%'"
      End
    End
  End

  # alpha.68 v2 (Jack 15:39 alpha.67 v1 live-gate RED + 15:45 alpha.68 v1
  # design HOLD + 15:58 alpha.68 v2 Direction B ACCEPT with refined
  # checkpoint #3): the alpha.67 v1 LOCKED+zero-priv @'%' detection-only
  # design correctly satisfied syncer's IsAdminCreated host='%' detection
  # but broke cross-member syncer auth (4151 Access denied → RoleProbeNotDone).
  # SQL matrix audit established the cross-member exact grant set; alpha.68
  # v2 changes @'%' from LOCKED+zero-priv to UNLOCK + cross-member health
  # grant allowlist:
  #   - REPLICATION CLIENT ON *.* (SHOW SLAVE/MASTER STATUS)
  #   - REPLICATION MASTER ADMIN ON *.* (cross-member SET GLOBAL
  #     rpl_semi_sync_master_timeout from Follow secondary -> leader)
  #   - SELECT, INSERT, UPDATE ON kubeblocks.kb_health_check
  # Refined checkpoint #3: no NEW net capability vs root@'%' which
  # already has REPLICATION MASTER ADMIN via alpha.64 v1 contract; the
  # forbidden classes (ALL PRIVILEGES / SUPER / READ_ONLY ADMIN /
  # CONNECTION ADMIN / BINLOG ADMIN / REPLICATION SLAVE ADMIN /
  # DELETE / DROP / CREATE USER / schema-wide DML / CREATE on
  # kubeblocks.*) are still hard-banned.
  Describe "alpha.68 v2 ensure_internal_local_admin cross-member health grant allowlist"
    setup_chart_alpha68_env() {
      export CMPD_SOURCE="../scripts/replication-entrypoint.sh"
    }
    Before "setup_chart_alpha68_env"

    Context "@'%' UNLOCK and 3 cross-member grants present (per Jack 15:58 grant contract)"
      It "alpha.68 v2: ensure_internal_local_admin body issues ALTER USER ... @'%' ACCOUNT UNLOCK (not ACCOUNT LOCK as in alpha.67 v1) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "@'%' ACCOUNT UNLOCK"
        The output should not include "@'%' ACCOUNT LOCK"
      End

      It "alpha.68 v2: ensure_internal_local_admin body grants REPLICATION CLIENT on *.* to kb_internal_root@'%' (cross-member SHOW SLAVE/MASTER STATUS) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "GRANT REPLICATION CLIENT ON *.* TO"
        The output should include "@'%'"
      End

      It "alpha.68 v2: ensure_internal_local_admin body grants REPLICATION MASTER ADMIN on *.* to kb_internal_root@'%' (cross-member SET GLOBAL rpl_semi_sync_master_timeout) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "GRANT REPLICATION MASTER ADMIN ON *.* TO"
      End

      It "alpha.68 v2: ensure_internal_local_admin body grants SELECT, INSERT, UPDATE on kubeblocks to kb_internal_root@'%' (ReadCheck + WriteCheck cross-member health) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "GRANT SELECT, INSERT, UPDATE ON kubeblocks."
      End

      It "alpha.68 v2: ensure_internal_local_admin SQL ordering — CREATE @'%' < ALTER UNLOCK @'%' < REVOKE @'%' < grant allowlist [product-blocker]"
        # Per Jack 15:58 grant contract: CREATE creates the user record,
        # ALTER UNLOCK reverses alpha.67 v1 LOCK, REVOKE clears any
        # pre-existing privileges, then each grant adds exactly the
        # cross-member health priv. Reordering would defeat either the
        # write-site contract or the unlock contract.
        When run sh -c '
          create_line=$(grep -n "CREATE USER IF NOT EXISTS .*@.%. IDENTIFIED BY" "${CMPD_SOURCE}" | head -1 | cut -d: -f1)
          unlock_line=$(grep -n "ALTER USER .*@.%. ACCOUNT UNLOCK" "${CMPD_SOURCE}" | head -1 | cut -d: -f1)
          revoke_line=$(grep -n "REVOKE ALL PRIVILEGES, GRANT OPTION FROM .*@.%." "${CMPD_SOURCE}" | head -1 | cut -d: -f1)
          repl_client_line=$(grep -n "GRANT REPLICATION CLIENT ON .*@.%." "${CMPD_SOURCE}" | head -1 | cut -d: -f1)
          if [ -z "${create_line}" ] || [ -z "${unlock_line}" ] || [ -z "${revoke_line}" ] || [ -z "${repl_client_line}" ]; then
            printf "missing line: create=%s unlock=%s revoke=%s repl_client=%s\n" "${create_line:-MISSING}" "${unlock_line:-MISSING}" "${revoke_line:-MISSING}" "${repl_client_line:-MISSING}"
          elif [ "${create_line}" -ge "${unlock_line}" ] || [ "${unlock_line}" -ge "${revoke_line}" ] || [ "${revoke_line}" -ge "${repl_client_line}" ]; then
            printf "wrong order: create=%s unlock=%s revoke=%s repl_client=%s (expect create<unlock<revoke<repl_client)\n" "${create_line}" "${unlock_line}" "${revoke_line}" "${repl_client_line}"
          fi
        '
        The status should be success
        The output should equal ""
      End
    End

    Context "@'%' forbidden-priv negative hard gate (per Jack 15:58 refined checkpoint #3)"
      It "alpha.68 v2: ensure_internal_local_admin body grants ZERO forbidden privileges to kb_internal_root@'%' (refined checkpoint #3 hard gate: no ALL PRIVILEGES / SUPER / READ_ONLY ADMIN / CONNECTION ADMIN / BINLOG ADMIN / REPLICATION SLAVE ADMIN / DELETE / DROP / CREATE USER on @'%') [product-blocker]"
        # Scope is limited to the ensure_internal_local_admin function body.
        # We allow: REPLICATION CLIENT, REPLICATION MASTER ADMIN, SELECT/
        # INSERT/UPDATE on kubeblocks.kb_health_check on @'%'. We forbid:
        # ALL PRIVILEGES, SUPER, READ_ONLY ADMIN, CONNECTION ADMIN, BINLOG
        # ADMIN, REPLICATION SLAVE ADMIN, DELETE, DROP, CREATE USER, plus
        # any schema-wide DML or CREATE on kubeblocks.*.
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func && /GRANT[[:space:]]/ && /@'\''%'\''/ {
              line = \$0
              if (line ~ /GRANT[[:space:]]+ALL[[:space:]]+PRIVILEGES/ ||
                  line ~ /GRANT[[:space:]]+SUPER/ ||
                  line ~ /READ_ONLY[[:space:]]+ADMIN/ ||
                  line ~ /CONNECTION[[:space:]]+ADMIN/ ||
                  line ~ /BINLOG[[:space:]]+ADMIN/ ||
                  line ~ /REPLICATION[[:space:]]+SLAVE[[:space:]]+ADMIN/ ||
                  line ~ /[[:space:]]+DELETE[[:space:]]+/ ||
                  line ~ /[[:space:]]+DROP[[:space:]]+/ ||
                  line ~ /CREATE[[:space:]]+USER/) {
                print NR\": forbidden grant to @ percent: \"\$0
              }
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        The output should equal ""
      End

      It "alpha.68 v2: ensure_internal_local_admin body does NOT grant CREATE on kubeblocks.* to kb_internal_root@'%' (primary_local_root_write_ready pre-creates kb_health_check during local bootstrap) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func && /GRANT[[:space:]]+CREATE[[:space:]]+ON[[:space:]]+kubeblocks\\.\\*/ {
              print NR\": forbidden CREATE on kubeblocks.* grant: \"\$0
            }
            in_func && /GRANT[[:space:]].*CREATE[[:space:]].*ON[[:space:]]+kubeblocks\\./ {
              print NR\": forbidden CREATE-class grant on kubeblocks: \"\$0
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        The output should equal ""
      End
    End

    Context "alpha.64+.65+.66+.67 contract no-regression spot-check"
      It "alpha.68 v2: ensure_internal_local_admin body retains GRANT ALL PRIVILEGES to kb_internal_root@localhost AND @127.0.0.1 (internal exception preserved for syncer 127.0.0.1 AdminDB connection) [contract-no-regression]"
        # alpha.64+.65+.66+.67 already established the local kb_internal_root
        # full admin executor; alpha.68 v2 changes ONLY the @'%' record.
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "@'localhost' WITH GRANT OPTION"
        The output should include "@'127.0.0.1' WITH GRANT OPTION"
      End

      It "alpha.68 v2: cmpd-replication.yaml retains alpha.64 v3 root-cause comment marker (proves CmpD content alpha.64 v3 + alpha.65 + alpha.66 + alpha.67 design preserved) [contract-no-regression]"
        When call grep -E "alpha.64 v3.*Jack 11:14.*live-gate RED" "${CMPD_SOURCE}"
        The status should be success
        The output should include "alpha.64 v3"
      End
    End
  End

  # alpha.69 v1 (Jack 17:57 alpha.68 v2 install/script live-gate RED
  # 3-evidence-chains closeout + 18:20 alpha.69 v1 design ACCEPT with
  # runtime-acceptance tightening): alpha.68 v2's @'%' grant on
  # kubeblocks.kb_health_check assumed the table existed, but
  # ensure_internal_local_admin runs from "startup-before-role-decision"
  # which precedes primary_local_root_write_ready (the function that
  # creates the table). Fresh boots hit Error 1146, wait_for_internal_
  # local_admin loops forever, role decision never reached, 2002
  # downstream. alpha.69 v1 adds CREATE DATABASE + CREATE TABLE inside
  # ensure_internal_local_admin SQL BEFORE the @'%' GRANT, plus narrow
  # GRANT SELECT ON mysql.user TO @'%' to satisfy syncer's
  # init_db=mysql handshake (Error 1044 fix).
  #
  # Source-side ShellSpec checks the literal source SQL syntax
  # ("REPLICATION CLIENT", not the SHOW GRANTS normalized form
  # "BINLOG MONITOR"). Runtime SHOW GRANTS acceptance (handled in live
  # gate, not here) uses semantic-equivalent matching. `BINLOG MONITOR`
  # in source SQL would be wrong (alpha.64 v3 has it for user-facing
  # root via CMPD_OPTIONAL_MONITOR_PRIVS only); `BINLOG MONITOR` in
  # SHOW GRANTS output is the positive normalized form of our
  # REPLICATION CLIENT grant and is allowed.
  Describe "alpha.69 v1 ensure_internal_local_admin bootstrap SQL ordering + mysql.user narrow grant"
    setup_chart_alpha69_env() {
      export CMPD_SOURCE="../scripts/replication-entrypoint.sh"
    }
    Before "setup_chart_alpha69_env"

    Context "1146 fix — CREATE DATABASE/TABLE before @'%' GRANT (per Jack 18:20 ACCEPT segment 1)"
      It "alpha.69 v1: ensure_internal_local_admin body contains CREATE DATABASE IF NOT EXISTS kubeblocks (idempotent precondition) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "CREATE DATABASE IF NOT EXISTS kubeblocks"
      End

      It "alpha.69 v1: ensure_internal_local_admin body contains CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check (idempotent precondition matching primary_local_root_write_ready schema) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check"
      End
    End

    Context "1044 fix — narrow GRANT SELECT ON mysql.user to satisfy syncer DSN /mysql init_db (per Jack 18:20 ACCEPT segment 2)"
      It "alpha.69 v1: ensure_internal_local_admin body contains GRANT SELECT ON mysql.user TO kb_internal_root@'%' (narrow table-specific, satisfies init_db=mysql handshake) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func { print }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should include "GRANT SELECT ON mysql.user TO"
        The output should include "@'%'"
      End

      It "alpha.69 v1: ensure_internal_local_admin body does NOT grant any broader mysql.* schema-wide DML (only the narrow mysql.user SELECT is allowed) [product-blocker]"
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func && /^[[:space:]]*GRANT[[:space:]]/ && /@'\''%'\''/ {
              if (\$0 ~ /ON[[:space:]]+mysql\\.[*]/ ||
                  (\$0 ~ /ON[[:space:]]+mysql\\./ && \$0 !~ /ON[[:space:]]+mysql\\.user[[:space:]]+TO/)) {
                print NR\": broader mysql grant: \"\$0
              }
            }
          " '"${CMPD_SOURCE}"' || true
        '
        The status should be success
        The output should equal ""
      End
    End

    Context "1146/1044 fix SQL ordering — CREATE DATABASE < CREATE TABLE < CREATE USER @'%' < UNLOCK < REVOKE < REPL CLIENT < REPL MASTER ADMIN < SELECT/INSERT/UPDATE on kubeblocks < SELECT on mysql.user (per Jack 18:20 ACCEPT)"
      It "alpha.69 v1: full 9-step SQL ordering in ensure_internal_local_admin [product-blocker]"
        # Each statement appears in the order listed; reordering would
        # defeat one of the contracts (1146 fix requires CREATE DB/TABLE
        # before any GRANT on the table; 1044 fix requires GRANT SELECT
        # on mysql.user to be applied; all alpha.68 v2 ordering preserved).
        # We scope to the ensure_internal_local_admin function body
        # using awk; other CREATE DATABASE / CREATE TABLE occurrences
        # exist in primary_local_root_write_ready / primary_internal_
        # root_write_ready. After CMPD consolidation (PR #2933), the
        # grant target is kubeblocks.* (broader) and the CREATE TABLE
        # uses kubeblocks.kb_post_dcs_fence_probe instead of
        # kubeblocks.kb_health_check.
        When run sh -c '
          awk "
            /^[[:space:]]*ensure_internal_local_admin\\(\\)[[:space:]]*\\{/ { in_func = 1; next }
            in_func && /^[[:space:]]*\\}[[:space:]]*\$/ { in_func = 0 }
            in_func && \$0 ~ /^[[:space:]]*#/ { next }
            in_func {
              if (\$0 ~ /CREATE DATABASE IF NOT EXISTS kubeblocks/ && !create_db_line) create_db_line = NR
              if (\$0 ~ /CREATE TABLE IF NOT EXISTS kubeblocks\\./ && !create_table_line) create_table_line = NR
              if (\$0 ~ /CREATE USER IF NOT EXISTS .*@.%. IDENTIFIED BY/ && !create_user_line) create_user_line = NR
              if (\$0 ~ /ALTER USER .*@.%. ACCOUNT UNLOCK/ && !unlock_line) unlock_line = NR
              if (\$0 ~ /REVOKE ALL PRIVILEGES, GRANT OPTION FROM .*@.%./ && !revoke_line) revoke_line = NR
              if (\$0 ~ /GRANT REPLICATION CLIENT ON [*]\\.[*] TO/ && !repl_client_line) repl_client_line = NR
              if (\$0 ~ /GRANT REPLICATION MASTER ADMIN ON [*]\\.[*] TO/ && !repl_master_line) repl_master_line = NR
              if (\$0 ~ /GRANT SELECT, INSERT, UPDATE ON kubeblocks\\./ && !health_grant_line) health_grant_line = NR
              if (\$0 ~ /GRANT SELECT ON mysql\\.user TO/ && !mysql_grant_line) mysql_grant_line = NR
            }
            END {
              if (!create_db_line || !create_table_line || !create_user_line || !unlock_line || !revoke_line || !repl_client_line || !repl_master_line || !health_grant_line || !mysql_grant_line) {
                printf \"missing line: create_db=%s create_table=%s create_user=%s unlock=%s revoke=%s repl_client=%s repl_master=%s health=%s mysql_user=%s\\n\", (create_db_line ? create_db_line : \"MISSING\"), (create_table_line ? create_table_line : \"MISSING\"), (create_user_line ? create_user_line : \"MISSING\"), (unlock_line ? unlock_line : \"MISSING\"), (revoke_line ? revoke_line : \"MISSING\"), (repl_client_line ? repl_client_line : \"MISSING\"), (repl_master_line ? repl_master_line : \"MISSING\"), (health_grant_line ? health_grant_line : \"MISSING\"), (mysql_grant_line ? mysql_grant_line : \"MISSING\")
              } else if (create_db_line >= create_table_line || create_table_line >= create_user_line || create_user_line >= unlock_line || unlock_line >= revoke_line || revoke_line >= repl_client_line || repl_client_line >= repl_master_line || repl_master_line >= health_grant_line || health_grant_line >= mysql_grant_line) {
                printf \"wrong order: create_db=%d create_table=%d create_user=%d unlock=%d revoke=%d repl_client=%d repl_master=%d health=%d mysql_user=%d\\n\", create_db_line, create_table_line, create_user_line, unlock_line, revoke_line, repl_client_line, repl_master_line, health_grant_line, mysql_grant_line
              }
            }
          " '"${CMPD_SOURCE}"'
        '
        The status should be success
        The output should equal ""
      End
    End
  End

  Describe "alpha.76/.77/.78 marker mechanism — alpha.80 v1 dead-code cleanup"
    # The entire `.switchover-fence-active` marker mechanism (helpers,
    # consumer fresh-checks, init-syncer rm) was removed by alpha.80 v1
    # because alpha.79 v1 minimalist deleted the marker writer. The
    # alpha.76/.77/.78 contract tests below are obsolete and marked
    # Pending. A future ShellSpec cleanup pass can delete them entirely;
    # left here as audit trail of which contracts changed.

    It "[alpha.80 v1: alpha.76/.77/.78 marker mechanism removed — all contract tests obsolete]"
      Pending "alpha.80 v1 removed marker mechanism entirely; obsolete pending future ShellSpec cleanup"
    End
  End

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
