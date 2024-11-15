#!/bin/bash
# TODO: support input password
# TODO: clear backup records in ob database
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}
noArchivedTenantsFiles="no_archived_tenants.dp"
deferArchiveLogTenantsFiles="defer_archive_tenants.dp"
endTimeInfoFile="kb_end_time.info"

mysql_cmd="mysql -u ${DP_DB_USER} -h ${DP_DB_HOST} -P${DP_DB_PORT} -p${DP_DB_PASSWORD} -N -e"
OlD_IFS=$IFS
time_zone_file="timezone.dp"

pod_ordinal=$(get_pod_ordinal ${DP_TARGET_POD_NAME})
if [[ ${pod_ordinal} -ne 0  ]]; then
    DP_log "Backups can only be performed from the first pod, except for rebuilding instance"
    exit 1
fi

function saveEndTime() {
    local minRestoreSCN=${1:?missing minRestoreSCN}
    local minRestoreTime=${2:?missing minRestoreTime}
    if [ -z ${minRestoreSCN} ]; then
      return
    fi
    if [ -f $endTimeInfoFile ]; then
       oldMinRestoreSCN=$(cat ${endTimeInfoFile} | jq -r ".minRestoreSCN" )
       [ $minRestoreSCN -gt ${oldMinRestoreSCN} ] && echo "{\"minRestoreSCN\":\"${minRestoreSCN}\",\"minRestoreTime\":\"${minRestoreTime}\"}" > ${endTimeInfoFile}
    else
       echo "{\"minRestoreSCN\":\"${minRestoreSCN}\",\"minRestoreTime\":\"${minRestoreTime}\"}" > ${endTimeInfoFile}
    fi
}

function save_defer_archivelog_tenants() {
  local tenant_id=${1:?missing tenant id}
  if [[ "${PLUS_ARCHIVELOG}" == "true" ]]; then
     # defer the archive log after backup when PLUS_ARCHIVELOG=true and it is not archive log to dest dir before this backup.
     enabled_archive_dest=`${mysql_cmd} "SELECT count(*) FROM oceanbase.CDB_OB_ARCHIVE_DEST where tenant_id='${tenant_id}' and name='state' and value='ENABLE';" | awk -F '\t' '{print}'`
     if [[ ${enabled_archive_dest} -eq 0 ]]; then
         echo "${tenant_name}" >> $deferArchiveLogTenantsFiles
     fi
  fi
}

function prepareTenantLogArchive() {
  tenant_id=${1:?missing tenant id}
  tenant_name=${2:?missing tenant name}
  log_mode=${3}
  if [[ $log_mode == "NOARCHIVELOG" ]]; then
     echo "${tenant_name}" >> $noArchivedTenantsFiles
  fi
  save_defer_archivelog_tenants "${tenant_id}"
  destUrl=$(getDestURL archive ${tenant_name} ${tenant_id})
  echo "INFO: prepare log archive dest for tenant ${tenant_name}"
  result=`${mysql_cmd} "ALTER SYSTEM SET LOG_ARCHIVE_DEST=\"LOCATION=${destUrl}\" TENANT=${tenant_name}"`
  if [[ $? -ne 0 ]];then
     echo "ERROR: alert log_archive_dest for tenant ${tenant_name} failed: ${result}"
     exit 1
  fi
  # enable dest
  echo "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE='ENABLE' TENANT=${tenant_name};"
  ${mysql_cmd} "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE='ENABLE' TENANT=${tenant_name};"
  # add recovery window to auto-clean backup.
  #deletePolicyCount=`${mysql_cmd} "SELECT count(*) FROM oceanbase.CDB_OB_BACKUP_DELETE_POLICY where TENANT_ID=${tenant_id};" |awk -F '\t' '{print}'`
  #if [ $deletePolicyCount -eq 0 ]; then
  #   echo "INFO: config recovery window '7d' for tenant ${tenant_name}."
  #   ${mysql_cmd} "ALTER SYSTEM ADD DELETE BACKUP POLICY 'default' RECOVERY_WINDOW '7d' TENANT ${tenant_name};"
  #fi
}

