# shellcheck shell=sh

Describe "doltdb-mysql-replica-setup.sh"
  setup() {
    export TEST_DIR
    TEST_DIR="$(mktemp -d)"
    export PATH="${TEST_DIR}:$PATH"
    export DOLT_ROOT_PASSWORD="root-password"
    export DOLT_MYSQL_REPLICA_SETUP_TIMEOUT_SECONDS="1"
    export DOLT_MYSQL_REPLICA_SETUP_POLL_SECONDS="1"

    cat >"${TEST_DIR}/dolt" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${TEST_DIR}/dolt-argv"
for arg do
  case "$arg" in
    --query=SHOW\ REPLICA\ STATUS\;)
      cat <<'STATUS'
*************************** 1. row ***************************
Replica_IO_Running: Yes
Replica_SQL_Running: Yes
Last_IO_Error:
Last_SQL_Error:
STATUS
      exit 0
      ;;
    --query=*) exit 0 ;;
  esac
done
cat >>"${TEST_DIR}/dolt-stdin"
EOF
    chmod +x "${TEST_DIR}/dolt"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    unset DOLT_ROOT_PASSWORD DOLT_MYSQL_REPLICA_REQUIRED DOLT_MYSQL_SOURCE_HOST
    unset DOLT_MYSQL_SOURCE_PORT DOLT_MYSQL_SOURCE_USER DOLT_MYSQL_SOURCE_PASSWORD
    unset DOLT_MYSQL_REPLICA_SERVER_ID DOLT_MYSQL_REPLICATION_FILTER
    unset DOLT_MYSQL_REPLICA_SETUP_TIMEOUT_SECONDS DOLT_MYSQL_REPLICA_SETUP_POLL_SECONDS
    unset DOLT_MYSQL_REPLICA_STATUS_POLL_SECONDS
  }
  AfterEach "cleanup"

  It "skips setup when mysql-source ServiceRef is absent"
    When run sh ../scripts/doltdb-mysql-replica-setup.sh
    The status should be success
    The output should include "mysql-source ServiceRef is not bound"
    The path "${TEST_DIR}/dolt-argv" should not be exist
  End

  It "fails when MySQL-source replication requires a missing ServiceRef"
    export DOLT_MYSQL_REPLICA_REQUIRED="true"

    When run sh ../scripts/doltdb-mysql-replica-setup.sh
    The status should be failure
    The error should include "MySQL-source replication requires mysql-source ServiceRef binding"
  End

  It "configures replication from a SQL file so source password is not in argv"
    export DOLT_MYSQL_SOURCE_HOST="mysql-source.demo.svc"
    export DOLT_MYSQL_SOURCE_PORT="3306"
    export DOLT_MYSQL_SOURCE_USER="repl_user"
    export DOLT_MYSQL_SOURCE_PASSWORD="pa'ss word"
    export DOLT_MYSQL_REPLICA_SERVER_ID="123"
    export DOLT_MYSQL_REPLICATION_FILTER="REPLICATE_DO_TABLE=(testdb.kb_smoke)"

    When run sh ../scripts/doltdb-mysql-replica-setup.sh
    The status should be success
    The output should include "Dolt MySQL replication source configured"
    The contents of file "${TEST_DIR}/dolt-argv" should not include "pa'ss word"
    The contents of file "${TEST_DIR}/dolt-argv" should include "--query=SET @@PERSIST.server_id=123;"
    The contents of file "${TEST_DIR}/dolt-stdin" should include "SOURCE_HOST='mysql-source.demo.svc'"
    The contents of file "${TEST_DIR}/dolt-stdin" should include "SOURCE_PASSWORD='pa''ss word'"
    The contents of file "${TEST_DIR}/dolt-argv" should include "--query=CHANGE REPLICATION FILTER REPLICATE_DO_TABLE=(testdb.kb_smoke);"
    The contents of file "${TEST_DIR}/dolt-argv" should include "--query=START REPLICA;"
    The contents of file "${TEST_DIR}/dolt-argv" should include "--query=SHOW REPLICA STATUS;"
    The contents of file "${TEST_DIR}/dolt-argv" should include "--result-format=vertical"
  End

  It "fails when the MySQL-source replica does not become running"
    export DOLT_MYSQL_SOURCE_HOST="mysql-source.demo.svc"
    export DOLT_MYSQL_SOURCE_PORT="3306"
    export DOLT_MYSQL_SOURCE_USER="repl_user"
    export DOLT_MYSQL_SOURCE_PASSWORD="password"
    export DOLT_MYSQL_REPLICA_SERVER_ID="123"

    cat >"${TEST_DIR}/dolt" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${TEST_DIR}/dolt-argv"
for arg do
  case "$arg" in
    --query=SHOW\ REPLICA\ STATUS\;)
      cat <<'STATUS'
*************************** 1. row ***************************
Replica_IO_Running: No
Replica_SQL_Running: Yes
Last_IO_Error: Access denied for replication user
Last_SQL_Error:
STATUS
      exit 0
      ;;
    --query=*) exit 0 ;;
  esac
done
cat >>"${TEST_DIR}/dolt-stdin"
EOF
    chmod +x "${TEST_DIR}/dolt"

    When run sh ../scripts/doltdb-mysql-replica-setup.sh
    The status should be failure
    The output should include "timed out waiting for Dolt MySQL-source replication to run"
    The output should include "Replica_IO_Running=No"
    The output should include "Access denied for replication user"
  End

  It "rejects filter clauses containing semicolons"
    export DOLT_MYSQL_SOURCE_HOST="mysql-source.demo.svc"
    export DOLT_MYSQL_SOURCE_PORT="3306"
    export DOLT_MYSQL_SOURCE_USER="repl_user"
    export DOLT_MYSQL_SOURCE_PASSWORD="password"
    export DOLT_MYSQL_REPLICA_SERVER_ID="123"
    export DOLT_MYSQL_REPLICATION_FILTER="REPLICATE_DO_TABLE=(testdb.t1); RESET REPLICA ALL"

    When run sh ../scripts/doltdb-mysql-replica-setup.sh
    The status should be failure
    The error should include "DOLT_MYSQL_REPLICATION_FILTER must not contain semicolons"
  End

  It "does not create the sensitive SQL file before local Dolt is ready"
    export DOLT_MYSQL_SOURCE_HOST="mysql-source.demo.svc"
    export DOLT_MYSQL_SOURCE_PORT="3306"
    export DOLT_MYSQL_SOURCE_USER="repl_user"
    export DOLT_MYSQL_SOURCE_PASSWORD="password"
    export DOLT_MYSQL_REPLICA_SERVER_ID="123"

    cat >"${TEST_DIR}/dolt" <<'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "${TEST_DIR}/dolt"
    cat >"${TEST_DIR}/mktemp" <<'EOF'
#!/bin/sh
printf 'mktemp called\n' >>"${TEST_DIR}/mktemp-called"
exec /usr/bin/mktemp "$@"
EOF
    chmod +x "${TEST_DIR}/mktemp"

    When run sh ../scripts/doltdb-mysql-replica-setup.sh
    The status should be failure
    The output should include "configuring Dolt as MySQL replica"
    The error should include "timed out waiting for local Dolt SQL server"
    The path "${TEST_DIR}/mktemp-called" should not be exist
  End
End
