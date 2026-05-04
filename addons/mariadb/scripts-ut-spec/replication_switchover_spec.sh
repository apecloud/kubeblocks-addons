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
    unset MARIADB_DATADIR DATA_DIR SYNCERCTL_BIN SYNCERCTL_ARGS MARIADB_CLIENT_BIN
    unset CLUSTER_NAME COMPONENT_NAME CLUSTER_NAMESPACE
    unset KB_SWITCHOVER_ROLE KB_SWITCHOVER_CURRENT_NAME KB_SWITCHOVER_CANDIDATE_NAME
    unset SWITCHOVER_WAIT_SECONDS SWITCHOVER_STABILIZATION_SECONDS SWITCHOVER_POLL_SECONDS
  }
  AfterEach "cleanup"

  Include ../scripts/replication-switchover.sh

  make_syncerctl() {
    cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
printf "%s" "$*" > "${SYNCERCTL_ARGS}"
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
        query_value() {
          case "$1:$2" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@server_id;"*) echo "2" ;;
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@global.read_only;"*) echo "0" ;;
            "mdb-mariadb.demo.svc.cluster.local:SELECT @@server_id;"*) echo "" ;;
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
        The output should include "Switchover service-route diagnostic: candidate=mdb-mariadb-1"
        The output should include "route_status=pending"
        The output should include "Switchover done"
      End

      It "passes pod names to syncerctl instead of candidate FQDN"
        make_syncerctl
        query_value() {
          case "$1:$2" in
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@server_id;"*) echo "2" ;;
            "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local:SELECT @@global.read_only;"*) echo "0" ;;
            "mdb-mariadb.demo.svc.cluster.local:SELECT @@server_id;"*) echo "" ;;
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

      It "falls back to syncer roles when mariadb client is unavailable"
        make_role_syncerctl
        rm -f "${MARIADB_CLIENT_BIN}"
        query_server_id() {
          echo "2"
        }
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be success
        The output should include "Switchover done"
      End
    End

    Context "when syncerctl cannot create DCS switchover"
      It "returns failure"
        make_failing_syncerctl
        When call run_switchover "mdb-mariadb-1" "mdb-mariadb-1.mdb-mariadb-headless.demo.svc.cluster.local"
        The status should be failure
        The output should include "Switchover: creating syncer DCS switchover"
        The stderr should include "Switchover failed: syncerctl could not create DCS switchover"
      End
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