function prepareTenantDataBackup() {
  tenant_name=${1:?missing tenant name}
  destUrl=$(getDestURL data ${tenant_name})
  echo "INFO: prepare data backup dest for tenant ${tenant_name}"
  result=`${mysql_cmd} "ALTER SYSTEM SET DATA_BACKUP_DEST=\"${destUrl}\" TENANT=${tenant_name}"`
  if [[ $? -ne 0 ]];then
     echo "ERROR: alert data_backup_dest for tenant ${tenant_name} failed: ${result}"
     exit 1
  fi
}

function saveUnitCreateStatement(){
  ${mysql_cmd} "SELECT NAME,MAX_CPU,MIN_CPU,MEMORY_SIZE,LOG_DISK_SIZE,MAX_IOPS,MIN_IOPS,IOPS_WEIGHT FROM oceanbase.DBA_OB_UNIT_CONFIGS;" | while IFS=$'\t' read -a row; do
     IFS=${OlD_IFS}
     echo "create resource unit if not exists ${row[0]} MAX_CPU=${row[1]}, MIN_CPU=${row[2]}, MEMORY_SIZE=${row[3]}, LOG_DISK_SIZE=${row[4]}, MAX_IOPS=${row[5]}, MIN_IOPS=${row[6]}, IOPS_WEIGHT=${row[7]};" >> ${unitSQLFile}
  done
}

function covertStringToOBArray() {
  local str=${1}
  IFS=';'
  read -ra array <<< "$str"
  IFS=${OlD_IFS}
  val=""
  for e in "${array[@]}"; do
      if [[ ! -z ${val} ]]; then
        val="${val},"
      fi
      val="${val}'${e}'"
  done
  echo "($val)"
}

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
  exit_code=$?
  if [ -f ${deferArchiveLogTenantsFiles} ]; then
     IFS=$'\n'
     for tenant_name in `cat ${deferArchiveLogTenantsFiles}`; do
       IFS=${OlD_IFS}
       if [[ ! -z $tenant_name ]]; then
         echo "INFO: defer ${tenant_name} to archive logs"
         ${mysql_cmd} "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE='DEFER' TENANT = ${tenant_name};"
       fi
     done
  fi
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

trap handle_exit EXIT

# step 1===> prepare for data and archive backup
# analysisToolConfig first
DP_log "analysis tool config"
analysisToolConfig

${mysql_cmd} "SELECT tenant_id, tenant_name,log_mode FROM oceanbase.DBA_OB_TENANTS where tenant_type='user' and status='NORMAL';" | while IFS=$'\t' read -a row; do
  IFS=${OlD_IFS}
  tenant_id=${row[0]}
  tenant_name=${row[1]}
  # prepare tenant log archive dest
  status=`${mysql_cmd} "SELECT status FROM oceanbase.CDB_OB_ARCHIVELOG where tenant_id=${tenant_id};" |awk -F '\t' '{print}'`
  if [[ "${status}" == "INTERRUPTED" ]]; then
     DP_log "try to recovery archive from INTERRUPTED..."
     ${mysql_cmd} "ALTER SYSTEM NOARCHIVELOG TENANT=${tenant_name};"
     # wait to stop archive process.
     sleep 30
     ${mysql_cmd} "ALTER SYSTEM ARCHIVELOG TENANT=${tenant_name};"
  elif [[ -z "${status}" ]] || [[ "${status}" == "STOP" ]]; then
      # only prepare the tenant which not doing archive.
      prepareTenantLogArchive ${tenant_id} $tenant_name ${row[2]}
  elif [[ "${status}" == "SUSPEND" ]]; then
      save_defer_archivelog_tenants "${tenant_id}"
      echo "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE='ENABLE' TENANT=${tenant_name};"
      ${mysql_cmd} "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE='ENABLE' TENANT=${tenant_name};"
  fi
  # prepare tenant data backup test
  prepareTenantDataBackup $tenant_name
done


# step 2===> start log archive
sql="ALTER SYSTEM ARCHIVELOG TENANT=ALL;"
echo "INFO: ${sql}"
${mysql_cmd} "${sql}"
sleep 1


