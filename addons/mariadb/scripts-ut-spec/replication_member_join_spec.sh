# shellcheck shell=sh
# Unit tests for replication-member-join.sh
# Tests primary detection guard, slave running check, and GTID alignment logic.
# The mariadb binary is mocked via local_sql/primary_sql function overrides.

Describe "replication-member-join.sh"
  setup() {
    TEST_DIR=$(mktemp -d)
    export MARIADB_DATADIR="$TEST_DIR"
    export DATA_DIR="$TEST_DIR"
    export CLUSTER_NAME="mdb"
    export COMPONENT_NAME="mariadb"
    export CLUSTER_NAMESPACE="demo"
    export MARIADB_ROOT_USER="root"
    export MARIADB_ROOT_PASSWORD="secret"
    export MARIADB_CLI="mariadb"
    export PRIMARY_HOST="mdb-mariadb.demo.svc.cluster.local"
    export PRIMARY_SAMPLE_SLEEP_SECONDS=0
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    unset MARIADB_DATADIR DATA_DIR PRIMARY_HOST
    unset MARIADB_CLI
    unset PRIMARY_SAMPLE_RETRIES PRIMARY_SAMPLE_SLEEP_SECONDS
    unset MYSQL_CLIENT_DIR
    unset CLUSTER_NAME COMPONENT_NAME CLUSTER_NAMESPACE
    unset MARIADB_ROOT_USER MARIADB_ROOT_PASSWORD
  }
  AfterEach "cleanup"

  Include ../scripts/replication-member-join.sh

  Describe "is_self_primary()"
    Context "when primary service routes to this pod (same server_id)"
      It "returns success (we are the primary)"
        local_sql()   { echo "100"; }
        primary_sql() { echo "100"; }
        When call is_self_primary
        The status should be success
      End
    End

    Context "when primary service routes to a different pod"
      It "returns failure (we are not the primary)"
        local_sql()   { echo "101"; }
        primary_sql() { echo "100"; }
        When call is_self_primary
        The status should be failure
      End
    End

    Context "when primary_sql returns empty (primary unreachable)"
      It "returns failure (empty primary_sid → not self)"
        local_sql()   { echo "101"; }
        primary_sql() { echo ""; }
        When call is_self_primary
        The status should be failure
      End
    End
  End

  Describe "is_slave_running()"
    Context "when SHOW SLAVE STATUS returns empty (not configured)"
      It "returns failure (not configured)"
        local_sql() {
          case "$*" in
            *"SHOW SLAVE STATUS"*) echo "" ;;
          esac
        }
        When call is_slave_running
        The status should be failure
      End
    End

    Context "when slave is configured and IO thread is running"
      It "returns success"
        local_sql() {
          case "$*" in
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *"Slave_running"*)     echo "Slave_running	ON" ;;
          esac
        }
        When call is_slave_running
        The status should be success
      End
    End

    Context "when slave is configured but IO thread is stopped"
      It "returns failure (needs reconfiguration)"
        local_sql() {
          case "$*" in
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *"Slave_running"*)     echo "Slave_running	OFF" ;;
          esac
        }
        When call is_slave_running
        The status should be failure
      End
    End
  End

  Describe "sample_primary_for_divergence()"
    It "queries primary sample as tabular columns and stores parsed fields separately"
      PRIMARY_SAMPLE_RETRIES=1
      ACTIVE_PRIMARY_HOST="mdb-mariadb.demo.svc.cluster.local"
      host_sql() {
        case "$*" in
          *"SELECT @@server_id, @@hostname, @@global.read_only, @@global.gtid_binlog_state;"*) ;;
          *) return 1 ;;
        esac
        printf '2\tmdb-mariadb-1\t0\t0-1-8550,0-2-8689\n'
      }
      When call sample_primary_for_divergence
      The status should be success
      The variable PRIMARY_SAMPLE_SERVER_ID should eq "2"
      The variable PRIMARY_SAMPLE_RESOLVED_ENDPOINT should eq "mdb-mariadb-1"
      The variable PRIMARY_SAMPLE_READ_ONLY should eq "0"
      The variable PRIMARY_SAMPLE_GTID should eq "0-1-8550,0-2-8689"
      The variable PRIMARY_SAMPLE_LOG should include "attempt=1 host=mdb-mariadb.demo.svc.cluster.local server_id=2 resolved_endpoint=mdb-mariadb-1 read_only=0 gtid=0-1-8550,0-2-8689"
    End

    It "accepts monotonic GTID advancement from the same primary identity"
      PRIMARY_SAMPLE_RETRIES=2
      ACTIVE_PRIMARY_HOST="mdb-mariadb.demo.svc.cluster.local"
      echo 0 > "${TEST_DIR}/sample-count"
      host_sql() {
        case "$*" in
          *"SELECT @@server_id, @@hostname, @@global.read_only, @@global.gtid_binlog_state;"*) ;;
          *) return 1 ;;
        esac
        sample_count=$(cat "${TEST_DIR}/sample-count")
        sample_count=$((sample_count + 1))
        echo "${sample_count}" > "${TEST_DIR}/sample-count"
        if [ "$sample_count" -eq 1 ]; then
          printf '2\tmdb-mariadb-1\t0\t0-1-8550,0-2-8689\n'
        else
          printf '2\tmdb-mariadb-1\t0\t0-1-8553,0-2-8690\n'
        fi
      }
      When call sample_primary_for_divergence
      The status should be success
      The variable PRIMARY_SAMPLE_STABLE should eq "true"
      The variable PRIMARY_SAMPLE_GTID should eq "0-1-8553,0-2-8690"
      The variable PRIMARY_SAMPLE_LOG should include "attempt=2 host=mdb-mariadb.demo.svc.cluster.local server_id=2 resolved_endpoint=mdb-mariadb-1 read_only=0 gtid=0-1-8553,0-2-8690"
    End
  End

  Describe "setup_replication()"
    Context "when pod has empty gtid_slave_pos (fresh pod)"
      It "does NOT set gtid_slave_pos (fresh pod replicates from binlog start)"
        GTID_SET_CALLED=""
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-100" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_slave_pos;"*)  echo "" ;;
            *"gtid_slave_pos='"*) GTID_SET_CALLED="yes" ;;
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *) : ;;
          esac
        }
        query_slave_status_verbose() {
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
EOF
        }
        touch "${TEST_DIR}/.replication-pending"
        When call setup_replication
        The variable GTID_SET_CALLED should eq ""
        The output should include "Replication started"
      End

      It "removes the .replication-pending flag"
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-100" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *) : ;;
          esac
        }
        query_slave_status_verbose() {
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
EOF
        }
        touch "${TEST_DIR}/.replication-pending"
        When call setup_replication
        The path "${TEST_DIR}/.replication-pending" should not be exist
        The output should include "Replication started"
      End

      It "clears any stale divergence marker on successful replication setup"
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-100" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *) : ;;
          esac
        }
        query_slave_status_verbose() {
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
EOF
        }
        touch "${TEST_DIR}/.replication-pending" "${TEST_DIR}/.replication-divergence-pending"
        When call setup_replication
        The path "${TEST_DIR}/.replication-divergence-pending" should not be exist
        The output should include "Replication started"
      End
    End

    Context "when pod has existing gtid_slave_pos (rejoining pod)"
      It "keeps the local gtid_slave_pos and does not align to primary"
        GTID_SET_CALLED=""
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-200" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_slave_pos;"*) echo "0-1-150" ;;
            *"gtid_slave_pos='"*) GTID_SET_CALLED="yes" ;;
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *) : ;;
          esac
        }
        query_slave_status_verbose() {
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
EOF
        }
        When call setup_replication
        The variable GTID_SET_CALLED should eq ""
        The output should include "Replication started"
      End
    End

    Context "when strict mode is ON and existing datadir has diverged GTID lineage"
      It "fails closed and keeps replication pending"
        CHANGE_MASTER_CALLED=""
        mkdir -p "${TEST_DIR}/mysql"
        touch "${TEST_DIR}/.replication-ready" "${TEST_DIR}/.replication-pending"
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*)   echo "0-2-8689" ;;
          esac
        }
        host_sql() {
          case "$*" in
            *"@"*) echo "2	mdb-mariadb-1	0	0-1-8550,0-2-8689" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_strict_mode"*)  echo "ON" ;;
            *"gtid_binlog_state"*) echo "0-1-8551" ;;
            *"gtid_slave_pos;"*)   echo "0-1-8283" ;;
            *"CHANGE MASTER TO"*)  CHANGE_MASTER_CALLED="yes" ;;
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *) : ;;
          esac
        }
        When call setup_replication
        The status should be failure
        The variable CHANGE_MASTER_CALLED should eq ""
        The path "${TEST_DIR}/.replication-pending" should be exist
        The path "${TEST_DIR}/.replication-divergence-pending" should be exist
        The output should include "GTID divergence detected"
      End

      It "persists divergence decision evidence for later proof collection"
        mkdir -p "${TEST_DIR}/mysql"
        export POD_NAME="mdb-mariadb-0"
        ACTIVE_PRIMARY_HOST="${PRIMARY_HOST}"
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*)   echo "0-2-8689" ;;
          esac
        }
        host_sql() {
          case "$*" in
            *"@"*) echo "2	mdb-mariadb-1	0	0-1-8550,0-2-8689" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_strict_mode"*)  echo "ON" ;;
            *"gtid_binlog_state"*) echo "0-1-8551" ;;
            *"gtid_slave_pos;"*)   echo "0-1-8283" ;;
            *"SHOW SLAVE STATUS"*) echo "Master_Host	primary	Slave_IO_Running	No" ;;
            *) : ;;
          esac
        }
        When call setup_replication
        The status should be failure
        The output should include "GTID divergence detected"
        The file "${TEST_DIR}/log/replication-divergence.log" should be file
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "branch=fail_closed_for_gtid_divergence"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "pod_name=mdb-mariadb-0"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "active_primary_host=mdb-mariadb.demo.svc.cluster.local"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "primary_sample_stable=true"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "primary_resolved_endpoint=mdb-mariadb-1"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "primary_server_id=2"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "attempt=1 host=mdb-mariadb.demo.svc.cluster.local server_id=2 resolved_endpoint=mdb-mariadb-1 read_only=0 gtid=0-1-8550,0-2-8689"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "local_gtid_binlog_state=0-1-8551"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "primary_gtid_binlog_state=0-1-8550,0-2-8689"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "slave_status_begin"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "Master_Host	primary	Slave_IO_Running	No"
        The contents of file "${TEST_DIR}/.replication-divergence-pending" should include "branch=fail_closed_for_gtid_divergence"
        The contents of file "${TEST_DIR}/.replication-divergence-pending" should include "primary_resolved_endpoint=mdb-mariadb-1"
        The contents of file "${TEST_DIR}/.replication-divergence-pending" should include "primary_gtid_binlog_state=0-1-8550,0-2-8689"
      End

      It "does not fail closed when primary sampling is unstable across retries"
        mkdir -p "${TEST_DIR}/mysql"
        export POD_NAME="mdb-mariadb-0"
        ACTIVE_PRIMARY_HOST="${PRIMARY_HOST}"
        echo 0 > "${TEST_DIR}/sample-count"
        host_sql() {
          case "$*" in
            *"@"*)
              sample_count=$(cat "${TEST_DIR}/sample-count")
              sample_count=$((sample_count + 1))
              echo "${sample_count}" > "${TEST_DIR}/sample-count"
              if [ "$sample_count" -eq 1 ]; then
                echo "2	mdb-mariadb-1	0	0-1-8550,0-2-8689"
              else
                echo "1	mdb-mariadb-0	0	0-1-8551"
              fi
              ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_strict_mode"*)  echo "ON" ;;
            *"gtid_binlog_state"*) echo "0-1-8551" ;;
            *"SHOW SLAVE STATUS"*) echo "Master_Host	primary	Slave_IO_Running	Yes" ;;
            *) : ;;
          esac
        }
        When call fail_closed_for_gtid_divergence
        The status should be failure
        The path "${TEST_DIR}/.replication-divergence-pending" should not be exist
        The file "${TEST_DIR}/log/replication-divergence.log" should be file
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "decision=sampling-instability"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "attempt=1 host=mdb-mariadb.demo.svc.cluster.local server_id=2 resolved_endpoint=mdb-mariadb-1 read_only=0 gtid=0-1-8550,0-2-8689"
        The contents of file "${TEST_DIR}/log/replication-divergence.log" should include "attempt=2 host=mdb-mariadb.demo.svc.cluster.local server_id=1 resolved_endpoint=mdb-mariadb-0 read_only=0 gtid=0-1-8551"
      End
    End

    Context "when rejoin hits GTID 1950 before primary truth stabilizes"
      It "keeps replication pending for retry instead of latching divergence"
        mkdir -p "${TEST_DIR}/mysql"
        export POD_NAME="mdb-mariadb-1"
        ACTIVE_PRIMARY_HOST="${PRIMARY_HOST}"
        echo 0 > "${TEST_DIR}/sample-count"
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-900" ;;
          esac
        }
        host_sql() {
          case "$*" in
            *"SELECT @@server_id, @@hostname, @@global.read_only, @@global.gtid_binlog_state;"*)
              sample_count=$(cat "${TEST_DIR}/sample-count")
              sample_count=$((sample_count + 1))
              echo "${sample_count}" > "${TEST_DIR}/sample-count"
              if [ "$sample_count" -le 3 ]; then
                echo "2	mdb-mariadb-0	0	0-1-899,0-2-469"
              elif [ "$sample_count" -eq 4 ]; then
                echo "2	mdb-mariadb-0	0	0-1-900,0-2-469"
              else
                echo "1	mdb-mariadb-1	0	0-1-900"
              fi
              ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_strict_mode"*)  echo "ON" ;;
            *"gtid_binlog_state"*) echo "0-1-382,0-2-469" ;;
            *"gtid_slave_pos;"*)   echo "0-1-300" ;;
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *) : ;;
          esac
        }
        query_slave_status_verbose() {
          cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 1950
Last_SQL_Error: An attempt was made to binlog GTID 0-1-470 which would create an out-of-order sequence number with existing GTID 0-2-470, and gtid strict mode is enabled
EOF
        }
        touch "${TEST_DIR}/.replication-pending"
        When call setup_replication
        The status should be failure
        The path "${TEST_DIR}/.replication-pending" should be exist
        The path "${TEST_DIR}/.replication-divergence-pending" should not be exist
        The output should include "GTID out-of-order (1950) before primary truth stabilized"
      End
    End
  End

  Describe "main() self-primary guard"
    Context "when this pod is the primary"
      It "skips replication setup and exits 0"
        local_sql()         { echo "100"; }
        primary_sql()       { echo "100"; }
        wait_for_primary()  { return 0; }
        When call main
        The status should be success
        The output should include "Already primary"
      End
    End

    Context "when slave is already running"
      It "skips reconfiguration and exits 0"
        local_sql() {
          case "$*" in
            *"server_id"*)         echo "101" ;;
            *"SHOW SLAVE STATUS"*) echo "some-row" ;;
            *"Slave_running"*)     echo "Slave_running	ON" ;;
          esac
        }
        primary_sql()      { echo "100"; }
        wait_for_primary() { return 0; }
        When call main
        The status should be success
        The output should include "Nothing to do"
      End
    End

    Context "when PRIMARY_HOST is unreachable but slave is already running"
      It "returns success without waiting for PRIMARY_HOST"
        local_sql() {
          case "$*" in
            *"SHOW SLAVE STATUS"*) echo "some-row" ;;
            *"Slave_running"*)     printf 'Slave_running\tON\n' ;;
          esac
        }
        wait_for_primary() { echo "should-not-be-called"; return 1; }
        When call main
        The status should be success
        The output should include "Nothing to do"
        The output should not include "should-not-be-called"
      End
    End
  End

  Describe "PRIMARY_HOST default contract"
    Context "when CLUSTER_DOMAIN is overridden"
      It "builds PRIMARY_HOST from CLUSTER_DOMAIN"
        When run sh -c '
          unset PRIMARY_HOST
          export CLUSTER_NAME="mdb"
          export COMPONENT_NAME="mariadb"
          export CLUSTER_NAMESPACE="demo"
          export CLUSTER_DOMAIN="custom.local"
          export __SOURCED__=1
          . ../scripts/replication-member-join.sh
          printf "%s" "$PRIMARY_HOST"
        '
        The status should be success
        The output should eq "mdb-mariadb.demo.svc.custom.local"
      End
    End
  End

  Describe "resolve_mariadb_cli()"
    Context "when mariadb is not in PATH but MYSQL_CLIENT_DIR/bin/mariadb exists"
      It "falls back to the copied client under /tools"
        mkdir -p "${TEST_DIR}/mysql-client/bin" "${TEST_DIR}/empty-path"
        touch "${TEST_DIR}/mysql-client/bin/mariadb"
        chmod +x "${TEST_DIR}/mysql-client/bin/mariadb"
        When run sh -c "
          PATH='${TEST_DIR}/empty-path'
          unset MARIADB_CLI
          export MYSQL_CLIENT_DIR='${TEST_DIR}/mysql-client'
          export __SOURCED__=1
          . ../scripts/replication-member-join.sh
          printf '%s' \"\$MARIADB_CLI\"
        "
        The status should be success
        The output should eq "${TEST_DIR}/mysql-client/bin/mariadb"
      End
    End
  End
End
