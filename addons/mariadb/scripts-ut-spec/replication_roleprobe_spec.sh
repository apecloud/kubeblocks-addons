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
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    export PATH="$TEST_ORIG_PATH"
    unset MARIADB_DATADIR DATA_DIR SYNCERCTL_BIN MOCK_SYNCERCTL_ROLE MARIADB_ROLEPROBE_SKIP_DB_READY TEST_ORIG_PATH
    unset MOCK_MARIADB_SELECT1_RC MOCK_MARIADB_SELECT1_STDOUT
    unset MOCK_MARIADB_SHOW_SLAVE_STATUS_RC MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT
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
    if [ -n "${MOCK_MARIADB_SELECT1_STDOUT:-}" ]; then
      printf "%s\n" "${MOCK_MARIADB_SELECT1_STDOUT}"
    fi
    exit "${MOCK_MARIADB_SELECT1_RC:-0}"
    ;;
  *"SHOW SLAVE STATUS\\G"*)
    if [ "${MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT+x}" = "x" ]; then
      printf "%s\n" "${MOCK_MARIADB_SHOW_SLAVE_STATUS_STDOUT}"
    fi
    exit "${MOCK_MARIADB_SHOW_SLAVE_STATUS_RC:-0}"
    ;;
esac
exit 0
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
End
