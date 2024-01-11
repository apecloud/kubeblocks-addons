set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}
export POSTGRESQL_MASTER_HOST=$KB_0_HOSTNAME



trap handle_exit EXIT

START_TIME=`get_current_time`
echo ${DP_DB_PASSWORD} | pg_basebackup -Ft -Pv -c fast -Xf -D ${DATA_DIR}  -h ${POSTGRESQL_MASTER_HOST} -U ${DP_DB_USER} -W 

# stat and save the backup information
stat_and_save_backup_info $START_TIME