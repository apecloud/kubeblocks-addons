# shellcheck shell=bash
# use datasafed and default config
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

if ! recovery_target_time=$(date -d "@${DP_RESTORE_TIMESTAMP}" '+%F %T%::z'); then
  DP_error_log "failed to format PITR recovery timestamp ${DP_RESTORE_TIMESTAMP}"
  exit 1
fi

if [[ -d ${DATA_DIR}.old ]] && [[ -d ${DATA_DIR} ]]; then
  DP_error_log "both ${DATA_DIR} and ${DATA_DIR}.old exist; refusing ambiguous PITR handoff"
  exit 1
fi

if [[ -d ${DATA_DIR}.old ]] && [[ ! -d ${DATA_DIR} ]]; then
  # A previous run already completed the final staging mv. Un-staging and
  # exiting 0 here (the old behavior) left a populated DATA_DIR carrying
  # recovery.signal but no bootstrap: Patroni adopted the directory and
  # postgres crash-looped on a missing restore_command. Move the data back
  # and RE-RUN the whole preparation instead — the WAL re-fetch and config
  # rewrite below are idempotent and the script ends by staging again.
  mv ${DATA_DIR}.old ${DATA_DIR}
fi

mkdir -p ${PITR_DIR};

start_wal_log=$(ls "${DATA_DIR}/pg_wal" -lI "*.history" | grep '^-' | awk '{print $9}' | grep -E '^[0-9A-F]{24}$' | sort | tail -n 1)
if [[ -z ${start_wal_log} ]]; then
  DP_error_log "failed to find a valid starting WAL in ${DATA_DIR}/pg_wal"
  exit 1
fi

DP_log "fetch-wal-log ${PITR_DIR} ${start_wal_log} \"${DP_RESTORE_TIME}\" true"
fetch-wal-log ${PITR_DIR} ${start_wal_log} "${DP_RESTORE_TIME}" true

chmod 777 -R ${PITR_DIR};
touch ${DATA_DIR}/recovery.signal;
mkdir -p ${CONF_DIR};
chmod 777 -R ${CONF_DIR};
mkdir -p ${RESTORE_SCRIPT_DIR};
echo "#!/bin/bash" > ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
echo "[[ -d '${DATA_DIR}.old' ]] && mv -f ${DATA_DIR}.old/* ${DATA_DIR}/;" >> ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
echo "sync;" >> ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
chmod +x ${RESTORE_SCRIPT_DIR}/kb_restore.sh;
cat << EOF > "${CONF_DIR}/recovery.conf"
restore_command='cp ${PITR_DIR}/%f %p'
recovery_target_time='${recovery_target_time}'
recovery_target_action='promote'
recovery_target_timeline='latest'
EOF
mv ${DATA_DIR} ${DATA_DIR}.old;
DP_log "done.";
sync;
