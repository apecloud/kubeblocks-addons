# shellcheck shell=bash
# Unit tests for replication-roleprobe.sh
# Tests the file-based role detection logic plus the secondary publication
# readiness gates backed by local MariaDB / SHOW SLAVE STATUS truth.

Describe "replication-roleprobe.sh"
  setup() {
    TEST_DIR=$(mktemp -d)
    TEST_ORIG_PATH="$PATH"
    export MARIADB_DATADIR="$TEST_DIR"
    export DATA_DIR="$TEST_DIR"
    export SYNCERCTL_BIN="${TEST_DIR}/syncerctl"
    export PATH="${TEST_DIR}:$PATH"
    export MARIADB_ROLEPROBE_SKIP_DB_READY="true"
    export MARIADB_ROOT_HOST="localhost"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    export PATH="$TEST_ORIG_PATH"
    unset MARIADB_DATADIR DATA_DIR SYNCERCTL_BIN MOCK_SYNCERCTL_ROLE MARIADB_ROLEPROBE_SKIP_DB_READY MARIADB_ROLEPROBE_REQUIRE_SQL_LISTENER_READY TEST_ORIG_PATH MARIADB_ROOT_HOST MARIADB_INTERNAL_ROOT_USER
    unset MOCK_MARIADB_SELECT1_RC MOCK_MARIADB_SELECT1_STDOUT
    unset MOCK_MARIADB_SHOW_SLAVE_STATUS_RC MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT
    unset MOCK_MARIADB_BIND_ADDRESS MOCK_MARIADB_BIND_ADDRESS_RC
    unset MOCK_MARIADB_READ_ONLY MOCK_MARIADB_READ_ONLY_RC
    unset MOCK_MARIADB_SQL_RC MOCK_MARIADB_CAPTURE_FILE MOCK_MARIADB_ROOT_SHOW_SLAVE_STATUS_RC MOCK_MARIADB_ROOT_SELECT1_RC
  }
  AfterEach "cleanup"

  Include ../scripts/replication-roleprobe.sh

  make_syncerctl() {
    cat > "${SYNCERCTL_BIN}" <<'EOF'
#!/bin/sh
printf "%s" "${MOCK_SYNCERCTL_ROLE}"
EOF
    chmod +x "${SYNCERCTL_BIN}"
  }

  make_mariadb_cli() {
    cat > "${TEST_DIR}/mariadb" <<'EOF'
#!/bin/sh
case "$*" in
  *"SELECT 1"*)
    case "$*" in
      *"-uroot"*)
        if [ "${MOCK_MARIADB_ROOT_SELECT1_RC+x}" = "x" ]; then
          exit "${MOCK_MARIADB_ROOT_SELECT1_RC}"
        fi
        ;;
    esac
    if [ -n "${MOCK_MARIADB_SELECT1_STDOUT:-}" ]; then
      printf "%s\n" "${MOCK_MARIADB_SELECT1_STDOUT}"
    fi
    exit "${MOCK_MARIADB_SELECT1_RC:-0}"
    ;;
  *"SHOW SLAVE STATUS\\G"*)
    case "$*" in
      *"-uroot"*)
        if [ "${MOCK_MARIADB_ROOT_SHOW_SLAVE_STATUS_RC+x}" = "x" ]; then
          exit "${MOCK_MARIADB_ROOT_SHOW_SLAVE_STATUS_RC}"
        fi
        ;;
    esac
    if [ "${MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT+x}" = "x" ]; then
      printf "%s\n" "${MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT}"
    fi
    exit "${MOCK_MARIADB_SHOW_SLAVE_STATUS_RC:-0}"
    ;;
  *"SHOW VARIABLES LIKE 'bind_address'"*)
    printf "bind_address\t%s\n" "${MOCK_MARIADB_BIND_ADDRESS:-0.0.0.0}"
    exit "${MOCK_MARIADB_BIND_ADDRESS_RC:-0}"
    ;;
  *"SELECT UPPER(CAST(@@global.read_only AS CHAR));"*)
    printf "%s\n" "${MOCK_MARIADB_READ_ONLY:-0}"
    exit "${MOCK_MARIADB_READ_ONLY_RC:-0}"
    ;;
esac
if [ -n "${MOCK_MARIADB_CAPTURE_FILE:-}" ]; then
  printf "%s\n" "$*" >> "${MOCK_MARIADB_CAPTURE_FILE}"