# step 3===> wait for archive job state is DOING
time=0
tenantCount=`${mysql_cmd} "SELECT count(*) FROM oceanbase.DBA_OB_TENANTS where tenant_type='user' and status='NORMAL';" | awk -F '\t' '{print}'`
until [ $(${mysql_cmd} "SELECT count(*) FROM oceanbase.CDB_OB_ARCHIVELOG where status='DOING';" | awk -F '\t' '{print}') -eq ${tenantCount} ]; do
    echo "INFO: wait for all tenants to archiving logs..."
    if [[ $time -gt 300 ]];then
       echo 'ERROR: timed out for all tenants to archiving logs, you can show message with sql "SELECT * FROM oceanbase.CDB_OB_ARCHIVELOG"'
       exit 1
    fi
    sleep 3
done

if [[ $tenantCount -eq 0 ]]; then
   echo "INFO: no normal tenants exists."
   echo "{}" >"${DP_BACKUP_INFO_FILE}"
   exit 0
fi

# step 4===> do data backup
START_TIME=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
sql="ALTER SYSTEM BACKUP DATABASE;"
if [[ "${PLUS_ARCHIVELOG}" == "true" ]]; then
  sql="ALTER SYSTEM BACKUP DATABASE PLUS ARCHIVELOG;"
fi
echo "INFO: ${sql}"
${mysql_cmd} "${sql}"
sleep 3


# step 5===> wait for all backup jobs completed.
initiator_job_id=$(${mysql_cmd} "SELECT INITIATOR_JOB_ID FROM oceanbase.CDB_OB_BACKUP_JOBS where JOB_LEVEL='CLUSTER' limit 1;" | awk -F '\t' '{print}')
while true; do
  res=$(${mysql_cmd} "SELECT count(*) FROM oceanbase.CDB_OB_BACKUP_JOBS where JOB_LEVEL='USER_TENANT';" | awk -F '\t' '{print}')
  if [[ res -eq 0 ]];then
    break
  fi
  echo "INFO: wait for backup data completed, uncompleted job count: ${res}"
  sleep 10
done
echo "INFO: backup data completed."
sleep 5

# step 5 ==> close tenant archive if the tenant not open the log archive.
if [[ -f $noArchivedTenantsFiles ]]; then
   IFS=$'\n'
   for tenant_name in `cat $noArchivedTenantsFiles`; do
     IFS=${OlD_IFS}
     if [[ ! -z $tenant_name ]]; then
       echo "INFO: start to close ${tenant_name} archive"
       ${mysql_cmd} "ALTER SYSTEM NOARCHIVELOG TENANT=${tenant_name}"
     fi
   done
fi


