# shellcheck shell=bash
# shellcheck disable=SC2034

# 2026-06-02 Reason: cover lightweight SQL readiness behavior before adding the probe script; Purpose: keep YashanDB liveness contract testable without depending on a real cluster.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "check_alive_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "YASDB Readiness Probe Tests"
  Include ../scripts/check_alive.sh

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

  Describe "check_alive()"
    It "succeeds when the lightweight instance status SQL returns"
      mkdir -p "${YASDB_HOME}/bin"
      cat >"${YASDB_HOME}/bin/yasql" <<'EOF'
#!/usr/bin/env bash
echo "OPEN"
exit 0
EOF
      chmod +x "${YASDB_HOME}/bin/yasql"

      When call check_alive
      The status should be success
    End

    It "fails when the lightweight instance status SQL returns a non-open state"
      mkdir -p "${YASDB_HOME}/bin"
      cat >"${YASDB_HOME}/bin/yasql" <<'EOF'
#!/usr/bin/env bash
echo "MOUNTED"
exit 0
EOF
      chmod +x "${YASDB_HOME}/bin/yasql"

      When call check_alive
      The status should be failure
    End

    It "fails when the lightweight instance status SQL fails"
      mkdir -p "${YASDB_HOME}/bin"
      cat >"${YASDB_HOME}/bin/yasql" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
      chmod +x "${YASDB_HOME}/bin/yasql"

      When call check_alive
      The status should be failure
    End
  End
End