fi
exit "${MOCK_MARIADB_SQL_RC:-0}"
EOF
    chmod +x "${TEST_DIR}/mariadb"
  }

  Describe "check_role()"
    Context "when syncerctl returns stale secondary but local files say primary"
      setup_stale_syncer_secondary() {
        export MOCK_SYNCERCTL_ROLE="secondary"
        touch "${TEST_DIR}/.replication-ready"
        make_syncerctl
      }
      Before "setup_stale_syncer_secondary"

      It "keeps local file-based primary truth"
        When call check_role
        The status should be success
        The output should eq "primary"
      End
    End

    Context "when syncerctl returns stale primary but pod is still pending"
      setup_stale_syncer_primary() {
        export MOCK_SYNCERCTL_ROLE="primary"
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/.replication-pending"
        make_syncerctl
      }
      Before "setup_stale_syncer_primary"

      It "does not publish a role before bootstrap finishes"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when .replication-pending exists"
      setup_pending() {
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/.replication-pending"
      }
      Before "setup_pending"

      It "does not publish a role while pod is still initializing"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when master.info exists (no pending flag)"
      setup_secondary() {
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/master.info"
      }
      Before "setup_secondary"

      It "returns 'secondary' (CHANGE MASTER TO was run)"
        When call check_role
        The status should be success
        The output should eq "secondary"
      End
    End

    Context "when running in kbagent contract without a live DB or mariadb client"
      setup_kbagent_primary() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        touch "${TEST_DIR}/.replication-ready"
      }
      Before "setup_kbagent_primary"

      It "still returns 'primary' from shared datadir markers"
        When call check_role
        The status should be success
        The output should eq "primary"
      End
    End

    Context "when running in kbagent contract with master.info and no live DB"
      setup_kbagent_secondary_db_down() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/master.info"
      }
      Before "setup_kbagent_secondary_db_down"

      It "does not publish secondary without current local DB reachability"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when local DB is reachable but SHOW SLAVE STATUS returns empty"
      setup_secondary_empty_slave_status() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/master.info"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT=""
        make_mariadb_cli
      }
      Before "setup_secondary_empty_slave_status"

      It "does not publish secondary when replication truth cannot be read"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when local DB is reachable but slave status output is unlabeled"
      setup_secondary_value_only_slave_status() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/master.info"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT="Yes
