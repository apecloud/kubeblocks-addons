# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "roleprobe_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "YASDB Database Initialization Tests"
  Include ../scripts/initDB.sh

  init() {
    ut_mode="true"
    YASDB_MOUNT_HOME="./test_mount"
    YASDB_HOME="./test_yasdb"
    YASDB_DATA="./test_data"
    YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"
    INSTALL_INI_FILE="${YASDB_MOUNT_HOME}/install.ini"
    REDO_FILE_NUM=3
    REDO_FILE_SIZE="100M"
    NLS_CHARACTERSET="UTF8"
    INSTALL_SIMPLE_SCHEMA_SALES="y"

    # Create test directories and files
    mkdir -p "${YASDB_MOUNT_HOME}" "${YASDB_HOME}/conf" "${YASDB_HOME}/admin" "${YASDB_HOME}/bin" "${YASDB_DATA}/config" "${YASDB_DATA}/instance" "${YASDB_DATA}/log"
    touch "${YASDB_MOUNT_HOME}/.temp.ini"
    touch "${YASDB_MOUNT_HOME}/install.ini"
    touch "${YASDB_HOME}/conf/yasdb.bashrc"
    touch "${INSTALL_INI_FILE}"
  }
  BeforeAll "init"

  cleanup() {
    rm -rf "${YASDB_MOUNT_HOME}" "${YASDB_HOME}" "${YASDB_DATA}" "${INSTALL_INI_FILE}"
  }
  AfterAll 'cleanup'

  Describe "source_env_files()"
    It "sets up correct paths"
      When call source_env_files
      The variable YASDB_HOME_BIN_PATH should eq "./test_yasdb/bin"
      The variable YASDB_BIN should eq "./test_yasdb/bin/yasdb"
      The variable YASQL_BIN should eq "./test_yasdb/bin/yasql"
      The variable YASPWD_BIN should eq "./test_yasdb/bin/yaspwd"
    End
  End

  Describe "generate_redo_config()"
    It "generates correct redo file configuration"
      When call generate_redo_config
      The output should eq "('redo0' size 100M,'redo1' size 100M,'redo2' size 100M)"
    End
  End

  Describe "restore_database()"
    It "executes restore SQL from the prepared restore directory"
      YASDB_RESTORE_DIR="${YASDB_MOUNT_HOME}/restore/${DP_BACKUP_NAME:-test-backup}"
      mkdir -p "${YASDB_RESTORE_DIR}" "${YASDB_HOME}/bin"
      printf '%s\n' "${YASDB_RESTORE_DIR}" >"${YASDB_MOUNT_HOME}/.restore_new_cluster"
      cat >"${YASDB_HOME}/bin/yasdb" <<'EOF'
#!/usr/bin/env bash
echo "Instance started"
exit 0
EOF
      cat >"${YASDB_HOME}/bin/yasql" <<'EOF'
#!/usr/bin/env bash
cat >>"${YASDB_MOUNT_HOME}/restore_sql.log"
if grep -q "select open_mode from v\\$database" "${YASDB_MOUNT_HOME}/restore_sql.log"; then
  echo "READ_WRITE"
fi
exit 0
EOF
      chmod +x "${YASDB_HOME}/bin/yasdb" "${YASDB_HOME}/bin/yasql"

      When call restore_database
      The status should be success
      The contents of file "${YASDB_MOUNT_HOME}/restore_sql.log" should include "restore database from '${YASDB_RESTORE_DIR}'"
      The contents of file "${YASDB_MOUNT_HOME}/restore_sql.log" should include "alter database open;"
    End
  End
End
