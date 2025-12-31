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
    if [ -n "${DATASAFED_ENCRYPTION_ALGORITHM}" ]; then
      echo "${DATASAFED_ENCRYPTION_ALGORITHM}" > ${walg_env}/DATASAFED_ENCRYPTION_ALGORITHM
    elif [ -f ${walg_env}/DATASAFED_ENCRYPTION_ALGORITHM ]; then
       rm ${walg_env}/DATASAFED_ENCRYPTION_ALGORITHM
    fi
    if [ -n "${DATASAFED_ENCRYPTION_PASS_PHRASE}" ]; then
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
# Create recovery signal file for PostgreSQL
touch ${DATA_DIR}/recovery.signal

# Prepare restore script directory
mkdir -p ${RESTORE_SCRIPT_DIR}
chmod 777 -R ${RESTORE_SCRIPT_DIR}
touch ${RESTORE_SCRIPT_DIR}/kb_restore.signal

# Generate kb_restore.sh script that Patroni will execute
cat > ${RESTORE_SCRIPT_DIR}/kb_restore.sh << 'EOF'
#!/bin/bash
set -e

# This script is executed by Patroni to finalize the restore process
# Usage: kb_restore.sh [--replica]
#   --replica: Indicates this is for replica creation, will skip restore and use basebackup

# Parse command line arguments
IS_REPLICA=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --replica)
            IS_REPLICA=true
            shift
            ;;
        *)
            # Unknown argument, skip it and continue
            shift
            ;;
    esac
done

# If this is for replica creation, clean up and let Patroni use basebackup
if [[ "${IS_REPLICA}" == "true" ]]; then
    echo "Replica creation detected, cleaning up restored data..."

    # Remove the restored data directory
    if [[ -d "${DATA_DIR}.old" ]]; then
        echo "Removing ${DATA_DIR}.old..."
        rm -rf ${DATA_DIR}.old
    fi

    # Remove restore signal
    if [[ -f "${RESTORE_SCRIPT_DIR}/kb_restore.signal" ]]; then
        rm -rf ${RESTORE_SCRIPT_DIR}/kb_restore.signal
    fi

    echo "Cleanup completed. Patroni will use basebackup to create replica from primary."
    # Return non-zero to signal Patroni to fall back to basebackup
    exit 1
fi

# Primary restore: Restore from successful backup (.old directory exists)
if [[ -d "${DATA_DIR}.old" ]] && [[ ! -d "${DATA_DIR}.failed" ]]; then
    echo "Restoring data from ${DATA_DIR}.old..."
    mkdir -p "${DATA_DIR}"
    mv -f ${DATA_DIR}.old/* ${DATA_DIR}/
    rm -rf ${RESTORE_SCRIPT_DIR}/kb_restore.signal
    echo "Data restore completed successfully"
fi

# Recover from failed restore attempt (.failed directory exists)
if [[ -d "${DATA_DIR}.failed" ]]; then
    echo "Recovering from failed restore..."
    mkdir -p ${DATA_DIR}/
    mv -f ${DATA_DIR}.failed/* ${DATA_DIR}/
    rm -rf ${RESTORE_SCRIPT_DIR}/kb_restore.signal
    rm -rf ${DATA_DIR}/recovery.signal
    echo "Failed restore recovery completed"
fi

sync
EOF

# Replace variables in the generated script
sed -i "s|\${DATA_DIR}|${DATA_DIR}|g" ${RESTORE_SCRIPT_DIR}/kb_restore.sh
sed -i "s|\${RESTORE_SCRIPT_DIR}|${RESTORE_SCRIPT_DIR}|g" ${RESTORE_SCRIPT_DIR}/kb_restore.sh
chmod +x ${RESTORE_SCRIPT_DIR}/kb_restore.sh

# 4. config wal-g to fetch wal logs
config_wal_g_for_fetch_wal_log "${backupRepoPath}"

# 5. config restore command
# Create recovery.conf for PostgreSQL PITR
mkdir -p ${CONF_DIR}
chmod 777 -R ${CONF_DIR}

WALG_DIR=/home/postgres/pgdata/wal-g
restore_command_str="envdir ${WALG_DIR}/restore-env ${WALG_DIR}/wal-g wal-fetch %f %p >> ${RESTORE_SCRIPT_DIR}/wal-g.log 2>&1"

cat << EOF > "${CONF_DIR}/recovery.conf"
restore_command='${restore_command_str}'
recovery_target='immediate'
recovery_target_action='promote'
EOF

# 6. Rename data directory (required by Patroni bootstrap)
# Patroni expects an empty data directory, so we move the restored data to .old
# The kb_restore.sh script will move it back during bootstrap
mv ${DATA_DIR} ${DATA_DIR}.old
sync
