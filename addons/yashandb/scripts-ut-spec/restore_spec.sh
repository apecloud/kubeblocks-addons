# shellcheck shell=bash
# shellcheck disable=SC2034

# 2026-06-02 Reason: cover restore data preparation before wiring KubeBlocks restore; Purpose: ensure restore.sh only downloads backup data and writes a restore marker.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "restore_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "YASDB Restore Preparation Tests"
  Include ../dataprotection/restore.sh

  init() {
    ut_mode="true"
    YASDB_MOUNT_HOME="./test_mount"
    DP_BACKUP_NAME="test-backup"
    DP_BACKUP_BASE_PATH="/backup-root"
    DP_DATASAFED_BIN_PATH="./test_bin"
    YASDB_RESTORE_ROOT="${YASDB_MOUNT_HOME}/restore"
    YASDB_RESTORE_DIR="${YASDB_RESTORE_ROOT}/${DP_BACKUP_NAME}"
    DATASAFED_ARGS_FILE="./datasafed_args.log"

    mkdir -p "${YASDB_MOUNT_HOME}" "${DP_DATASAFED_BIN_PATH}" "./archive_src"
    echo "restored" >"./archive_src/backup.txt"
    tar -C "./archive_src" -cf "./${DP_BACKUP_NAME}.tar" .
    cat >"${DP_DATASAFED_BIN_PATH}/datasafed" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${DATASAFED_ARGS_FILE}"
cat "./${DP_BACKUP_NAME}.tar"
exit 0
EOF
    chmod +x "${DP_DATASAFED_BIN_PATH}/datasafed"
  }
  BeforeEach "init"

  cleanup() {
    rm -rf "${YASDB_MOUNT_HOME}" "${DP_DATASAFED_BIN_PATH}" "${DATASAFED_ARGS_FILE}" "./archive_src" "./${DP_BACKUP_NAME}.tar"
  }
  AfterEach 'cleanup'

  Describe "prepare_restore_data()"
    It "downloads backup data and writes the restore marker"
      When call prepare_restore_data
      The status should be success
      The path "${YASDB_MOUNT_HOME}/.restore_new_cluster" should exist
      The path "${YASDB_RESTORE_DIR}/backup.txt" should exist
      The contents of file "${DATASAFED_ARGS_FILE}" should include "pull"
      The contents of file "${DATASAFED_ARGS_FILE}" should include "test-backup.tar"
    End
  End
End
