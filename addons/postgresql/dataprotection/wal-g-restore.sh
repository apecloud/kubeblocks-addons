#!/bin/bash
set -e
export WALG_DATASAFED_CONFIG=""
export WALG_COMPRESSION_METHOD=zstd
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
# 20Gi for bundle file
export WALG_TAR_SIZE_THRESHOLD=21474836480
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function getWalGSentinelInfo() {
  local sentinelFile=${1}
  local out=$(datasafed list ${sentinelFile})
  if [ "${out}" == "${sentinelFile}" ]; then
     datasafed pull "${sentinelFile}" ${sentinelFile}
     echo "$(cat ${sentinelFile})"
     return
  fi
}

function config_wal_g_for_fetch_wal_log() {
    walg_dir=${VOLUME_DATA_DIR}/wal-g
    walg_env=${walg_dir}/restore-env
    mkdir -p ${walg_dir}/restore-env
    cp /etc/datasafed/datasafed.conf ${walg_dir}/datasafed.conf
    cp /usr/bin/wal-g ${walg_dir}/wal-g
    datasafed_base_path=${1:?missing datasafed_base_path}
    # config wal-g env
    # config WALG_PG_WAL_SIZE with wal_segment_size which fetched by psql
    # echo "" > ${walg_env}/WALG_PG_WAL_SIZE
    echo "${walg_dir}/datasafed.conf" > ${walg_env}/WALG_DATASAFED_CONFIG
    echo "${datasafed_base_path}" > ${walg_env}/DATASAFED_BACKEND_BASE_PATH
    echo "zstd" > ${walg_env}/WALG_COMPRESSION_METHOD
    if [ -n ${DATASAFED_ENCRYPTION_ALGORITHM} ]; then
      echo "${DATASAFED_ENCRYPTION_ALGORITHM}" > ${walg_env}/DATASAFED_ENCRYPTION_ALGORITHM
    elif [ -f ${walg_env}/DATASAFED_ENCRYPTION_ALGORITHM ]; then
       rm ${walg_env}/DATASAFED_ENCRYPTION_ALGORITHM
    fi
    if [ -n ${DATASAFED_ENCRYPTION_PASS_PHRASE} ]; then
       echo "${DATASAFED_ENCRYPTION_PASS_PHRASE}" > ${walg_env}/DATASAFED_ENCRYPTION_PASS_PHRASE
    elif [ -f ${walg_env}/DATASAFED_ENCRYPTION_PASS_PHRASE ]; then
       rm ${walg_env}/DATASAFED_ENCRYPTION_PASS_PHRASE
    fi
}

# 1. get restore info
backupRepoPath=$(getWalGSentinelInfo "wal-g-backup-repo.path")
backupName=$(getWalGSentinelInfo "wal-g-backup-name")

# 2. fetch base backup
export DATASAFED_BACKEND_BASE_PATH="${backupRepoPath}"
mkdir -p ${DATA_DIR};
wal-g backup-fetch ${DATA_DIR} ${backupName}

# if restore timestamp is specified, skip restore wal logs
if [ ! -z "${DP_RESTORE_TIMESTAMP}" ]; then
   exit 0
fi
# 3. config restore script
touch ${DATA_DIR}/recovery.signal;
mkdir -p ${RESTORE_SCRIPT_DIR} && chmod 777 -R ${RESTORE_SCRIPT_DIR} && touch ${RESTORE_SCRIPT_DIR}/kb_restore.signal;
echo "#!/bin/bash" > ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
echo "[[ -d '${DATA_DIR}.old' ]] && [[ ! -d '${DATA_DIR}.failed' ]] && mv -f ${DATA_DIR}.old/* ${DATA_DIR}/ && rm -rf ${RESTORE_SCRIPT_DIR}/kb_restore.signal;" >> ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
echo "[[ -d '${DATA_DIR}.failed' ]] && mkdir -p ${DATA_DIR}/ && mv -f ${DATA_DIR}.failed/* ${DATA_DIR}/ && rm -rf ${RESTORE_SCRIPT_DIR}/kb_restore.signal && rm -rf ${DATA_DIR}/recovery.signal;" >> ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
echo "sync;" >> ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
chmod +x ${RESTORE_SCRIPT_DIR}/kb_restore.sh;

# 4. config wal-g to fetch wal logs
config_wal_g_for_fetch_wal_log "${backupRepoPath}"

# 5. config restore command
mkdir -p ${CONF_DIR} && chmod 777 -R ${CONF_DIR};
WALG_DIR=/home/postgres/pgdata/wal-g

restore_command_str="envdir ${WALG_DIR}/restore-env ${WALG_DIR}/wal-g wal-fetch %f %p >> ${RESTORE_SCRIPT_DIR}/wal-g.log 2>&1"
cat << EOF > "${CONF_DIR}/recovery.conf"
restore_command='${restore_command_str}'
recovery_target='immediate'
recovery_target_action='promote'
EOF
# this step is necessary, data dir must be empty for patroni
mv ${DATA_DIR} ${DATA_DIR}.old
sync
