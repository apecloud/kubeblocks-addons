set -e
# TODO: support input password
# TODO: clear backup records in ob database
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}
mysql_cmd="mysql -u root -h ${DP_DB_HOST} -P2881 -N -e"
OlD_IFS=$IFS

provider=
access_key_id=
secret_access_key=
region=
endpoint=
bucket=

function getToolConfigValue() {
    local line=${1}
    value=${line#*=}
    echo $(eval echo $value)
}

function analysisToolConfig() {
  toolConfig=/etc/datasafed/datasafed.conf
  if [ ! -f ${toolConfig} ];then
      echo "ERROR: backupRepo should use Tool accessMode"
      exit 1
  fi
  IFS=$'\n'
  for line in `cat ${toolConfig}`; do
    # remove space
    line=$(eval echo $line)
    IFS=$OlD_IFS
    if [[ $line == "provider"* ]];then
       provider=$(getToolConfigValue "$line")
    elif [[ $line == "access_key_id"* ]];then
       access_key_id=$(getToolConfigValue "$line")
    elif [[ $line == "secret_access_key"* ]];then
       secret_access_key=$(getToolConfigValue "$line")
    elif [[ $line == "region"* ]];then
       region=$(getToolConfigValue "$line")
    elif [[ $line == "endpoint"* ]];then
       endpoint=$(getToolConfigValue "$line")
    elif [[ $line == "root"* ]];then
       bucket=$(getToolConfigValue "$line")
    fi
  done
}

function buildJsonString() {
    jsonString=${1}
    key=${2}
    value=${3}
    if [ ! -z "$jsonString" ];then
       jsonString="${jsonString},"
    fi
    echo "${jsonString}\"${key}\":\"${value}\""
}
# get the storage host by storage provider and endpoint
function getStorageHost() {
    if [[ ! -z ${endpoint} ]]; then
       echo ${endpoint#*//}
       return
    fi
    # TODO: support cos for 4.2.1 version
    if [[ ${provider} == "Alibaba" ]];then
       echo "oss-${DP_STORAGE_REGION}.aliyuncs.com"
    fi
}

function getArchiveDestPath() {
    # TODO: support nfs
    path="/${KB_NAMESPACE}/${KB_CLUSTER_NAME}-${KB_CLUSTER_UID}/${KB_COMP_NAME}/archive"
    echo $path
}

# get the backup dest url
function getDestURL() {
  destType=${1:?missing destType}
  tenantName=${2:?missing tenantName}
  host=$(getStorageHost)
  if [[ -z $host ]];then
     echo "ERROR: unsupported storage provider \"${provider}\""
     exit 1
  fi
  # TODO: support nfs and cos
  destPath="${DP_BACKUP_BASE_PATH}"
  if [[ $destType == "archive" ]]; then
     destPath=$(getArchiveDestPath)
  fi
  echo "oss://${bucket}${destPath}/${tenantName}?host=${host}&access_id=${access_key_id}&access_key=${secret_access_key}"
}

function prepareTenantLogArchive() {
  tenant_name=${1:?missing tenant name}
  destUrl=$(getDestURL archive ${tenant_name})
  echo $destUrl
  echo "INFO: prepare log archive dest for tenant ${tenant_name}"
  result=`${mysql_cmd} "ALTER SYSTEM SET LOG_ARCHIVE_DEST=\"LOCATION=${destUrl}\" TENANT=${tenant_name}"`
  if [[ $? -ne 0 ]];then
     echo "ERROR: alert log_archive_dest for tenant ${tenant_name} failed: ${result}"
     exit 1
  fi
  # TODO: add auto clean archive logs
  # enable dest
  ${mysql_cmd} "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE='ENABLE' TENANT=${tenant_name};"
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
  # enable dest
  ${mysql_cmd} "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE='ENABLE' TENANT=${tenant_name};"
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
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT


# step 1===> prepare for data and archive backup
# analysisToolConfig first
analysisToolConfig

${mysql_cmd} "SELECT tenant_id, tenant_name FROM oceanbase.DBA_OB_TENANTS where tenant_type='user' and status='NORMAL';" | while IFS=$'\t' read -a row; do
  IFS=${OlD_IFS}
  tenant_id=${row[0]}
  tenant_name=${row[1]}
  # prepare tenant log archive dest
  res=`${mysql_cmd} "SELECT count(*) FROM oceanbase.CDB_OB_ARCHIVELOG where status='DOING' and tenant_id=${tenant_id};" |awk -F '\t' '{print}'`
  if [[ $res -eq 0 ]]; then
    # only prepare the tenant which not doing archive.
    prepareTenantLogArchive $tenant_name
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


# step 4===> do data backup
sql="ALTER SYSTEM BACKUP DATABASE;"
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
echo "INFO: backup data completed, start to save status"
sleep 5


# step 6===> check if backup jobs are successful and collect backup info for restore.
tenantFile="tenantStatus.dp"
unitSQLFile="create_unit.sql"
resourcePoolSQLFile="create_resource_pool.sql"
# save unit create statement to tmp file
saveUnitCreateStatement

${mysql_cmd} "select tenant_id, backup_set_id from oceanbase.CDB_OB_BACKUP_JOB_HISTORY where initiator_job_id=${initiator_job_id} and backup_set_id !=0;" | while IFS=$'\t' read -a row; do
    IFS=${OlD_IFS}
    tenant_id=${row[0]}
    backup_set_id=${row[1]}
    ${mysql_cmd} "select d.tenant_name, t.START_REPLAY_SCN, t.START_REPLAY_SCN_DISPLAY, t.MIN_RESTORE_SCN, t.MIN_RESTORE_SCN_DISPLAY, t.STATUS, t.RESULT, t.COMMENT FROM oceanbase.CDB_OB_BACKUP_SET_FILES t, oceanbase.DBA_OB_TENANTS d where t.tenant_id = d.tenant_id and t.BACKUP_SET_ID=${backup_set_id} and t.tenant_id=${tenant_id};" | while IFS=$'\t' read -a res; do
      echo "INFO: collect backup info for tenant ${res[0]}"
      IFS=${OlD_IFS}
      tenantName=${res[0]}
      tenantJson=""
      tenantJson=$(buildJsonString "$tenantJson" "name" $tenantName)
      tenantJson=$(buildJsonString "$tenantJson" "archivePath" "$(getArchiveDestPath)")
      tenantJson=$(buildJsonString "$tenantJson" "startReplaySCN" ${res[1]})
      tenantJson=$(buildJsonString "$tenantJson" "startReplaySCNTIME" "${res[2]}")
      tenantJson=$(buildJsonString "$tenantJson" "minRestoreSCN" ${res[3]})
      tenantJson=$(buildJsonString "$tenantJson" "minRestoreTime" "${res[4]}")
      status=${res[5]}
      if [[ $status -ne "SUCCESS" ]];then
          tenantJson=$(buildJsonString "$tenantJson" "failureMessage" "${res[6]}: ${res[7]}")
      fi
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


# # step 8===> save tenants info for restore and backup status
datasafed push ${unitSQLFile} "/${unitSQLFile}"
datasafed push ${resourcePoolSQLFile} "/${resourcePoolSQLFile}"
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
backupInfo="{\"totalSize\":\"$TOTAL_SIZE\",\"extras\":[${extras}]}"
echo ${backupInfo}
echo ${backupInfo} >"${DP_BACKUP_INFO_FILE}"
if [[ $extras == *"failureMessage"* ]];then
   echo "ERROR: backup data failed: $extras"
   exit 1
fi