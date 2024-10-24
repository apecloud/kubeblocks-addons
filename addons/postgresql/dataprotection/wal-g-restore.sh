# shellcheck disable=SC2148

postgres_log_dir="${VOLUME_DATA_DIR}/logs"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
mkdir -p "$postgres_log_dir"
chmod -R +777 "$postgres_log_dir"
touch "$postgres_scripts_log_file"
chmod 666 "$postgres_scripts_log_file"

setup_logging WALG_RESTORE "${postgres_scripts_log_file}"

set -e
export WALG_DATASAFED_CONFIG=""
export WALG_COMPRESSION_METHOD=zstd
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
# 20Gi for bundle file
export WALG_TAR_SIZE_THRESHOLD=21474836480
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function getWalGSentinelInfo() {
    local sentinelFile
    local out

    sentinelFile=$1
    out=$(datasafed list "${sentinelFile}")
    if [ "${out}" == "${sentinelFile}" ]; then
       datasafed pull "${sentinelFile}" "${sentinelFile}"
       cat "${sentinelFile}"
       return
    fi
}

function config_wal_g_for_fetch_wal_log() {
    local walg_dir
    local walg_env
    local datasafed_base_path

    walg_dir="${VOLUME_DATA_DIR}/wal-g"
    walg_env="${walg_dir}/restore-env"
    mkdir -p "${walg_env}"
    cp /etc/datasafed/datasafed.conf "${walg_dir}/datasafed.conf"
    cp /usr/bin/wal-g "${walg_dir}/wal-g"
    datasafed_base_path=${1:?missing datasafed_base_path}
    # config wal-g env
    # config WALG_PG_WAL_SIZE with wal_segment_size which fetched by psql
    # echo "" > ${walg_env}/WALG_PG_WAL_SIZE
    echo "${walg_dir}/datasafed.conf" > "${walg_env}/WALG_DATASAFED_CONFIG"
    echo "${datasafed_base_path}" > "${walg_env}/DATASAFED_BACKEND_BASE_PATH"
    echo "zstd" > "${walg_env}/WALG_COMPRESSION_METHOD"
}

# 1. get restore info
backupRepoPath=$(getWalGSentinelInfo "wal-g-backup-repo.path")
backupName=$(getWalGSentinelInfo "wal-g-backup-name")

# 2. fetch base backup
export DATASAFED_BACKEND_BASE_PATH="${backupRepoPath}"
mkdir -p "${DATA_DIR}";
echo "WAL-G fetching full backup '${backupName}': BEGIN"
wal-g backup-fetch "${DATA_DIR}" "${backupName}"
echo "WAL-G fetching full backup '${backupName}': DONE"

# 3. config restore script
echo "configure restore script"
touch "${DATA_DIR}/recovery.signal";
mkdir -p "${RESTORE_SCRIPT_DIR}" && chmod 777 -R "${RESTORE_SCRIPT_DIR}";
echo "#!/bin/bash" > "${RESTORE_SCRIPT_DIR}/kb_restore.sh";
echo "[[ -d '${DATA_DIR}.old' ]] && mv -f ${DATA_DIR}.old/* ${DATA_DIR}/;" >> "${RESTORE_SCRIPT_DIR}/kb_restore.sh";
echo "sync;" >> "${RESTORE_SCRIPT_DIR}/kb_restore.sh";
chmod +x "${RESTORE_SCRIPT_DIR}/kb_restore.sh";

# 4. config wal-g to fetch wal logs
echo "configure wal-g to fetch WAL log"
config_wal_g_for_fetch_wal_log "${backupRepoPath}"

# 5. config restore command
mkdir -p "${CONF_DIR}" && chmod 777 -R "${CONF_DIR}";

restore_command_str="/kb-scripts/wal-g-wal-restore.sh %f %p"
if [[ -n "${DP_RESTORE_TIMESTAMP}" ]]; then
    cat << EOF > "${CONF_DIR}/recovery.conf"
restore_command='${restore_command_str}'
recovery_target_time='$( date -d "@${DP_RESTORE_TIMESTAMP}" '+%F %T%::z' )'
recovery_target_action='promote'
recovery_target_timeline='latest'
EOF
else
    cat << EOF > "${CONF_DIR}/recovery.conf"
restore_command='${restore_command_str}'
recovery_target='immediate'
recovery_target_action='promote'
EOF
fi
# this step is necessary, data dir must be empty for patroni
mv "${DATA_DIR}" "${DATA_DIR}.old"
echo "restore data from full backup DONE"
sync
