#!/bin/bash
set -e
set -o pipefail

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
TMP_DIR=/tmp/zookeeper/restore
mkdir -p ${TMP_DIR}

backupFileName="${DP_BACKUP_NAME}.backup.json"
datasafed pull -d zstd-fastest "${backupFileName}" ${TMP_DIR}/backup.json

touch ${ZOOKEEPER_DATA_DIR}/.restore_new_cluster

java -cp /zoocreeper.jar  com.boundary.zoocreeper.Restore \
-z ${KB_CLUSTER_COMP_NAME}:${DP_DB_PORT}  -f ${TMP_DIR}/backup.json \
--overwrite-existing --compress --exclude /zookeeper/config*

rm -rf ${TMP_DIR}
rm -rf ${ZOOKEEPER_DATA_DIR}/.restore_new_cluster