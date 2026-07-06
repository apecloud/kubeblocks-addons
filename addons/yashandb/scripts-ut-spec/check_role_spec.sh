# shellcheck shell=bash
# shellcheck disable=SC2034

# 2026-06-02 Reason: cover YashanDB role mapping before wiring KubeBlocks roleProbe; Purpose: ensure database_role values are translated to KubeBlocks primary/secondary labels.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "check_role_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "YASDB Role Probe Tests"
  Include ../scripts/check_role.sh

  init() {
    ut_mode="true"
    YASDB_MOUNT_HOME="./test_mount"
    YASDB_HOME="./test_yasdb"
    YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"

    mkdir -p "${YASDB_MOUNT_HOME}" "${YASDB_HOME}/conf" "${YASDB_HOME}/bin"
    touch "${YASDB_MOUNT_HOME}/.temp.ini"
    touch "${YASDB_HOME}/conf/yasdb.bashrc"
  }
  BeforeEach "init"

  cleanup() {
    rm -rf "${YASDB_MOUNT_HOME}" "${YASDB_HOME}"
  }
  AfterEach 'cleanup'

  Describe "source_env_files()"
    It "sets up the yasql path"
      When call source_env_files
      The variable YASQL_BIN should eq "./test_yasdb/bin/yasql"
    End
  End

  Describe "map_database_role()"
    It "maps PRIMARY to primary"
      When call map_database_role "DATABASE_ROLE PRIMARY"
      The output should eq "primary"
    End

    It "maps STANDBY to secondary"
      When call map_database_role "DATABASE_ROLE STANDBY"
      The output should eq "secondary"
    End

    It "fails for an unknown database role"
      When call map_database_role "DATABASE_ROLE UNKNOWN"
      The status should be failure
    End
  End

  Describe "check_role()"
    It "returns primary when yasql reports PRIMARY"
      mkdir -p "${YASDB_HOME}/bin"
      cat >"${YASDB_HOME}/bin/yasql" <<'EOF'
#!/usr/bin/env bash
echo "DATABASE_ROLE"
echo "PRIMARY"
exit 0
EOF
      chmod +x "${YASDB_HOME}/bin/yasql"

      When call check_role
      The output should eq "primary"
    End

    It "returns secondary when yasql reports STANDBY"
      mkdir -p "${YASDB_HOME}/bin"
      cat >"${YASDB_HOME}/bin/yasql" <<'EOF'
#!/usr/bin/env bash
echo "DATABASE_ROLE"
echo "STANDBY"
exit 0
EOF
      chmod +x "${YASDB_HOME}/bin/yasql"

      When call check_role
      The output should eq "secondary"
    End
  End
End
