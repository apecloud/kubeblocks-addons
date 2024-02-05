set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

mongo_uri="mongodb://${DP_DB_HOST}:${DP_DB_PORT}"

oplogFlags=""
oplogSignal="oplog.signal"
if [ "$(datasafed list ${oplogSignal})" == "${oplogSignal}" ];then
  oplogFlags="--oplogReplay"
fi
backupFile="${DP_BACKUP_NAME}.archive.zst"
if [ "$(datasafed list ${backupFile})" == "${backupFile}" ]; then
   datasafed pull -d zstd-fastest "${backupFile}" - | mongorestore --archive ${oplogFlags} --numParallelCollections=${PARALLEL} --uri "${mongo_uri}" -u ${MONGODB_ROOT_USER} -p ${MONGODB_ROOT_PASSWORD} --authenticationDatabase admin
else
   datasafed pull "${DP_BACKUP_NAME}.archive" - | mongorestore --archive --gzip --uri "${mongo_uri}" --numParallelCollections=${PARALLEL} -u ${MONGODB_ROOT_USER} -p ${MONGODB_ROOT_PASSWORD} --authenticationDatabase admin
fi

