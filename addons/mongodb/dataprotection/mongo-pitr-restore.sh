#!/bin/bash
export MONGODB_URI="mongodb://${MONGODB_ROOT_USER}:${MONGODB_ROOT_PASSWORD}@${DP_DB_HOST}:${DP_DB_PORT}/?authSource=admin&replicaSet=${CLUSTER_COMPONENT_NAME}"
# use datasafed and default config
export WALG_DATASAFED_CONFIG=""
export WALG_COMPRESSION_METHOD=zstd
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

export CLIENT=`which mongosh ||echo mongo`
command="$CLIENT admin -u ${MONGODB_ROOT_USER} -p ${MONGODB_ROOT_PASSWORD} --port ${DP_DB_PORT} --host ${DP_DB_HOST} --authenticationDatabase admin --quiet --eval"

DP_log "grant apply op role"
${command} 'db.createRole({role: "internalUseOnlyOplogRestore", privileges:[{resource: {anyResource:true}, actions: ["anyAction"]}],roles: []});db.grantRolesToUser("root",[{role: "internalUseOnlyOplogRestore",db: "admin" }]);'

DP_log "wal-g oplog-replay ${DP_BASE_BACKUP_START_TIMESTAMP}.1 ${DP_RESTORE_TIMESTAMP}.1"
wal-g oplog-replay ${DP_BASE_BACKUP_START_TIMESTAMP}.1 ${DP_RESTORE_TIMESTAMP}.1

DP_log "revoke apply op role"
${command} 'db.revokeRolesFromUser("root",[{role: "internalUseOnlyOplogRestore",db: "admin" }]);'