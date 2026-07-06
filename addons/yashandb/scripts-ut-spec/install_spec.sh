# shellcheck shell=bash
# shellcheck disable=SC2034

# 2026-06-17 Reason: cover the YashanDB official image layout before changing install.sh; Purpose: ensure the addon can use images that contain a nested database tarball instead of pre-expanded runtime directories.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "install_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "YASDB Install Script Tests"
  Include ../scripts/install.sh

  init() {
    ut_mode="true"
    WORK_DIR="./test_work"
    YASDB_MOUNT_HOME="./test_mount"
    YASDB_HOME="./test_mount/yasdb_home"
    YASDB_DATA="./test_mount/yasdb_data"

    mkdir -p "${WORK_DIR}" "${YASDB_MOUNT_HOME}" "${YASDB_DATA}/config"
  }
  BeforeEach "init"

  cleanup() {
    rm -rf "${WORK_DIR}" "${YASDB_MOUNT_HOME}"
  }
  AfterEach "cleanup"

  Describe "setup_directories()"
    It "expands a nested official image package before copying runtime directories"
      mkdir -p "${WORK_DIR}/database/admin" "${WORK_DIR}/database/bin" "${WORK_DIR}/database/conf" "${WORK_DIR}/database/include" "${WORK_DIR}/database/java" "${WORK_DIR}/database/lib" "${WORK_DIR}/database/plug-in" "${WORK_DIR}/database/scripts"
      touch "${WORK_DIR}/database/gitmoduleversion.dat"
      tar -czf "${WORK_DIR}/database-23.4.1.109-linux-aarch64.tar.gz" -C "${WORK_DIR}/database" .
      tar -czf "${WORK_DIR}/yashandb-23.4.1.109-linux-aarch64.tar.gz" -C "${WORK_DIR}" database-23.4.1.109-linux-aarch64.tar.gz
      rm -rf "${WORK_DIR}/database" "${WORK_DIR}/database-23.4.1.109-linux-aarch64.tar.gz"

      When call setup_directories
      The status should be success
      The path "${YASDB_HOME}/bin" should be directory
      The path "${YASDB_HOME}/conf" should be directory
      The path "${YASDB_HOME}/admin" should be directory
    End
  End

  Describe "setup_install_file()"
    It "syncs rendered ConfigMap parameter changes into persisted PVC config files"
      mkdir -p ./home/yashan/kbconfigs "${YASDB_DATA}/config"
      echo "YASDB_HOME=${YASDB_HOME}" >"${YASDB_TEMP_FILE}"
      echo "YASDB_DATA=${YASDB_DATA}" >>"${YASDB_TEMP_FILE}"
      echo "RUN_LOG_LEVEL=INFO" >>"${YASDB_TEMP_FILE}"
      echo "YASDB_HOME=${YASDB_HOME}" >"${YASDB_INSTALL_FILE}"
      echo "YASDB_DATA=${YASDB_DATA}" >>"${YASDB_INSTALL_FILE}"
      echo "[instance]" >>"${YASDB_INSTALL_FILE}"
      echo "RUN_LOG_LEVEL=INFO" >>"${YASDB_INSTALL_FILE}"
      echo "RUN_LOG_LEVEL=INFO" >"${YASDB_DATA}/config/yasdb.ini"
      mkdir -p /home/yashan/kbconfigs
      echo "YASDB_HOME=${YASDB_HOME}" >/home/yashan/kbconfigs/install.ini
      echo "YASDB_DATA=${YASDB_DATA}" >>/home/yashan/kbconfigs/install.ini
      echo "[instance]" >>/home/yashan/kbconfigs/install.ini
      echo "RUN_LOG_LEVEL=WARN" >>/home/yashan/kbconfigs/install.ini

      When call setup_install_file
      The status should be success
      The contents of file "${YASDB_INSTALL_FILE}" should include "RUN_LOG_LEVEL=WARN"
      The contents of file "${YASDB_TEMP_FILE}" should include "RUN_LOG_LEVEL=WARN"
      The contents of file "${YASDB_DATA}/config/yasdb.ini" should include "RUN_LOG_LEVEL=WARN"
    End
  End
End
