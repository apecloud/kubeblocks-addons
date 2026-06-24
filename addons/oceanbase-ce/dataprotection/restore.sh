#!/usr/bin/env bash
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}

SUBDOMAIN=${OB_COMPONENT_NAME}-headless

tenant_restored_signal=/home/admin/workdir/restore-primary.done


echo "Wait for a while before restoring cluster."
sleep 30
primary_host="${OB_COMPONENT_NAME}-0.${SUBDOMAIN}"
target_host="${primary_host}"


detect_mysql_bin
primaryCmd="${OB_MYSQL_BIN} -u root -P${DP_DB_PORT} -h ${primary_host} -p${OB_ROOT_PASSWD} -N -e"

echo "INFO: primary host: ${primary_host}, current pod host: ${DP_DB_HOST}, target host: ${target_host}"

mysql_cmd="${OB_MYSQL_BIN} -u root -P${DP_DB_PORT} -h ${target_host} -p${OB_ROOT_PASSWD} -N -e"

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
    if [[ "$tenant_name" == "${TENANT_NAME:-}" ]]; then
      echo "INFO: drop init tenant ${tenant_name}"
      ${mysql_cmd} "SET SESSION ob_query_timeout=1000000000; DROP TENANT IF EXISTS ${TENANT_NAME} FORCE;"
    fi
    echo "INFO: $sql"
    if ${mysql_cmd} "${sql}"; then
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

function normalizeSQLValue() {
  local value=${1}
  if [[ "${value}" == "NULL" ]]; then
    echo ""
    return
  fi
  echo "${value}"
}

function getTenantStatusRole() {
  local tenant_name=${1:?missing tenant_name}
  ${mysql_cmd} "SELECT COALESCE(status,''), COALESCE(tenant_role,'') FROM oceanbase.DBA_OB_TENANTS WHERE tenant_name='${tenant_name}' AND tenant_type='USER';" 2>/dev/null | awk 'NF {print; exit}'
}

function getRestoreProgressCount() {
  ${mysql_cmd} "SELECT count(*) FROM oceanbase.CDB_OB_RESTORE_PROGRESS;" 2>/dev/null | awk -F '\t' 'NF {print; exit}'
}

function getLatestRestoreHistoryStatus() {
  local tenant_name=${1:?missing tenant_name}
  ${mysql_cmd} "SELECT STATUS FROM oceanbase.CDB_OB_RESTORE_HISTORY WHERE RESTORE_TENANT_NAME='${tenant_name}';" 2>/dev/null | awk 'NF {status=$0} END {print status}'
}

function printRestoreDiagnostics() {
  local tenant_name=${1:?missing tenant_name}
  echo "INFO: restore diagnostics for tenant ${tenant_name}: DBA_OB_TENANTS"
  ${mysql_cmd} "SELECT tenant_id,tenant_name,status,tenant_role FROM oceanbase.DBA_OB_TENANTS WHERE tenant_name='${tenant_name}' AND tenant_type='USER';" 2>&1 || true
  echo "INFO: restore diagnostics for tenant ${tenant_name}: CDB_OB_RESTORE_PROGRESS"
  ${mysql_cmd} "SELECT * FROM oceanbase.CDB_OB_RESTORE_PROGRESS;" 2>&1 || true
  echo "INFO: restore diagnostics for tenant ${tenant_name}: CDB_OB_RESTORE_HISTORY"
  ${mysql_cmd} "SELECT TENANT_ID,RESTORE_TENANT_NAME,STATUS,COMMENT FROM oceanbase.CDB_OB_RESTORE_HISTORY WHERE RESTORE_TENANT_NAME='${tenant_name}';" 2>&1 || true
}

