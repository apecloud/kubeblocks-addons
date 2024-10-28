set -e;

echo "DB_HOST=${DP_DB_HOST} DB_USER=${DP_DB_USER} DB_PASSWORD=${DP_DB_PASSWORD} DATA_DIR=${DATA_DIR} BACKUP_DIR=${DP_BACKUP_DIR} BACKUP_NAME=${DP_BACKUP_NAME}";
mariadb-backup --backup  --safe-slave-backup --slave-info --stream=mbstream --host=${DP_DB_HOST} \
--user=${DP_DB_USER} --password=${DP_DB_PASSWORD} --datadir=${DATA_DIR} > ${DATASAFED_LOCAL_BACKEND_PATH}/${DP_BACKUP_NAME}.mbstream