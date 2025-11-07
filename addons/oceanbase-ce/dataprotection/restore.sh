#!/usr/bin/env bash
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}

SUBDOMAIN=${OB_COMPONENT_NAME}-headless

tenant_restored_signal=/home/admin/workdir/restore-primary.done


echo "Wait for a while before restoring cluster."
sleep 30
primary_host="${OB_COMPONENT_NAME}-0.${SUBDOMAIN}"
target_host="${primary_host}"


primaryCmd="mysql -u root -P${DP_DB_PORT} -h ${primary_host} -p${OB_ROOT_PASSWD} -N -e"

echo "INFO: primary host: ${primary_host}, current pod host: ${DP_DB_HOST}, target host: ${target_host}"

mysql_cmd="mysql -u root -P${DP_DB_PORT} -h ${target_host} -p${OB_ROOT_PASSWD} -N -e"

OlD_IFS=$IFS

archiveStatusFile="tenantStatus.dp"

function execute() {
  local sql=${1:?missing sql}
  while true; do
    echo "execute '${sql}'"
    res=`${mysql_cmd} "${sql}" 2>&1`
    if [[ $res != *"Server is initializing"* ]]; then
      break
      exit 1
    fi
    echo "$res"
    sleep 10
  done
}

function restoreTenant() {
  local tenant_name=${1:?missing tenant_name}
  local sql=${2:?missing restore sql}
  local time=0
  while true; do
    if [[ "$tenant_name" == ${TENANT_NAME} ]]; then
      echo "INFO: drop init tenant ${tenant_name}"
      ${mysql_cmd} "SET SESSION ob_query_timeout=1000000000; DROP TENANT IF EXISTS ${TENANT_NAME} FORCE;"
    fi
    echo "INFO: $sql"
    `${mysql_cmd} "${sql}"`
    if [[ $? -eq 0 ]]  ; then
      break
    fi
    if [[ $time -ge 2 ]]; then
        return 1
    fi
    time=$((time+1))
  done
}

function executeSQLFile() {
  local sqlFile=${1}
  IFS=$'\n'
  for sql in `cat ${sqlFile}`; do
    IFS=$OlD_IFS
    execute "${sql}"
  done
}

function waitForPrimaryClusterRestore() {
  while true; do
    echo "INFO: wait primary cluster to restore data completed..."
    res=$(${primaryCmd} "SELECT count(*) FROM oceanbase.CDB_OB_RESTORE_PROGRESS;" | awk -F '\t' '{print}')
    if [[ $res -eq 0 ]];then
      break
    fi
    sleep 10
  done
}

function waitToPromotePrimary() {
  local tenant_name=${1}
  local time=0
  while true; do
    echo "INFO: wait to promote ${tenant_name} to PRIMARY."
    role=$(${primaryCmd} "select tenant_role from oceanbase.DBA_OB_TENANTS where tenant_name='${tenant_name}';" | awk -F '\t' '{print}')
    if [[ $role == "PRIMARY" ]] || [[ $time -gt 60 ]];then
      break
    fi
    time=$((time+10))
    sleep 10
  done
}

function pullArchiveStatusFile() {
  export DATASAFED_BACKEND_BASE_PATH=$(dirname ${DP_BACKUP_BASE_PATH})/archive
  if [ "$(datasafed list ${archiveStatusFile})" == "${archiveStatusFile}" ]; then
    # TODO: using archive path to replace?
    echo "INFO: pull archive status file ${archiveStatusFile}"
    datasafed pull ${archiveStatusFile} ${archiveStatusFile}
  fi
  export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}
}

function getRestoreFragment() {
  local tenantName=${1:?missing tenant name}
  local scn=${2:?missing restore scn}
  if [ -z "${DP_RESTORE_TIME}" ]; then
    echo "SCN=${scn}"
    return
  fi
  if [ -f ${archiveStatusFile} ]; then
    while IFS= read -r line; do
      IFS=$OlD_IFS
      if [ -z "$line" ]; then
          continue
      fi
      tenant=`echo ${line} | jq -r ".name"`
      if [ "${tenant}" == "${tenantName}" ]; then
          checkPointTime=`echo ${line} | jq -r ".checkPointTime"`
          if [ $(date -d "${DP_RESTORE_TIME}" +%s) -gt $(date -d "${checkPointTime}" +%s) ]; then
            echo "TIME='$(date -d "${checkPointTime}" "+%Y-%m-%d %H:%M:%S")'"
            return
          fi
      fi
    done < ${archiveStatusFile}
  fi
  echo "TIME='${DP_RESTORE_TIME}'"
}