function waitForExistingTenantRestore() {
  local tenant_name=${1:?missing tenant_name}
  local timeout=${RESTORE_TENANT_WAIT_TIMEOUT_SECONDS:-300}
  local interval=${RESTORE_TENANT_WAIT_INTERVAL_SECONDS:-10}
  local waitTime=0
  local tenant_state tenant_status tenant_role progress_count history_status

  while true; do
    tenant_state=$(getTenantStatusRole "${tenant_name}")
    tenant_status=""
    tenant_role=""
    if [[ -n "${tenant_state}" ]]; then
      IFS=$'\t' read -r tenant_status tenant_role <<< "${tenant_state}"
      IFS=$OlD_IFS
      tenant_status=$(normalizeSQLValue "${tenant_status}")
      tenant_role=$(normalizeSQLValue "${tenant_role}")
    else
      echo "ERROR: tenant ${tenant_name} disappeared while waiting for restore convergence"
      printRestoreDiagnostics "${tenant_name}"
      return 1
    fi
    progress_count=$(getRestoreProgressCount)
    history_status=$(getLatestRestoreHistoryStatus "${tenant_name}")
    echo "INFO: tenant ${tenant_name} restore wait: status='${tenant_status:-NULL}', role='${tenant_role:-NULL}', restore_progress_count='${progress_count:-unknown}', latest_restore_history_status='${history_status:-none}', wait=${waitTime}s/${timeout}s"

    if [[ "${tenant_role}" == "PRIMARY" ]] || [[ "${tenant_role}" == "STANDBY" ]]; then
      echo "INFO: tenant ${tenant_name} restore already converged with role ${tenant_role}"
      return 0
    fi

    if [[ "${history_status}" == *"FAIL"* ]]; then
      echo "ERROR: tenant ${tenant_name} restore history reports failure"
      printRestoreDiagnostics "${tenant_name}"
      return 1
    fi

    if [[ -n "${tenant_status}" ]] && [[ "${tenant_status}" != "RESTORE" ]] && [[ "${tenant_role}" != "RESTORE" ]]; then
      echo "ERROR: tenant ${tenant_name} exists with unexpected status '${tenant_status}' and role '${tenant_role:-NULL}'"
      printRestoreDiagnostics "${tenant_name}"
      return 1
    fi

    if [[ ${waitTime} -ge ${timeout} ]]; then
      echo "ERROR: tenant ${tenant_name} did not leave RESTORE state within ${timeout}s"
      printRestoreDiagnostics "${tenant_name}"
      return 1
    fi

    sleep "${interval}"
    waitTime=$((waitTime+interval))
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
      tenant=$(json_get name "$line")
      if [ "${tenant}" == "${tenantName}" ]; then
          checkPointTime=$(json_get checkPointTime "$line")
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
length=$(json_array_len "$extras")
index=$((length-1))
for i in $(seq 0 ${index}); do
  if [[ -f ${tenant_restored_signal} ]]; then
    echo "INFO: primary cluster has been restored, skip the restore process."
    continue
  fi
  tenant_name=$(json_array_get "$i" name "$extras")
  tenant_id=$(json_array_get "$i" tenantId "$extras")
  minRestoreSCN=$(json_array_get "$i" minRestoreSCN "$extras")
  poolList=$(json_array_get "$i" poolList "$extras")
  archivePath=$(json_array_get "$i" archivePath "$extras")
  uri="$(getDestURL data "${tenant_name}"),$(getDestURL restoreFromArchive "${tenant_name}" "${tenant_id}" "${archivePath}")"
  restoreFragment=$(getRestoreFragment "${tenant_name}" "${minRestoreSCN}")
  tenant_state=$(getTenantStatusRole "${tenant_name}")
  existing_status=""
  existing_role=""
  if [[ -n "${tenant_state}" ]]; then
    IFS=$'\t' read -r existing_status existing_role <<< "${tenant_state}"
    IFS=$OlD_IFS
    existing_status=$(normalizeSQLValue "${existing_status}")
    existing_role=$(normalizeSQLValue "${existing_role}")
    case "$existing_role" in
      PRIMARY)
        echo "INFO: tenant ${tenant_name} already PRIMARY, skipping RESTORE"
        ;;
      STANDBY)
        echo "INFO: tenant ${tenant_name} already STANDBY (restore completed), skipping RESTORE"
        ;;
      RESTORE)
        echo "INFO: tenant ${tenant_name} in RESTORE state, skipping RESTORE command"
        waitForExistingTenantRestore "${tenant_name}" || exit 1
        ;;
      *)
        if [[ "${existing_status}" == "RESTORE" ]] && [[ -z "${existing_role}" ]]; then
          echo "INFO: tenant ${tenant_name} already exists in RESTORE status with empty role, waiting for restore convergence"
          waitForExistingTenantRestore "${tenant_name}" || exit 1
        else
          echo "ERROR: tenant ${tenant_name} exists with unexpected status '${existing_status:-NULL}' and role '${existing_role:-NULL}'"
          printRestoreDiagnostics "${tenant_name}"
          exit 1
        fi
        ;;
    esac
    continue
  fi
  echo "INFO: start to restore tenant ${tenant_name} until ${restoreFragment}"
  restoreTenant "${tenant_name}" "SET SESSION ob_query_timeout=1000000000; ALTER SYSTEM RESTORE ${tenant_name} FROM '${uri}' UNTIL ${restoreFragment} WITH 'pool_list=${poolList}'"
  if [ $? -eq 1 ]; then
    printRestoreDiagnostics "${tenant_name}"
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
