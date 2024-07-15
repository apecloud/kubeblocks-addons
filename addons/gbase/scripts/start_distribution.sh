#!/bin/bash

# 设置日志文件路径
LOG_FILE="/start_cluster.log"

# 如果日志文件不存在则创建
if [ ! -f "$LOG_FILE" ]; then
  touch "$LOG_FILE"
fi

# 将所有输出重定向到日志文件
exec > >(tee -a "$LOG_FILE") 2>&1

GLOBAL_OUTPUT=""

# 设置错误处理
trap 'handle_error' ERR

handle_error() {
  echo "An error occurred in command: '$BASH_COMMAND'. Exiting..."
  echo "Command output: $GLOBAL_OUTPUT"
  exit 0
}

NAMESPACE=$KB_NAMESPACE

function check_host_ready {
  local ip=$1
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 gbase@$ip exit &> /dev/null
  return $?
}
 
function get_pod_ip_list {
  local svc_name="${1}-headless.${2}.svc.cluster.local"
  local replica_count=$3
  local wait_time=600
  local ip_list=()

  for i in $(seq 0 $(($replica_count - 1))); do
    local replica_hostname="${1}-${i}"
    local replica_ip=""
    local elapsed_time=0
    
    while [ $elapsed_time -lt $wait_time ]; do
      replica_ip=$(nslookup $replica_hostname.$svc_name | awk '/^Address: / { print $2 }')
      if [ -z "$replica_ip" ]; then
        echo "$replica_hostname.$svc_name is not ready yet"
        sleep 10
        elapsed_time=$((elapsed_time + 10))
      else
        break
      fi
    done

    if [ -z "$replica_ip" ]; then
      echo "Failed to get the IP of $replica_hostname.$svc_name, exiting..."
      exit 1
    fi

    ip_list+=("$replica_ip")
  done
  
  echo "${ip_list[@]}"
}

function wait_for_pods_ready {
  local ips=("$@")
  local all_pods_ready=false

  while [ "$all_pods_ready" = false ]; do
    all_pods_ready=true

    for ip in "${ips[@]}"; do
      if ! check_host_ready $ip; then
        echo "Pod at IP $ip SSH service is ready."
      else
        all_pods_ready=false
      fi
    done

    if [ "$all_pods_ready" = false ]; then
      sleep 5
    fi
  done
}

/scripts/set_ssh.sh

echo "get pod ip list..."
echo "gha_server node ip list: "
GHA_SERVER_IPS=$(get_pod_ip_list "$GBASE_GHA_SERVER_POD_LIST" "$GBASE_GHA_SERVER_HEADLESS" "$NAMESPACE")
echo "$GHA_SERVER_IPS"

echo "gtm node ip list: "
GTM_IPS=$(get_pod_ip_list "$GBASE_GTM_POD_LIST" "$GBASE_GTM_HEADLESS" "$NAMESPACE")
echo "$GTM_IPS"

echo "data node ip list: "
DATANODE_IPS=$(get_pod_ip_list "$GBASE_DATANODE_POD_LIST" "$GBASE_DATANODE_HEADLESS" "$NAMESPACE")
echo "$DATANODE_IPS"

echo "coordinator node ip list: "
COORDINATOR_IPS=$(get_pod_ip_list "$GBASE_COORDINATOR_POD_LIST" "$GBASE_COORDINATOR_HEADLESS" "$NAMESPACE")
echo "$COORDINATOR_IPS"

echo "dcs node ip list: "
DCS_IPS=$(get_pod_ip_list "$GBASE_DCS_POD_LIST" "$GBASE_DCS_HEADLESS" "$NAMESPACE")
echo "$DCS_IPS"

echo "Checking if gha_server pods are ready..."
wait_for_pods_ready "${GHA_SERVER_IPS[@]}"

echo "Checking if GTM pods are ready..."
wait_for_pods_ready "${GTM_IPS[@]}"

echo "Checking if Datanode pods are ready..."
wait_for_pods_ready "${DATANODE_IPS[@]}"

echo "Checking if Coordinator pods are ready..."
wait_for_pods_ready "${COORDINATOR_IPS[@]}"

echo "Checking if DCS pods are ready..."
wait_for_pods_ready "${DCS_IPS[@]}"

echo "All pods are ready."

echo "generating gbase.yaml..."

dcs_ips=$(python3 /scripts/generate_distribution_yaml.py "${GHA_SERVER_IPS[@]}" "${GTM_IPS[@]}" "${DATANODE_IPS[@]}" "${COORDINATOR_IPS[@]}" "${DCS_IPS[@]}")

echo "YAML file has been generated and saved to /home/gbase/gbase_package/gbase.yaml"

# must be http://ip format
echo "DCS IPs: $dcs_ips"

CURRENT_POD_NAME=$(hostname)

firstStart=false

if ! sudo -u gbase -i command -v gha_ctl &> /dev/null; then
  if [[ ${CURRENT_POD_NAME: -1} == "0" ]]; then
    echo "install gha_ctl......"
    GLOBAL_OUTPUT=$(sudo -i -u gbase /home/gbase/gbase_package/script/gha_ctl install -p /home/gbase/gbase_package -c gbase 2>&1)
    echo "gha_ctl install node log:"
    echo "$GLOBAL_OUTPUT"
  fi
  firstStart=true
fi

if [[ ${CURRENT_POD_NAME: -1} == "0" ]]; then
  echo "gha_ctl start......"
  GLOBAL_OUTPUT=$(sudo -i -u gbase /home/gbase/gbase_package/script/gha_ctl start all -l $DCS_IPS 2>&1)
  echo "gha_ctl start node log:"
  echo "$GLOBAL_OUTPUT"
fi

if [[ ${firstStart} == true ]]; then
  /home/gbase/gbase_db/app/bin/gs_guc reload -Z coordinator -N all -I all -h "host all all 0.0.0.0/0 sha256"
  /home/gbase/gbase_db/app/bin/gs_guc reload -Z coordinator -N all -I all -c "listen_addresses='*'"

  /home/gbase/gbase_db/app/bin/gsql -p ${server_port} -U ${GBASE_USER} -d postgres <<EOF
ALTER USER ${GBASE_USER} PASSWORD '${GBASE_PASSWORD}';
EOF
fi

if [ -d /${DATA_DIR}/backup ]; then
  /home/gbase/gbase_db/app/bin/gsql -p ${server_port} -U ${GBASE_USER} -d postgres -f /home/gbase/backup/backup.sql
fi

echo "Script execution completed."
exit 0