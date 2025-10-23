#!/bin/bash
#
# Refer: https://github.com/wal-g/wal-g/blob/master/docs/MySQL.md#mysql---using-with-xtrabackup
#
# export wal-g environments
export WALG_MYSQL_DATASOURCE_NAME="${MYSQL_ADMIN_USER}:${MYSQL_ADMIN_PASSWORD}@tcp(${DP_DB_HOST}:${DP_DB_PORT})/mysql"
export WALG_COMPRESSION_METHOD=zstd
# use datasafed and default config
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export WALG_MYSQL_CHECK_GTIDS=true
export MYSQL_PWD=${MYSQL_ADMIN_PASSWORD}
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export WALG_MYSQL_BINLOG_DST=${PITR_DIR}
export WALG_MYSQL_BINLOG_REPLAY_COMMAND="mysqlbinlog --stop-datetime=\"\$WALG_MYSQL_BINLOG_END_TS\" \"\$WALG_MYSQL_CURRENT_BINLOG\" | mysql -u ${MYSQL_ADMIN_USER} -h ${DP_DB_HOST}"

# If pitr logs dir exists, it may be created by previous failed restore.
if [ -d "$WALG_MYSQL_BINLOG_DST" ]; then
    DP_log "pitr logs dir $WALG_MYSQL_BINLOG_DST exists, may be created by previous failed restore, exit"
    exit 1
fi

DP_log "mkdir -p $WALG_MYSQL_BINLOG_DST"
mkdir -p "$WALG_MYSQL_BINLOG_DST"

DP_log "wal-g binlog-replay --since-time=${DP_BASE_BACKUP_START_TIME} --until=${DP_RESTORE_TIME}"
wal-g binlog-replay --since-time="${DP_BASE_BACKUP_START_TIME}" --until="${DP_RESTORE_TIME}"
echo "mysql binlog replay done."