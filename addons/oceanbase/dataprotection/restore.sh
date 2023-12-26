export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}
sql_port_file=/home/admin/workdir/sql_port.ob
sql_port=2881
if [[ -f ${sql_port_file} ]];then
  sql_port=$(cat ${sql_port_file})
fi
mysql_cmd="mysql -u root -h ${DP_DB_HOST} -P${sql_port} -N -e"
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

function getStorageHost() {
    if [[ ! -z ${endpoint} ]]; then
       echo ${endpoint#*//}
       return
    fi
    # TODO: support cos for 4.2.1 version
    if [[ ${provider} == "Alibaba" ]];then
       echo "oss-${DP_STORAGE_REGION}.aliyun-inc.com"
    fi
}


# get the backup dest url
function getDestURL() {
  local destPath=${1:?missing destPath}
  local tenantName=${2:?missing tenantName}
  local host=$(getStorageHost)
  if [[ -z $host ]];then
     echo "ERROR: unsupported storage provider \"${provider}\""
     exit 1
  fi
  # TODO: support nfs and cos
  echo "oss://${bucket}${destPath}/${tenantName}?host=${host}&access_id=${access_key_id}&access_key=${secret_access_key}"
}


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
     `${mysql_cmd} "${sql}"`
      if [[ $? -eq 0 ]] || [[ $time -ge 2 ]] ; then
        break
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
    local primaryHost=${1}
    local primaryCmd="mysql -u root -P${sql_port} -h ${primaryHost} -N -e"
    while true; do
      echo "INFO: wait primary cluster to restore data completed..."
      historyRes=$(${primaryCmd} "SELECT count(*) FROM oceanbase.CDB_OB_RESTORE_HISTORY;" | awk -F '\t' '{print}')
      if [[ ${historyRes} -lt 1 ]];then
        sleep 10
        continue
      fi
      res=$(${primaryCmd} "SELECT count(*) FROM oceanbase.CDB_OB_RESTORE_PROGRESS;" | awk -F '\t' '{print}')
      if [[ $res -eq 0 ]];then
        break
      fi
      sleep 10
    done
}

