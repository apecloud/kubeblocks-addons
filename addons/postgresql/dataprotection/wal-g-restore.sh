set -e
dirPath=$(dirname ${DP_BACKUP_BASE_PATH})
backupRepo=$(dirname ${dirPath})
export WALG_DATASAFED_CONFIG=""
export WALG_COMPRESSION_METHOD=zstd
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
# 20Gi for bundle file
export WALG_TAR_SIZE_THRESHOLD=21474836480
export DATASAFED_BACKEND_BASE_PATH="${backupRepo}"

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
}

# 1. fetch base backup
mkdir -p ${DATA_DIR};
wal-g backup-fetch ${DATA_DIR} LATEST

# 2. config restore script
touch ${DATA_DIR}/recovery.signal;
mkdir -p ${RESTORE_SCRIPT_DIR};
echo "#!/bin/bash" > ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
echo "[[ -d '${DATA_DIR}.old' ]] && mv -f ${DATA_DIR}.old/* ${DATA_DIR}/;" >> ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
echo "sync;" >> ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
chmod +x ${RESTORE_SCRIPT_DIR}/kb_restore.sh;

# 3. config wal-g to fetch wal logs
config_wal_g_for_fetch_wal_log "${backupRepo}"

# 4. config restore command
mkdir -p ${CONF_DIR} && chmod 777 -R ${CONF_DIR};
echo "restore_command='envdir /home/postgres/pgdata/wal-g/restore-env /home/postgres/pgdata/wal-g/wal-g wal-fetch %f %p'" > ${CONF_DIR}/recovery.conf;
if [[ ! -z ${DP_RESTORE_TIME} ]]; then
   echo "recovery_target_time='${DP_RESTORE_TIME}'" >> ${CONF_DIR}/recovery.conf;
   echo "recovery_target_action='promote'" >> ${CONF_DIR}/recovery.conf;
   echo "recovery_target_timeline='latest'" >> ${CONF_DIR}/recovery.conf;
fi
# this step is necessary, data dir must be empty for patroni
mv ${DATA_DIR} ${DATA_DIR}.old
sync