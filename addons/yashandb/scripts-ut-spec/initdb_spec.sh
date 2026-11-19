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

  # Contract: the restore marker is the ONLY signal that tells a restarted
  # container "this data dir is a half-restored cluster, re-enter the restore
  # path". It must survive every failure between restore submission and
  # verified open (rc-checked restore, open, READ_WRITE readiness), and be
  # removed only after all of them positively close. Deleting it right after
  # submitting `restore database` means an open/readiness failure + container
  # restart silently boots a normal cluster on half-restored data.
  Describe "restore_database() marker lifecycle"
    setup_restore() {
      YASDB_RESTORE_MARKER="${YASDB_MOUNT_HOME}/.restore_new_cluster"
      RESTORE_SRC_DIR="${YASDB_MOUNT_HOME}/restore/bk1"
      mkdir -p "${RESTORE_SRC_DIR}"
      printf '%s\n' "${RESTORE_SRC_DIR}" >"${YASDB_RESTORE_MARKER}"
      START_LOG_FILE="${YASDB_DATA}/log/start.log"
      : >"${START_LOG_FILE}"

      # Stub the process start and the yasql client. The stub distinguishes the
      # readiness poll (-c "select open_mode...") from the heredoc-driven
      # restore/open submissions, and is controlled by two files:
      #   ${YASDB_DATA}/open_mode    - what the readiness poll reports
      #   ${YASDB_DATA}/restore_rc   - exit code for the restore submission
      start_yasdb_process() { return 0; }
      YASQL_BIN="${YASDB_HOME}/bin/yasql-stub"
      cat >"${YASQL_BIN}" <<STUB
#!/bin/bash
if [[ "\$*" == *"select open_mode"* ]]; then
  cat "${YASDB_DATA}/open_mode"
  exit 0
fi
input=\$(cat)
if [[ "\$input" == *"restore database"* ]]; then
  exit "\$(cat "${YASDB_DATA}/restore_rc")"
fi
exit 0
STUB
      chmod +x "${YASQL_BIN}"
      echo "READ_WRITE" >"${YASDB_DATA}/open_mode"
      echo "0" >"${YASDB_DATA}/restore_rc"
      # Collapse the bounded 60x1s readiness loop for the failure cases.
      sleep() { :; }
    }
    cleanup_restore() {
      rm -f "${YASDB_RESTORE_MARKER}" "${YASDB_DATA}/open_mode" "${YASDB_DATA}/restore_rc"
      rm -rf "${YASDB_MOUNT_HOME}/restore"
    }
    BeforeEach "setup_restore"
    AfterEach "cleanup_restore"

    It "keeps the marker when the restored database never reaches READ_WRITE"
      echo "MOUNTED" >"${YASDB_DATA}/open_mode"

      When call restore_database
      The status should be failure
      The output should include "Failed to open restored database"
      The path "${YASDB_RESTORE_MARKER}" should be exist
    End

    It "fails and keeps the marker when the restore submission itself fails"
      echo "1" >"${YASDB_DATA}/restore_rc"

      When call restore_database
      The status should be failure
      The output should include "restore submission failed"
      The output should include "keeping restore marker"
      The path "${YASDB_RESTORE_MARKER}" should be exist
    End

    It "removes the marker only after restore, open and readiness all succeed"
      When call restore_database
      The status should be success
      The output should include "Database open succeed"
      The path "${YASDB_RESTORE_MARKER}" should not be exist
    End
  End
End