Yes
0
0"
        make_mariadb_cli
      }
      Before "setup_secondary_value_only_slave_status"

      It "fails closed instead of treating value-only output as healthy"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when local DB is reachable but replication is unhealthy"
      setup_secondary_unhealthy_replication() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/master.info"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT="Slave_IO_Running: Yes
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 1062"
        make_mariadb_cli
      }
      Before "setup_secondary_unhealthy_replication"

      It "does not publish secondary until IO/SQL truth is healthy"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when local DB and labeled replication truth are healthy"
      setup_secondary_live_and_healthy() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/master.info"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT="Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0"
        make_mariadb_cli
      }
      Before "setup_secondary_live_and_healthy"

      It "publishes secondary only after current replication truth closes"
        When call check_role
        The status should be success
        The output should eq "secondary"
      End
    End

    Context "when user-facing root cannot read slave status but internal admin can"
      setup_secondary_internal_admin_probe() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/master.info"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_ROOT_SHOW_SLAVE_STATUS_RC=1
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT="Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0"
        make_mariadb_cli
      }
      Before "setup_secondary_internal_admin_probe"

      It "uses internal admin as a local probe fallback and publishes secondary"
        When call check_role
        The status should be success
        The output should eq "secondary"
      End
    End

    Context "when neither file exists"
      setup_primary() {
        touch "${TEST_DIR}/.replication-ready"
      }
      Before "setup_primary"

      It "returns 'primary' (RESET SLAVE ALL was run or never configured)"
        When call check_role
        The status should be success
        The output should eq "primary"
      End
    End

    Context "when sql listener readiness is required but marker is missing"
      setup_primary_without_listener_marker() {
        export MARIADB_ROLEPROBE_REQUIRE_SQL_LISTENER_READY="true"
        touch "${TEST_DIR}/.replication-ready"
      }
      Before "setup_primary_without_listener_marker"

      It "does not publish primary before SQL listener is exposed"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when sql listener readiness is required but bind_address is local only"
      setup_primary_local_listener_only() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        export MARIADB_ROLEPROBE_REQUIRE_SQL_LISTENER_READY="true"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_BIND_ADDRESS="127.0.0.1"
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/.sql-listener-ready"
        make_mariadb_cli
      }
      Before "setup_primary_local_listener_only"

      It "does not publish primary while SQL listener is still local-only"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when sql listener readiness is required and bind_address is reachable by peers"
      setup_primary_peer_reachable_listener() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        export MARIADB_ROLEPROBE_REQUIRE_SQL_LISTENER_READY="true"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_BIND_ADDRESS="0.0.0.0"
        export MOCK_MARIADB_READ_ONLY="0"
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/.sql-listener-ready"
        touch "${TEST_DIR}/.primary-read-write-ready"
        make_mariadb_cli
      }
      Before "setup_primary_peer_reachable_listener"

      It "publishes primary only after SQL listener is peer-reachable"
        When call check_role
        The status should be success
        The output should eq "primary"
      End
    End

    Context "when primary read-write readiness marker is missing"
      setup_primary_missing_read_write_marker() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        export MARIADB_ROLEPROBE_REQUIRE_SQL_LISTENER_READY="true"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_BIND_ADDRESS="0.0.0.0"
        export MOCK_MARIADB_READ_ONLY="0"
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/.sql-listener-ready"
        make_mariadb_cli
      }
      Before "setup_primary_missing_read_write_marker"

      It "does not publish primary until runtime proves local root writes are ready"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when SQL listener is peer-reachable but local server is still read-only"
      setup_primary_read_only() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        export MARIADB_ROLEPROBE_REQUIRE_SQL_LISTENER_READY="true"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_BIND_ADDRESS="0.0.0.0"
        export MOCK_MARIADB_READ_ONLY="1"
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/.sql-listener-ready"
        touch "${TEST_DIR}/.primary-read-write-ready"
        make_mariadb_cli
      }
      Before "setup_primary_read_only"

      It "does not publish primary until local read_only is off"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when publishing a primary with remote root access enabled"
      setup_primary_remote_root() {
        export MARIADB_ROOT_HOST="%"
        export MOCK_MARIADB_CAPTURE_FILE="${TEST_DIR}/mariadb-sql.log"
        touch "${TEST_DIR}/.replication-ready"
        make_mariadb_cli
      }
      Before "setup_primary_remote_root"

      It "alpha.60: restores remote root grants WITHOUT admin bypass privileges and records primary fence marker"
        # alpha.60 (Jack 23:28 review): primary grant must NOT include
        # SUPER / READ_ONLY ADMIN / BINLOG ADMIN, because those let user-facing
        # root bypass @@global.read_only=ON during a future switchover and
        # break post-DCS local-root fence. GRANT OPTION is only via the
        # trailing WITH GRANT OPTION clause, never inside the privilege list
        # (the latter is a syntax error in some MariaDB versions).
        When call check_role
        The status should be success
        The output should eq "primary"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should include "REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'root'@'%'"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should include "ON *.* TO 'root'@'%' WITH GRANT OPTION"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should not include "GRANT ALL PRIVILEGES ON *.*"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should not include "SUPER"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should not include "READ_ONLY ADMIN"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should not include "BINLOG ADMIN"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should not include ", GRANT OPTION,"
        The contents of file "${TEST_DIR}/.remote-root-fence-role" should eq "primary"
      End
    End

    Context "when publishing a secondary with remote root access enabled"
      setup_secondary_remote_root() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        export MARIADB_ROOT_HOST="%"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT="Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0"
        export MOCK_MARIADB_CAPTURE_FILE="${TEST_DIR}/mariadb-sql.log"
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/master.info"
        make_mariadb_cli
      }
      Before "setup_secondary_remote_root"

      It "alpha.61: restricts remote root grants on secondary WITHOUT admin bypass privileges"
        # alpha.61 (Jack 01:40 review): user-facing root on secondary must
        # NOT carry SUPER, READ_ONLY ADMIN, BINLOG ADMIN, or CONNECTION ADMIN.
        # The legitimate bypass need (kb_health_check 1062 repair) uses
        # kb_internal_root in roleProbe's secondary_kb_health_check_repair_attempt.
        # REPLICATION MASTER ADMIN stays so the secondary can run CHANGE MASTER /
        # START SLAVE for follow-time maintenance. BINLOG MONITOR / SLAVE
        # MONITOR are read-only monitoring privileges and stay.
        When call check_role
        The status should be success
        The output should eq "secondary"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should include "REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'root'@'%'"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should include "GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO 'root'@'%'"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should include "GRANT BINLOG MONITOR ON *.* TO 'root'@'%'"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should include "GRANT SLAVE MONITOR ON *.* TO 'root'@'%'"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should not include "SUPER"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should not include "READ_ONLY ADMIN"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should not include "BINLOG ADMIN"
        The contents of file "${TEST_DIR}/mariadb-sql.log" should not include "CONNECTION ADMIN"
        The contents of file "${TEST_DIR}/.remote-root-fence-role" should eq "secondary"
      End
    End

    Context "when remote root fencing fails"
      setup_secondary_fence_failure() {
        unset MARIADB_ROLEPROBE_SKIP_DB_READY
        export MARIADB_ROOT_HOST="%"
        export MOCK_MARIADB_SELECT1_RC=0
        export MOCK_MARIADB_SELECT1_STDOUT="1"
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT="Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0"
        export MOCK_MARIADB_SQL_RC=1
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/master.info"
        printf "primary" > "${TEST_DIR}/.remote-root-fence-role"
        make_mariadb_cli
      }
      Before "setup_secondary_fence_failure"

      It "fails closed and clears the stale fence marker"
        When call check_role
        The status should be failure
        The output should eq "initializing"
        The path "${TEST_DIR}/.remote-root-fence-role" should not be exist
      End
    End

    Context "when both .replication-pending and master.info exist"
      setup_both() {
        touch "${TEST_DIR}/.replication-ready"
        touch "${TEST_DIR}/.replication-pending"
        touch "${TEST_DIR}/master.info"
      }
      Before "setup_both"

      It "does not publish a role because .replication-pending takes priority"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End

    Context "when bootstrap has not created .replication-ready"
      It "does not publish a role"
        When call check_role
        The status should be failure
        The output should eq "initializing"
      End
    End
  End

  # alpha.59: switchover action no longer waits for old-primary follow
  # convergence (kbagent enforces a 60s action ceiling). The kb_health_check
  # 1062/1146 repair path moved here so the secondary roleProbe self-heals
  # the duplicate-row case asynchronously. See addon-test-runner-write-after-bounded
  # role-gate guide and bootstrap-runner-preload-after-bounded-role-gate-case.
  Describe "secondary_kb_health_check_repair_attempt()"
    Context "when slave status shows 1062 + kubeblocks.kb_health_check"
      setup_repair_kb_health_check_signature() {
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT="Slave_IO_Running: Yes
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 1062
Last_SQL_Error: Could not execute Write_rows event on table kubeblocks.kb_health_check"
        export MOCK_MARIADB_READ_ONLY="1"
        export MOCK_MARIADB_CAPTURE_FILE="${TEST_DIR}/sql_calls"
        : > "${MOCK_MARIADB_CAPTURE_FILE}"
        make_mariadb_cli
      }
      Before "setup_repair_kb_health_check_signature"

      It "fires repair: STOP SLAVE SQL_THREAD, DELETE kb_health_check, START SLAVE SQL_THREAD"
        When call secondary_kb_health_check_repair_attempt
        The status should be success
        The stderr should include "secondary_kb_health_check_repair_attempt: detected 1062/1146 on kubeblocks.kb_health_check, attempting repair"
        The stderr should include "secondary_kb_health_check_repair_attempt: rc=0"
        The contents of file "${TEST_DIR}/sql_calls" should include "STOP SLAVE SQL_THREAD;"
        The contents of file "${TEST_DIR}/sql_calls" should include "DELETE FROM kubeblocks.kb_health_check;"
        The contents of file "${TEST_DIR}/sql_calls" should include "START SLAVE SQL_THREAD;"
      End

      It "uses kb_internal_root for the maintenance writes (not user-facing root)"
        When call secondary_kb_health_check_repair_attempt
        The status should be success
        The stderr should include "secondary_kb_health_check_repair_attempt: rc=0"
        The contents of file "${TEST_DIR}/sql_calls" should include "-ukb_internal_root"
        The contents of file "${TEST_DIR}/sql_calls" should not include "-uroot"
      End

      It "alpha.59 invariant: NEVER opens @@global.read_only during repair (no double-writable window)"
        # Per Jack 19:45 review blocker 2: a transient SET GLOBAL read_only=OFF
        # during repair would create a tiny but real write window that
        # contradicts double_writable=0. kb_internal_root has READ_ONLY ADMIN
        # so the maintenance DELETE works while read_only stays ON.
        When call secondary_kb_health_check_repair_attempt
        The status should be success
        The stderr should include "secondary_kb_health_check_repair_attempt: rc=0"
        The contents of file "${TEST_DIR}/sql_calls" should not include "SET GLOBAL read_only=OFF"
        The contents of file "${TEST_DIR}/sql_calls" should not include "SET GLOBAL read_only=ON"
        The contents of file "${TEST_DIR}/sql_calls" should not include "set global read_only=off"
      End
    End

    Context "when slave status shows 1062 but the table is NOT kubeblocks.kb_health_check"
      setup_repair_other_table() {
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT="Slave_IO_Running: Yes
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 1062
Last_SQL_Error: Could not execute Write_rows event on table myapp.users"
        export MOCK_MARIADB_CAPTURE_FILE="${TEST_DIR}/sql_calls"
        : > "${MOCK_MARIADB_CAPTURE_FILE}"
        make_mariadb_cli
      }
      Before "setup_repair_other_table"

      It "does NOT fire repair (precise signature, no other 1062 swallowed)"
        When call secondary_kb_health_check_repair_attempt
        The status should be success
        The stderr should not include "attempting repair"
        The contents of file "${TEST_DIR}/sql_calls" should not include "DELETE FROM kubeblocks.kb_health_check;"
        The contents of file "${TEST_DIR}/sql_calls" should not include "STOP SLAVE SQL_THREAD;"
      End
    End

    Context "when slave status shows a non-1062/1146 error"
      setup_repair_other_errno() {
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT="Slave_IO_Running: Yes
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 1064
Last_SQL_Error: You have an error in your SQL syntax"
        export MOCK_MARIADB_CAPTURE_FILE="${TEST_DIR}/sql_calls"
        : > "${MOCK_MARIADB_CAPTURE_FILE}"
        make_mariadb_cli
      }
      Before "setup_repair_other_errno"

      It "does NOT fire repair (only 1062/1146 are repairable)"
        When call secondary_kb_health_check_repair_attempt
        The status should be success
        The stderr should not include "attempting repair"
        The contents of file "${TEST_DIR}/sql_calls" should not include "DELETE FROM kubeblocks.kb_health_check;"
      End
    End

    Context "when slave status is empty"
      setup_repair_empty_status() {
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_RC=0
        export MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT=""
        export MOCK_MARIADB_CAPTURE_FILE="${TEST_DIR}/sql_calls"
        : > "${MOCK_MARIADB_CAPTURE_FILE}"
        make_mariadb_cli
      }
      Before "setup_repair_empty_status"

      It "does NOT fire repair when slave status output is empty"
        When call secondary_kb_health_check_repair_attempt
        The status should be success
        The stderr should not include "attempting repair"
      End
    End
  End

  Describe "slave_status_has_kb_health_check_repairable_error()"
    It "matches Last_SQL_Errno: 1062 + kubeblocks.kb_health_check"
      When call slave_status_has_kb_health_check_repairable_error "Slave_SQL_Running: No
