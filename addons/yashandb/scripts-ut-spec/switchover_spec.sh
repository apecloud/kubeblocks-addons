# shellcheck shell=bash
# shellcheck disable=SC2034

# 2026-06-02 Reason: cover the approved standalone switchover script before implementation; Purpose: ensure the script only delegates the user-approved SQL to yasql and preserves database-side failure semantics.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "switchover_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "YASDB Switchover Script Tests"
  Include ../scripts/switchover.sh

  init() {
    ut_mode="true"
    YASDB_MOUNT_HOME="./test_mount"
    YASDB_HOME="./test_yasdb"
    YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"
    YASQL_ARGS_FILE="./yasql_args.log"

    mkdir -p "${YASDB_MOUNT_HOME}" "${YASDB_HOME}/conf" "${YASDB_HOME}/bin"
    touch "${YASDB_MOUNT_HOME}/.temp.ini"
    touch "${YASDB_HOME}/conf/yasdb.bashrc"
  }
  BeforeEach "init"

  cleanup() {
    rm -rf "${YASDB_MOUNT_HOME}" "${YASDB_HOME}" "${YASQL_ARGS_FILE}"
  }
  AfterEach 'cleanup'

  Describe "source_env_files()"
    It "sets up the yasql path"
      When call source_env_files
      The variable YASQL_BIN should eq "./test_yasdb/bin/yasql"
    End
  End

  Describe "switchover_database()"
    It "executes the standalone database switchover SQL"
      mkdir -p "${YASDB_HOME}/bin"
      cat >"${YASDB_HOME}/bin/yasql" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${YASQL_ARGS_FILE}"
exit 0
EOF
      chmod +x "${YASDB_HOME}/bin/yasql"

      When call switchover_database
      The status should be success
      The contents of file "${YASQL_ARGS_FILE}" should include "alter database switchover"
    End

    It "fails when the database switchover SQL fails"
      mkdir -p "${YASDB_HOME}/bin"
      cat >"${YASDB_HOME}/bin/yasql" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
      chmod +x "${YASDB_HOME}/bin/yasql"

      When call switchover_database
      The status should be failure
    End
  End
End