function waitToPromotePrimary() {
    local primaryHost=${1}
    local tenant_name=${2}
    local primaryCmd="mysql -u root -P2881 -h ${primaryHost} -N -e"
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

# step 1 ===> create unit config and resource pools
echo "INFO: wait for bootstrap sucessfully."
waitTime=0
while true; do
  tenant_status=`${mysql_cmd} "SELECT * FROM oceanbase.DBA_OB_SERVERS;"`
  if [[ $? -eq 0 ]]; then
     break
  fi
  if [[ $waitTime -gt 300 ]];then
     exit 1
  fi
  sleep 5
  waitTime=$((waitTime+5))
done

unitSQLFile="create_unit.sql"
resourcePoolSQLFile="create_resource_pool.sql"
datasafed pull "/${unitSQLFile}" ${unitSQLFile}
datasafed pull "/${resourcePoolSQLFile}" ${resourcePoolSQLFile}
executeSQLFile ${unitSQLFile}
executeSQLFile ${resourcePoolSQLFile}


# TODO: restore specified tenants
# step 2 ===> restore all tenants
# TODO: drop TENANT_NAME

analysisToolConfig
comp_index=$(echo $KB_CLUSTER_COMP_NAME | awk -F '-' '{print $(NF)}')
extras=$(cat /dp_downward/status_extras)
length=$(echo "$extras" | jq length)
index=$((length-1))
for i in $(seq 0 ${index}); do
   tenant_name=$(echo "$extras" | jq -r ".[${i}].name")
   minRestoreSCN=$(echo "$extras"  | jq -r ".[${i}].minRestoreSCN")
   poolList=$(echo "$extras"  | jq -r ".[${i}].poolList")
   archivePath=$(echo "$extras"  | jq -r ".[${i}].archivePath")
   uri="$(getDestURL "${DP_BACKUP_BASE_PATH}" "${tenant_name}"),$(getDestURL "${archivePath}" "${tenant_name}")"
   echo "INFO: start to restore tenant ${tenant_name}"
   restoreTenant "${tenant_name}" "SET SESSION ob_query_timeout=1000000000; ALTER SYSTEM RESTORE ${tenant_name} FROM '${uri}' UNTIL SCN=${minRestoreSCN} WITH 'pool_list=${poolList}'"
   echo "INFO: restoring tenant ${tenant_name}"
done
sleep 5


# step 3 ===> wait for restore complete
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
restoreFile="restore.dp"
${mysql_cmd} "SELECT TENANT_ID,RESTORE_TENANT_NAME,STATUS,COMMENT FROM oceanbase.CDB_OB_RESTORE_HISTORY;" | while IFS=$'\t' read -a row; do
  IFS=$OlD_IFS
  tenant_id=${row[0]}
  tenant_name=${row[1]}
  status="${row[2]}"
  if [[ $tenant_id -ne 1 ]]; then
     if [[ $status == "SUCCESS" ]]  && [[ $OB_CLUSTERS_COUNT -eq 1 || $comp_index -eq 0 ]];then
        echo "INFO: promote ${tenant_name} to Primary for primary cluster."
        ${mysql_cmd} "ALTER SYSTEM ACTIVATE STANDBY TENANT ${tenant_name}";
        if [[ $OB_CLUSTERS_COUNT -gt 1 ]];then
           sql="ALTER SYSTEM ARCHIVELOG TENANT=${tenant_name};"
           ${mysql_cmd} "${sql}";
        fi
     fi
     if [[ $status != "SUCCESS" ]];then
        echo "ERROR: restore tenant ${tenant_name} failed: ${row[3]}" >> $restoreFile
     fi
  elif [[ $status != "SUCCESS" ]]; then
      echo "ERROR: create tenant ${tenant_name} failed: ${row[3]}" >> $restoreFile
  fi
done


# step 5 ===> establish PRIMARY/STANDBY relationship for standby cluster
# TODO: wait for primary restore successfuly
if [[ $comp_index -gt 0 ]]; then
   repUser=${REP_USER:-rep_user}
   repPasswd=${REP_PASSWD:-rep_user}
   primaryComponentName="${KB_CLUSTER_COMP_NAME%-*}-0"
   primaryHost="${primaryComponentName}-0.${primaryComponentName}-headless"
   echo "primary cluster host: ${primaryHost}"
   waitForPrimaryClusterRestore "${primaryHost}"
   echo "INFO: establish replication relationship"
   # set -e
   for tenant_name in `${mysql_cmd} "SELECT tenant_name FROM oceanbase.DBA_OB_TENANTS where tenant_type='user' and status='NORMAL';" | awk -F '\t' '{print}'`; do
      primary_tenant_cmd="mysql -u root@${tenant_name} -h ${primaryHost} -P${sql_port} -N -e"
      # get primary tenant svr_list
      arr=$(${primary_tenant_cmd} "select concat(SVR_IP,':',SQL_PORT) from oceanbase.DBA_OB_ACCESS_POINT dp, oceanbase.DBA_OB_TENANTS dt where dp.tenant_id = dt.tenant_id and dt.tenant_name='${tenant_name}';" | awk -F '\t' '{print}')
      IFS=,
      svrList="${arr[*]}"
      IFS=$OlD_IFS
      # wait to promote primary cluster to  Primary
      waitToPromotePrimary "${primaryHost}" "${tenant_name}"
      res=`${primary_tenant_cmd} "SELECT count(*) FROM mysql.user where user='${repUser}'" | awk -F '\t' '{print}'`
      if [[ $res -eq 0 ]]; then
        echo "INFO: create user ${repUser} for primary tenant ${tenant_name}"
        ${primary_tenant_cmd} "CREATE USER ${repUser} IDENTIFIED BY '${repPasswd}';"
      else
        echo "INFO: alter user ${repUser} for primary tenant ${tenant_name}"
        ${primary_tenant_cmd} "ALTER USER ${repUser} IDENTIFIED BY '${repPasswd}'";
      fi
      ${primary_tenant_cmd} "GRANT SELECT ON oceanbase.* TO ${repUser};"
      ${primary_tenant_cmd} "SET GLOBAL ob_tcp_invited_nodes='%';"
      echo "INFO: set log source for tenant ${tenant_name}, svrList: ${svrList}, user: ${repUser}"
      ${mysql_cmd} "ALTER SYSTEM SET LOG_RESTORE_SOURCE ='SERVICE=${svrList} USER=${repUser}@${tenant_name} PASSWORD=${repPasswd}' TENANT = ${tenant_name};"
      ${mysql_cmd} "ALTER SYSTEM RECOVER STANDBY TENANT = ${tenant_name} UNTIL UNLIMITED;"
   done
fi

if [[ -f $restoreFile ]];then
   echo $(cat $restoreFile)
fi