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

      It "prepares an empty local KubeBlocks health check table after starting IO and before starting SQL"
        : > "${TEST_DIR}/call-log"
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-100" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"START SLAVE IO_THREAD"*) echo "change-master" >> "${TEST_DIR}/call-log"; echo "start-io" >> "${TEST_DIR}/call-log" ;;
            *"CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check"*) echo "cleanup" >> "${TEST_DIR}/call-log" ;;
            *"START SLAVE SQL_THREAD"*) echo "start-sql" >> "${TEST_DIR}/call-log" ;;
            *"gtid_slave_pos;"*) echo "" ;;
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
        The contents of file "${TEST_DIR}/call-log" should eq "change-master
start-io
cleanup
start-sql"
        The file "${TEST_DIR}/log/fresh-replica-health-check-cleanup.log" should be file
        The output should include "Prepared local kubeblocks health check table"
      End

      It "repairs a local health check duplicate and restarts the SQL thread once"
        : > "${TEST_DIR}/call-log"
        query_count=0
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-100" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"START SLAVE IO_THREAD"*) echo "start-io" >> "${TEST_DIR}/call-log" ;;
            *"CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check"*) echo "cleanup" >> "${TEST_DIR}/call-log" ;;
            *"STOP SLAVE SQL_THREAD"*) echo "stop-sql" >> "${TEST_DIR}/call-log" ;;
            *"START SLAVE SQL_THREAD"*) echo "start-sql" >> "${TEST_DIR}/call-log" ;;
            *"gtid_slave_pos;"*) echo "" ;;
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *) : ;;
          esac
        }
        query_slave_status_verbose() {
          query_count=$(cat "${TEST_DIR}/query-count" 2>/dev/null || echo 0)
          query_count=$((query_count + 1))
          printf "%s" "${query_count}" > "${TEST_DIR}/query-count"
          if [ "${query_count}" -eq 1 ]; then
            cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 1062
Last_SQL_Error: Error 'Duplicate entry' on table 'kubeblocks.kb_health_check'
EOF
          else
            cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
EOF
          fi
        }
        When call setup_replication
        The contents of file "${TEST_DIR}/call-log" should include "stop-sql"
        The contents of file "${TEST_DIR}/call-log" should include "cleanup"
        The contents of file "${TEST_DIR}/call-log" should include "start-sql"
        The output should include "after repairing kubeblocks health check replication error"
      End

      It "repairs a missing local health check table and restarts the SQL thread once"
        : > "${TEST_DIR}/call-log"
        query_count=0
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-100" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"START SLAVE IO_THREAD"*) echo "start-io" >> "${TEST_DIR}/call-log" ;;
            *"CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check"*) echo "cleanup" >> "${TEST_DIR}/call-log" ;;
            *"STOP SLAVE SQL_THREAD"*) echo "stop-sql" >> "${TEST_DIR}/call-log" ;;
            *"START SLAVE SQL_THREAD"*) echo "start-sql" >> "${TEST_DIR}/call-log" ;;
            *"gtid_slave_pos;"*) echo "" ;;
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *) : ;;
          esac
        }
        query_slave_status_verbose() {
          query_count=$(cat "${TEST_DIR}/query-count" 2>/dev/null || echo 0)
          query_count=$((query_count + 1))
          printf "%s" "${query_count}" > "${TEST_DIR}/query-count"
          if [ "${query_count}" -eq 1 ]; then
            cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 1146
Last_SQL_Error: Error executing row event: 'Table 'kubeblocks.kb_health_check' doesn't exist'
EOF
          else
            cat <<'EOF'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
EOF
          fi
        }
        When call setup_replication
        The contents of file "${TEST_DIR}/call-log" should include "stop-sql"
        The contents of file "${TEST_DIR}/call-log" should include "cleanup"
        The contents of file "${TEST_DIR}/call-log" should include "start-sql"
        The output should include "after repairing kubeblocks health check replication error"
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

      It "does not clear the local health table on an existing GTID rejoin"
        CLEANUP_CALLED=""
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-200" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check"*) CLEANUP_CALLED="yes" ;;
            *"gtid_slave_pos;"*) echo "0-1-150" ;;
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
        The variable CLEANUP_CALLED should eq ""
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
        The stderr should include "phase: gtid-divergence-fail-closed"
        The stderr should include "next-retry-safe: no"
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
        The stderr should include "phase: gtid-divergence-fail-closed"
        The stderr should include "next-retry-safe: no"
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
        The stderr should include "phase: gtid-out-of-order-transient"
        The stderr should include "next-retry-safe: yes"
      End
    End

    Context "when slave is not yet ready for rejoin (Slave_IO_Running still Connecting)"
      It "returns failure with classified slave-not-yet-ready-for-rejoin retry=yes (alpha.110 implicit rc=0 bug fix)"
        # Regression guard for alpha.110 implicit rc=0 bug: that release returned rc=0
        # from this branch because the last statement was an echo (no explicit return 1).
        # alpha.113 reclassifies as slave-not-yet-ready-for-rejoin + retry=yes so kbagent
        # re-fires memberJoin until slave actually converges.
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-100" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_slave_pos;"*)   echo "" ;;
            *"SHOW SLAVE STATUS"*) echo "some-slave-status-row" ;;
            *) : ;;
          esac
        }
        query_slave_status_verbose() {
          cat <<'EOF'
Slave_IO_Running: Connecting
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 0
EOF
        }
        When call setup_replication
        The status should be failure
        The path "${TEST_DIR}/.replication-pending" should be exist
        The output should include "WARNING: replication rejoin not yet healthy"
        The stderr should include "phase: slave-not-yet-ready-for-rejoin"
        The stderr should include "next-retry-safe: yes"
        The stderr should include "Slave_IO_Running: Connecting"
        The stderr should include "Slave_SQL_Running: No"
      End
    End
  End

  Describe "replication_member_join_diagnose_not_ready()"
    Context "emits structured stderr with action label, phase, and retry-safe"
      It "writes the action label, phase, and next-retry-safe to stderr"
        export KB_CLUSTER_NAME="mdb-cluster"
        export POD_NAME="mdb-mariadb-1"
        ACTIVE_PRIMARY_HOST="mdb-mariadb.demo.svc.cluster.local"
        When call replication_member_join_diagnose_not_ready "primary-not-yet-reachable" "  probe_primary_host: mdb-mariadb.demo.svc.cluster.local" "yes"
        The status should be success
        The stderr should include "action: replication-member-join"
        The stderr should include "phase: primary-not-yet-reachable"
        The stderr should include "cluster: mdb-cluster"
        The stderr should include "pod: mdb-mariadb-1"
        The stderr should include "probe_primary_host: mdb-mariadb.demo.svc.cluster.local"
        The stderr should include "next-retry-safe: yes"
      End

      It "supports retry-safe: no for operator-attention failures"
        When call replication_member_join_diagnose_not_ready "change-master-failed" "  master_host: pri" "no"
        The status should be success
        The stderr should include "phase: change-master-failed"
        The stderr should include "next-retry-safe: no"
      End
    End
  End

  Describe "probe_primary_or_defer() single-shot"
    Context "when PRIMARY_HOST accepts SELECT 1"
      It "sets ACTIVE_PRIMARY_HOST and returns success"
        host_sql() {
          case "$1" in
            "${PRIMARY_HOST}") return 0 ;;
            *) return 1 ;;
          esac
        }
        ACTIVE_PRIMARY_HOST=""
        When call probe_primary_or_defer
        The status should be success
        The variable ACTIVE_PRIMARY_HOST should eq "${PRIMARY_HOST}"
      End
    End

    Context "when PRIMARY_HOST is unreachable on pod-0"
      It "defers without trying bootstrap fallback and writes retry-safe: yes diagnose"
        export POD_NAME="mdb-mariadb-0"
        POD_INDEX="0"
        host_sql() { return 1; }
        ACTIVE_PRIMARY_HOST=""
        When call probe_primary_or_defer
        The status should be failure
        The variable ACTIVE_PRIMARY_HOST should eq ""
        The stderr should include "phase: primary-not-yet-reachable"
        The stderr should include "next-retry-safe: yes"
      End
    End

    Context "when PRIMARY_HOST unreachable on pod-1 and bootstrap primary is writable"
      It "falls back to BOOTSTRAP_PRIMARY_HOST and returns success"
        export POD_NAME="mdb-mariadb-1"
        POD_INDEX="1"
        host_sql() {
          case "$*" in
            *"${BOOTSTRAP_PRIMARY_HOST}"*"read_only"*) echo "0"; return 0 ;;
            *) return 1 ;;
          esac
        }
        ACTIVE_PRIMARY_HOST=""
        When call probe_primary_or_defer
        The status should be success
        The variable ACTIVE_PRIMARY_HOST should eq "${BOOTSTRAP_PRIMARY_HOST}"
        The output should include "Using bootstrap primary"
      End
    End

    Context "when neither PRIMARY_HOST nor bootstrap primary are reachable on pod-1"
      It "defers with retry-safe: yes"
        export POD_NAME="mdb-mariadb-1"
        POD_INDEX="1"
        host_sql() { return 1; }
        ACTIVE_PRIMARY_HOST=""
        When call probe_primary_or_defer
        The status should be failure
        The variable ACTIVE_PRIMARY_HOST should eq ""
        The stderr should include "phase: primary-not-yet-reachable"
        The stderr should include "next-retry-safe: yes"
        The stderr should include "pod_index: 1"
      End
    End

    Context "when PRIMARY_HOST unreachable on pod-1 but bootstrap primary is read_only"
      It "defers because bootstrap is not writable (read_only != 0)"
        export POD_NAME="mdb-mariadb-1"
        POD_INDEX="1"
        host_sql() {
          case "$*" in
            *"${BOOTSTRAP_PRIMARY_HOST}"*"read_only"*) echo "1"; return 0 ;;
            *) return 1 ;;
          esac
        }
        ACTIVE_PRIMARY_HOST=""
        When call probe_primary_or_defer
        The status should be failure
        The variable ACTIVE_PRIMARY_HOST should eq ""
        The stderr should include "next-retry-safe: yes"
      End
    End
  End

  Describe "main() self-primary guard"
    Context "when this pod is the primary"
      It "skips replication setup and exits 0"
        local_sql()         { echo "100"; }
        primary_sql()       { echo "100"; }
        probe_primary_or_defer() { return 0; }
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
        probe_primary_or_defer() { return 0; }
        When call main
        The status should be success
        The output should include "Nothing to do"
      End
    End

    Context "when PRIMARY_HOST is unreachable but slave is already running"
      It "returns success without probing PRIMARY_HOST"
        local_sql() {
          case "$*" in
            *"SHOW SLAVE STATUS"*) echo "some-row" ;;
            *"Slave_running"*)     printf 'Slave_running\tON\n' ;;
          esac
        }
        probe_primary_or_defer() { echo "should-not-be-called"; return 1; }
        When call main
        The status should be success
        The output should include "Nothing to do"
        The output should not include "should-not-be-called"
      End
    End
  End

  Describe "setup_replication() rc=1 paths MUST write .replication-pending marker (regression guard for roleProbe stuck-initializing window)"
    setup_pending_guard() {
      rm -f "${TEST_DIR}/.replication-ready" "${TEST_DIR}/.replication-pending" "${TEST_DIR}/.replication-divergence-pending"
    }
    BeforeEach "setup_pending_guard"

    Context "fresh-pod CHANGE MASTER + START IO failed"
      It "writes .replication-pending before returning failure"
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-100" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_slave_pos;"*) echo "" ;;
            *"STOP SLAVE"*) return 1 ;;
            *) : ;;
          esac
        }
        When call setup_replication
        The status should be failure
        The output should be present
        The path "${TEST_DIR}/.replication-pending" should be exist
        The stderr should include "phase: change-master-or-start-io-failed"
      End
    End

    Context "rejoining-pod CHANGE MASTER failed"
      It "writes .replication-pending before returning failure"
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-200" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_slave_pos;"*) echo "0-1-150" ;;
            *"STOP SLAVE"*) return 1 ;;
            *) : ;;
          esac
        }
        When call setup_replication
        The status should be failure
        The output should be present
        The path "${TEST_DIR}/.replication-pending" should be exist
        The stderr should include "phase: change-master-failed"
      End
    End

    Context "SHOW SLAVE STATUS empty after successful CHANGE MASTER"
      It "writes .replication-pending before returning failure"
        primary_sql() {
          case "$*" in
            *"gtid_binlog_pos"*) echo "0-1-300" ;;
          esac
        }
        local_sql() {
          case "$*" in
            *"gtid_slave_pos;"*) echo "0-1-250" ;;
            *"STOP SLAVE"*) : ;;
            *"SHOW SLAVE STATUS"*) echo "" ;;
            *) : ;;
          esac
        }
        When call setup_replication
        The status should be failure
        The output should be present
        The path "${TEST_DIR}/.replication-pending" should be exist
        The stderr should include "phase: slave-config-not-persisted"
      End
    End
  End

  Describe "main() rc=1 paths MUST write .replication-pending marker (regression guard for roleProbe stuck-initializing window)"
    setup_main_guard() {
      rm -f "${TEST_DIR}/.replication-ready" "${TEST_DIR}/.replication-pending" "${TEST_DIR}/.replication-divergence-pending"
    }
    BeforeEach "setup_main_guard"

    Context "MARIADB_CLI unavailable"
      It "writes .replication-pending before returning failure"
        export MARIADB_CLI=""
        When call main
        The status should be failure
        The output should be present
        The path "${TEST_DIR}/.replication-pending" should be exist
        The stderr should include "phase: mariadb-cli-unavailable"
      End
    End

    Context "probe_primary_or_defer fails"
      It "writes .replication-pending before returning failure"
        local_sql() {
          case "$*" in
            *"SHOW SLAVE STATUS"*) echo "" ;;
            *) : ;;
          esac
        }
        is_slave_running() { return 1; }
        probe_primary_or_defer() { return 1; }
        When call main
        The status should be failure
        The path "${TEST_DIR}/.replication-pending" should be exist
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