# step 1 ===> create unit config and resource pools.
echo "INFO: step 1 ===> INFO: check for instance bootstrap successfully."
echo "INFO: wait for bootstrap successfully."
waitTime=0
until ${mysql_cmd} "SELECT * FROM oceanbase.DBA_OB_TENANTS;"
do
  if [[ $waitTime -gt 300 ]];then
    echo "ERROR: wait for bootstrap failed, wait time: ${waitTime}s"
    exit 1
  fi
  echo "INFO: wait for bootstrap successfully, wait time: ${waitTime}s"
  sleep 5
  waitTime=$((waitTime+5))
done

echo "INFO: step 2 ===> create unit config and resource pools, restore tenants."

unitSQLFile="create_unit.sql"
resourcePoolSQLFile="create_resource_pool.sql"
datasafed pull "/${unitSQLFile}" ${unitSQLFile}
datasafed pull "/${resourcePoolSQLFile}" ${resourcePoolSQLFile}
executeSQLFile ${unitSQLFile}
executeSQLFile ${resourcePoolSQLFile}

# TODO: restore specified tenants
# step 2 ===> restore all tenants
# isPrimaryCluster=$(checkIsPrimaryCluster)
analysisToolConfig
pullArchiveStatusFile
# global_comp_index=$(echo $OB_COMPONENT_NAME | awk -F '-' '{print $(NF)}')
extras=$(cat /dp_downward/status_extras)
length=$(echo "$extras" | jq length)
index=$((length-1))
for i in $(seq 0 ${index}); do
  if [[ -f ${tenant_restored_signal} ]]; then
    echo "INFO: primary cluster has been restored, skip the restore process."
    continue
  fi
  tenant_name=$(echo "$extras" | jq -r ".[${i}].name")
  tenant_id=$(echo "$extras"  | jq -r ".[${i}].tenantId")
  minRestoreSCN=$(echo "$extras"  | jq -r ".[${i}].minRestoreSCN")
  poolList=$(echo "$extras"  | jq -r ".[${i}].poolList")
  archivePath=$(echo "$extras"  | jq -r ".[${i}].archivePath")
  uri="$(getDestURL data "${tenant_name}"),$(getDestURL restoreFromArchive "${tenant_name}" "${tenant_id}" "${archivePath}")"
  restoreFragment=$(getRestoreFragment "${tenant_name}" "${minRestoreSCN}")
  echo "INFO: start to restore tenant ${tenant_name} until ${restoreFragment}"
  # TODO: check if the sql executed successfully. if restore time is over than actual time, it will failed.
  # ERROR 4018 (HY000) at line 1: No enough log for restore
  restoreTenant "${tenant_name}" "SET SESSION ob_query_timeout=1000000000; ALTER SYSTEM RESTORE ${tenant_name} FROM '${uri}' UNTIL ${restoreFragment} WITH 'pool_list=${poolList}'"
  if [ $? -eq 1 ]; then
    exit 1
  fi
  echo "INFO: restoring tenant ${tenant_name}"
done
sleep 5

# step 3 ===> wait for restore complete
echo "INFO: step 3 ===> wait for restore data completed."
while true; do
  res=$(${mysql_cmd} "SELECT count(*) FROM oceanbase.CDB_OB_RESTORE_PROGRESS;" | awk -F '\t' '{print}')
  if [[ $res -eq 0 ]];then
    break
  fi
  echo "INFO: wait for restore data completed, uncompleted job count: ${res}"
  sleep 10
done
echo "INFO: restore data completed"
sleep 5

# step 4 ===> promote the tenants of the first replicas to PRIMARY and record the failed restore jobs.
echo "INFO: step 4 ===> promote the tenants."
restoreFile="restore.dp"
${mysql_cmd} "SELECT TENANT_ID,RESTORE_TENANT_NAME,STATUS,COMMENT FROM oceanbase.CDB_OB_RESTORE_HISTORY;" | while IFS=$'\t' read -a row; do
  IFS=$OlD_IFS
  tenant_id=${row[0]}
  tenant_name=${row[1]}
  status="${row[2]}"
  if [[ $tenant_id -eq 1 ]]; then
     continue
  fi
  if [[ $status != "SUCCESS" ]]; then
    echo "ERROR: restore tenant ${tenant_name} failed: ${row[3]}" >> $restoreFile
    continue
  fi
done