Last_SQL_Errno: 1062
Last_SQL_Error: ... on table kubeblocks.kb_health_check at master log"
      The status should be success
    End

    It "matches Last_Errno: 1062 + kubeblocks.kb_health_check (legacy field name)"
      When call slave_status_has_kb_health_check_repairable_error "Slave_SQL_Running: No
Last_Errno: 1062
Last_Error: ... on table kubeblocks.kb_health_check at master log"
      The status should be success
    End

    It "matches Last_SQL_Errno: 1146 + kubeblocks.kb_health_check (missing table)"
      When call slave_status_has_kb_health_check_repairable_error "Slave_SQL_Running: No
Last_SQL_Errno: 1146
Last_SQL_Error: Table 'kubeblocks.kb_health_check' doesn't exist"
      The status should be success
    End

    It "does NOT match 1062 on a different table"
      When call slave_status_has_kb_health_check_repairable_error "Slave_SQL_Running: No
Last_SQL_Errno: 1062
Last_SQL_Error: ... on table myapp.users"
      The status should be failure
    End

    It "does NOT match other errno even on kubeblocks.kb_health_check"
      When call slave_status_has_kb_health_check_repairable_error "Slave_SQL_Running: No
Last_SQL_Errno: 1064
Last_SQL_Error: ... on table kubeblocks.kb_health_check"
      The status should be failure
    End

    It "does NOT match empty input"
      When call slave_status_has_kb_health_check_repairable_error ""
      The status should be failure
    End
  End
End
