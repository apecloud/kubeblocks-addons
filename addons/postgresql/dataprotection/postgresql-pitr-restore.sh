# use datasafed and default config
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

if [[ -d ${DATA_DIR}.old ]] && [[ ! -d ${DATA_DIR} ]]; then
  # if dataDir.old exists but dataDir not exits, retry it
  mv ${DATA_DIR}.old ${DATA_DIR}
  exit 0;
fi

mkdir -p ${PITR_DIR};

latest_wal=$(ls ${DATA_DIR}/pg_wal -lI "*.history" | grep ^- | awk '{print $9}' | sort | tail -n 1)
start_wal_log=`basename $latest_wal`

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
echo "restore_command='case "%f" in *history) cp ${PITR_DIR}/%f %p ;; *) mv ${PITR_DIR}/%f %p ;; esac'" > ${CONF_DIR}/recovery.conf;
echo "recovery_target_time='${DP_RESTORE_TIME}'" >> ${CONF_DIR}/recovery.conf;
echo "recovery_target_action='promote'" >> ${CONF_DIR}/recovery.conf;
echo "recovery_target_timeline='latest'" >> ${CONF_DIR}/recovery.conf;
mv ${DATA_DIR} ${DATA_DIR}.old;
DP_log "done.";
sync;