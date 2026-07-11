#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

restore_preflight() {
  local residue

  mkdir -p "${DATA_DIR}"
  if [ -f "${DATA_DIR}/.xtrabackup_restore" ]; then
    echo "Restore already completed; keeping existing data"
    return 10
  fi
  residue=$(find "${DATA_DIR}" -mindepth 1 -maxdepth 1 ! -name lost+found -print -quit)
  if [ -n "$residue" ]; then
    echo "Restore target is non-empty without completion marker: ${residue}" >&2
    return 1
  fi
}

${__SOURCED__:+false} : || return 0
restore_preflight_rc=0
restore_preflight || restore_preflight_rc=$?
[ "$restore_preflight_rc" -eq 10 ] && exit 0
[ "$restore_preflight_rc" -ne 0 ] && exit "$restore_preflight_rc"

mkdir -p ${DATA_DIR}
TMP_DIR=${MYSQL_DIR}/temp
mkdir -p ${TMP_DIR} && cd ${TMP_DIR}

xbstreamFile="${DP_BACKUP_NAME}.xbstream.zst"
if [ "$(datasafed list ${xbstreamFile})" == "${xbstreamFile}" ]; then
  datasafed pull -d zstd-fastest "${xbstreamFile}" - | xbstream -x
elif [ "$(datasafed list mysql.xbstream)" == "mysql.xbstream" ]; then
  datasafed pull "mysql.xbstream" - | xbstream -x
else
  datasafed pull "${DP_BACKUP_NAME}.xbstream" - | xbstream -x
fi
xtrabackup --decompress --remove-original --target-dir=${TMP_DIR}
xtrabackup --prepare --target-dir=${TMP_DIR}
xtrabackup --move-back --target-dir=${TMP_DIR} --datadir=${DATA_DIR}/

touch ${DATA_DIR}/.xtrabackup_restore
if [ "${BACKUP_FOR_STANDBY}" != "true" ]; then
   touch ${DATA_DIR}/.restore_new_cluster
fi
rm -rf ${TMP_DIR}
chmod -R 0777 ${DATA_DIR}
