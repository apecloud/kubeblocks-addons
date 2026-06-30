# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "MySQL docker entrypoint restore account reset"
  Include ../scripts/docker-entrypoint-5.7.sh

  setup_restore_dir() {
    TEST_DATADIR="${SHELLSPEC_WORKDIR}/mysql-restore"
    mkdir -p "${TEST_DATADIR}/mysql"
    : > "${TEST_DATADIR}/.xtrabackup_restore"
    : > "${TEST_DATADIR}/.restore_new_cluster"
    : > "${TEST_DATADIR}/xtrabackup_info"

    export DATADIR="${TEST_DATADIR}"
    export SOCKET="${TEST_DATADIR}/mysql.sock"
    export MYSQL_MAJOR="8.0"
    export MYSQL_ROOT_USER="root"
    export MYSQL_ROOT_PASSWORD="targetRootPass"
    export MYSQL_ROOT_HOST="%"
    export MYSQL_ADMIN_USER="kbadmin"
    export MYSQL_ADMIN_PASSWORD="targetAdminPass"
    export MYSQL_REPLICATION_USER="kbreplicator"
    export MYSQL_REPLICATION_PASSWORD="targetReplicaPass"
    SQL_LOG="${SHELLSPEC_WORKDIR}/sql.log"
    : > "${SQL_LOG}"
  }

  BeforeEach "setup_restore_dir"

  It "resets restored new-cluster system accounts before xtrabackup GTID handling"
    mysql_note() {
      echo "$*"
    }
    docker_temp_server_start_skip_grants() {
      echo "skip-grants start $*"
    }
    docker_temp_server_start() {
      echo "normal start $*"
    }
    docker_temp_server_stop() {
      echo "stop"
    }
    docker_process_sql() {
      cat >> "${SQL_LOG}"
    }

    When call restore_standby_from_xtrabackup mysqld
    The status should be success
    The output should include "skip-grants start mysqld"
    The output should not include "normal start"
    The output should not include "targetRootPass"
    The output should not include "targetAdminPass"
    The contents of file "${SQL_LOG}" should not include "CREATE USER"
    The contents of file "${SQL_LOG}" should include "ALTER USER 'root'@'localhost' IDENTIFIED BY 'targetRootPass'"
    The contents of file "${SQL_LOG}" should include "ALTER USER 'kbadmin'@'%' IDENTIFIED BY 'targetAdminPass'"
    The contents of file "${SQL_LOG}" should include "ALTER USER 'kbreplicator'@'%' IDENTIFIED BY 'targetReplicaPass'"
    The path "${TEST_DATADIR}/.xtrabackup_restore" should not be exist
  End

  It "keeps standby restore on the normal authenticated temporary server path"
    rm -f "${TEST_DATADIR}/.restore_new_cluster"

    mysql_note() {
      echo "$*"
    }
    docker_temp_server_start_skip_grants() {
      echo "skip-grants start $*"
    }
    docker_temp_server_start() {
      echo "normal start $*"
    }
    docker_temp_server_stop() {
      echo "stop"
    }
    docker_process_sql() {
      cat >> "${SQL_LOG}"
    }

    When call restore_standby_from_xtrabackup mysqld
    The status should be success
    The output should include "normal start mysqld"
    The output should not include "skip-grants start"
    The contents of file "${SQL_LOG}" should not include "ALTER USER"
  End

  It "fails fast when a required restored account credential is empty"
    MYSQL_ROOT_PASSWORD=""
    mysql_error() {
      echo "$*" >&2
      return 1
    }
    mysql_note() {
      echo "$*"
    }
    docker_process_sql() {
      cat >> "${SQL_LOG}"
    }

    When call mysql_reset_restored_system_accounts
    The status should be failure
    The stderr should include "MYSQL_ROOT_PASSWORD"
    The contents of file "${SQL_LOG}" should equal ""
  End

  It "escapes quote and backslash characters in restored account secret literals"
    MYSQL_ROOT_PASSWORD="pa'ss\\word"
    MYSQL_ADMIN_PASSWORD="ad'min\\word"
    MYSQL_REPLICATION_PASSWORD="rep'lica\\word"
    mysql_note() {
      echo "$*"
    }
    docker_process_sql() {
      cat >> "${SQL_LOG}"
    }

    When call mysql_reset_restored_system_accounts
    The status should be success
    The output should include "Resetting restored MySQL system accounts"
    The contents of file "${SQL_LOG}" should include "ALTER USER 'root'@'localhost' IDENTIFIED BY 'pa''ss\\\\word'"
    The contents of file "${SQL_LOG}" should include "ALTER USER 'kbadmin'@'%' IDENTIFIED BY 'ad''min\\\\word'"
    The contents of file "${SQL_LOG}" should include "ALTER USER 'kbreplicator'@'%' IDENTIFIED BY 'rep''lica\\\\word'"
  End
End
