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

IP_LIST=()

function  check_ssh_port {
  local ip=$1
  nc -zv -w5 $ip 22 &> /dev/null
  return $?
}

function get_pod_ip_list {
  local SVC_NAME="${KB_CLUSTER_COMP_NAME}-headless.${KB_NAMESPACE}.svc"
  local wait_time=600

  for i in $(seq 0 $(($KB_REPLICA_COUNT-1))); do
    local replica_hostname="${KB_CLUSTER_COMP_NAME}-${i}"
    local replica_ip=""
    local elapsed_time=0

    echo "nslookup $replica_hostname.$SVC_NAME"
    while [ $elapsed_time -lt $wait_time ]; do
      replica_ip=$(nslookup $replica_hostname.$SVC_NAME | awk '/^Address: / { print $2 }')
      if [ -z "$replica_ip" ]; then
        echo "$replica_hostname.$SVC_NAME is not ready yet"
        sleep 10
        elapsed_time=$((elapsed_time + 10))
      else
        echo "$replica_hostname.$SVC_NAME is ready"
        echo "nslookup $replica_hostname.$SVC_NAME success, IP: $replica_ip"
        break
      fi
    done

    if [ -z "$replica_ip" ]; then
      echo "Failed to get the IP of $replica_hostname.$SVC_NAME, exiting..."
      exit 1
    fi

    IP_LIST+=("$replica_ip")
  done

  echo "get_pod_ip_list: ${IP_LIST[*]}"
}

echo "get pod ip list..."

get_pod_ip_list

echo "configure ssh..."

cp /ssh-key/id_rsa /home/gbase/.ssh/id_rsa
cp /ssh-key/id_rsa.pub /home/gbase/.ssh/id_rsa.pub
cat /ssh-key/id_rsa.pub >> /home/gbase/.ssh/authorized_keys
chown -R gbase:gbase /home/gbase/.ssh
chmod 700 /home/gbase/.ssh
chmod 600 /home/gbase/.ssh/id_rsa /home/gbase/.ssh/authorized_keys

echo "complete ssh configure"

sleep 10

echo "wait all pod to ready..."
all_pods_ready=false
while [ "$all_pods_ready" = false ]; do
  all_pods_ready=true
  
  for ip in "${IP_LIST[*]}"; do
    
    if check_ssh_port $ip; then
      echo "Pod at IP $ip SSH service is ready."
    else
      all_pods_ready=false
    fi
  done
  
  if [ "$all_pods_ready" = false ]; then
    sleep 5
  fi
done

echo "generating gbase.yaml..."

dcs_ips=$(python3 /scripts/generate_yaml.py "${IP_LIST[@]}")

echo "YAML file has been generated and saved to /home/gbase/gbase_package/gbase.yaml"

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
  GLOBAL_OUTPUT=$(sudo -i -u gbase /home/gbase/gbase_package/script/gha_ctl start all -l $dcs_ips 2>&1)
  echo "gha_ctl start node log:"
  echo "$GLOBAL_OUTPUT"
fi

if [[ ${firstStart} == true ]]; then
  /home/gbase/gbase_db/app/bin/gs_guc reload -Z coordinator -N all -I all -h "host all all 0.0.0.0/0 sha256"
  /home/gbase/gbase_db/app/bin/gs_guc reload -Z coordinator -N all -I all -c "listen_addresses='*'"

  /home/gbase/gbase_db/app/bin/gsql -p ${server_port} -U ${GBASE_USER} -d postgres <<EOF
ALTER USER ${GBASE_USER} PASSWORD '${GBASE_PASSWORD}';
CREATE USER ${KBADMIN_USER} WITH SYSADMIN PASSWORD '${KBADMIN_PASSWORD}';
EOF

  if [ -d /${DATA_DIR}/backup ]; then
    /home/gbase/gbase_db/app/bin/gsql -p ${server_port} -U ${GBASE_USER} -d postgres -f /home/gbase/backup/backup.sql
  fi
fi

echo "Script execution completed."
exit 0