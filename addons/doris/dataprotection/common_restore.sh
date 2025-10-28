export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

DP_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} INFO: $msg"
}


function download_backups() {
   local backup_name=${1:-${DP_BACKUP_NAME}}
   local target_path=${BACKUP_DIR}/INIT_BACKUPS/${backup_name}
   mkdir -p ${target_path}
   datasafed pull -d zstd-fastest "${backup_name}.tar.zst" - | tar -xvf - -C ${target_path}

   echo "" > ${BACKUP_DIR}/.restore
}

# download_backups
# cd 
# datasafed pull -d zstd-fastest "${backupFile}" - | tar -xvf - -C ${DATA_DIR}

# CREATE REPOSITORY `APE_kb10-5cd4db689c-minio` WITH S3 ON LOCATION "s3://kb-backup" PROPERTIES ("s3.endpoint" = " http://kb10-5cd4db689c-minio.kb-system.svc.cluster.local:9000 ", "s3.access_key" = "root", "s3.secret_key" = "6Zn98rv0YOej9970", "s3.region" = "dummy-region", "use_path_style" = "true");