# step 6===> check if backup jobs are successful and collect backup info for restore.
tenantFile="tenantStatus.dp"
unitSQLFile="create_unit.sql"
resourcePoolSQLFile="create_resource_pool.sql"
# save unit create statement to tmp file
saveUnitCreateStatement
echo "INFO: start to save status"
${mysql_cmd} "select tenant_id, backup_set_id from oceanbase.CDB_OB_BACKUP_JOB_HISTORY where initiator_job_id=${initiator_job_id} and backup_set_id !=0;" | while IFS=$'\t' read -a row; do
    IFS=${OlD_IFS}
    tenant_id=${row[0]}
    backup_set_id=${row[1]}
    ${mysql_cmd} "select d.tenant_name, d.tenant_id, d.COMPATIBILITY_MODE, t.START_REPLAY_SCN, t.START_REPLAY_SCN_DISPLAY, t.MIN_RESTORE_SCN, t.MIN_RESTORE_SCN_DISPLAY, t.STATUS, t.RESULT, t.COMMENT FROM oceanbase.CDB_OB_BACKUP_SET_FILES t, oceanbase.DBA_OB_TENANTS d where t.tenant_id = d.tenant_id and t.BACKUP_SET_ID=${backup_set_id} and t.tenant_id=${tenant_id};" | while IFS=$'\t' read -a res; do
      echo "INFO: collect backup info for tenant ${res[0]}"
      IFS=${OlD_IFS}
      tenantName=${res[0]}
      mode=${res[2]}
      tenantJson=""
      tenantJson=$(buildJsonString "$tenantJson" "name" $tenantName)
      tenantJson=$(buildJsonString "$tenantJson" "tenantId" "${res[1]}")
      tenantJson=$(buildJsonString "$tenantJson" "mode" "${mode}")
      tenantJson=$(buildJsonString "$tenantJson" "archivePath" "$(getArchiveDestPath)")
      tenantJson=$(buildJsonString "$tenantJson" "startReplaySCN" ${res[3]})
      tenantJson=$(buildJsonString "$tenantJson" "startReplaySCNTIME" "${res[4]}")
      tenantJson=$(buildJsonString "$tenantJson" "minRestoreSCN" ${res[5]})
      tenantJson=$(buildJsonString "$tenantJson" "minRestoreTime" "${res[6]}")
      status=${res[7]}
      if [[ $status -ne "SUCCESS" ]];then
          tenantJson=$(buildJsonString "$tenantJson" "failureMessage" "${res[8]}: ${res[9]}")
      fi
      # record time zone
      userName="root"
      timezone_sql="select @@time_zone;"
      mysql_tenant_cmd="mysql -u ${userName}@${tenantName} -h ${DP_DB_HOST} -P${DP_DB_PORT} -N -e"
      # get time zone
      timeZone=$(${mysql_tenant_cmd} "${timezone_sql}")
      echo $(getTimeZoneOffset "${timeZone}") > ${time_zone_file}
      # records the resources pool list
      pool_list=""
      for resourceName in `${mysql_cmd} "SELECT name FROM oceanbase.DBA_OB_RESOURCE_POOLS where TENANT_ID=${tenant_id};" | awk -F '' '{print}'`; do
        if [[ ! -z $pool_list ]];then
            pool_list="${pool_list},"
        fi
        pool_list="${pool_list}${resourceName}"
      done
      tenantJson=$(buildJsonString "$tenantJson" "poolList" "${pool_list}")
      echo "{${tenantJson}}" >> ${tenantFile}
      saveEndTime "${res[5]}" "${res[6]}"
    done

    ${mysql_cmd} "SELECT r.name, u.name as unit_name, r.unit_count, r.zone_list FROM oceanbase.DBA_OB_RESOURCE_POOLS r, oceanbase.DBA_OB_UNIT_CONFIGS u where u.UNIT_CONFIG_ID = r.UNIT_CONFIG_ID and r.TENANT_ID=${tenant_id};" | while IFS=$'\t' read -a pool; do
       IFS=${OlD_IFS}
       echo "create resource pool if not exists ${pool[0]} UNIT=${pool[1]}, UNIT_NUM=${pool[2]}, ZONE_LIST=$(covertStringToOBArray ${pool[3]});" >> ${resourcePoolSQLFile}
    done
done


# step 7===> get extras infos
extras=""
while IFS= read -r line; do
  IFS=$OlD_IFS
  if [ ! -z "${extras}" ];then
     extras="${extras},"
  fi
  extras="${extras}${line}"
done < ${tenantFile}

# get stop time
STOP_TIME=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
if [ -f ${endTimeInfoFile} ]; then
   stop_scn=$(cat ${endTimeInfoFile} | jq -r ".minRestoreSCN")
   if [ "${stop_scn}" != "NULL" ]; then
      stop_timestamp=$((${stop_scn}/1000000000))
      STOP_TIME=$(date -d @$stop_timestamp -u "+%Y-%m-%dT%H:%M:%SZ")
   fi
fi

# step 8===> save tenants info for restore and backup status
datasafed push ${unitSQLFile} "/${unitSQLFile}"
datasafed push ${resourcePoolSQLFile} "/${resourcePoolSQLFile}"
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
if [ -f ${time_zone_file} ]; then
  timeZone=$(cat ${time_zone_file})
fi
backupInfo="{\"totalSize\":\"$TOTAL_SIZE\",\"extras\":[${extras}],\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\",\"timeZone\":\"${timeZone}\"}}"
echo ${backupInfo}
echo ${backupInfo} >"${DP_BACKUP_INFO_FILE}"
if [[ $extras == *"failureMessage"* ]];then
   echo "ERROR: backup data failed: $extras"
   exit 1
fi