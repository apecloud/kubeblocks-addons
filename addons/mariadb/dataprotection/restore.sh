echo "BACKUP_DIR=${DP_BACKUP_BASE_PATH} BACKUP_NAME=${DP_BACKUP_NAME} DATA_DIR=${DATA_DIR}" && \
mkdir -p /tmp/data/ && cd /tmp/data \
&& mbstream -x < /backupdata/${DP_BACKUP_NAME}.mbstream \
&& mariadb-backup --prepare --target-dir=/tmp/data/ \
&& mariadb-backup --copy-back --target-dir=/tmp/data/ \
&& find . -name "*.qp"|xargs rm -f \
&& rm -rf ${DATA_DIR}/* \
&& rsync -avrP /tmp/data/ ${DATA_DIR}/ \
&& rm -rf /tmp/data/ \
&& chmod -R 0777 ${DATA_DIR}