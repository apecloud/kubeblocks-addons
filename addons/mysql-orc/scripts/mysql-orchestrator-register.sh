#!/bin/sh
set -ex

# 定义 MySQL 连接参数
mysql_port="3306"
mysql_username="$MYSQL_ROOT_USER"
mysql_password="$MYSQL_ROOT_PASSWORD"

topology_user="$ORC_TOPOLOGY_USER"
topology_password="$ORC_TOPOLOGY_PASSWORD"


# 创建 MySQL 用户并授予权限
create_mysql_user() {
  local host=$1

  echo "Create MySQL User and Grant Permissions..."
  exists=$(mysql -h $host -P 3306 -u $mysql_username -p$mysql_password -s -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'orchestrator');")

  if [ $exists -eq 0 ]; then
    echo "Create MySQL User and Grant Permissions..."
    mysql -h $host -P 3306 -u $mysql_username -p$mysql_password << EOF
CREATE USER '$topology_user'@'%' IDENTIFIED BY '$topology_password';
GRANT SUPER, PROCESS, REPLICATION SLAVE, RELOAD ON *.* TO '$topology_user'@'%';
GRANT SELECT ON mysql.slave_master_info TO '$topology_user'@'%';
EOF
  else
    echo "MySQL user '$topology_user' already exists."
  fi
}

wait_for_connectivity() {
  local timeout=600
  local start_time=$(date +%s)
  local current_time

  local host=$1
  echo "Checking mysql connectivity to $host on port $mysql_port ..."
  while true; do
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      echo "Timeout waiting for $host to become available."
      exit 1
    fi

    # Send PING and check for mysql response
    if  mysqladmin -h "$host" -P 3306 -u "$mysql_username" -p"$mysql_password" PING | grep -q "mysqld is alive"; then
      echo "$host is reachable."
      break
    fi

    sleep 5
  done
}

register_to_orchestrator() {
    local timeout=100
    local start_time=$(date +%s)
    local current_time

    local host_ip=$1
    echo "register all mysql pod to orchestrator..."
    while true; do
    # 注册到 Orchestrator
        echo "register $pod_name ($host_ip) to Orchestrator..."
        current_time=$(date +%s)
        if [ $((current_time - start_time)) -gt $timeout ]; then
          echo "Timeout waiting for $host to become available."
          return 1
        fi

        # 定义要检查的 URL
        url="http://orc-cluster-orchestrator-orchestrator:80/api/discover/$host_ip/3306"
        response=$(curl -s -o /dev/null -w "%{http_code}" $url)

        if [ $response -eq 200 ]; then
            echo "response success"
            current_time=0
        else
            echo "response failed"
            sleep 1
        fi
    done
    return 0
}


# 从环境变量中获取 Pod 名称列表和 IP 地址列表
process_each_pod() {
  local mysql_port

  if [ -z "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" ] || [ -z "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST" ]; then
    echo "Error: Required environment variables KB_CLUSTER_COMPONENT_POD_NAME_LIST or KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are not set."
    exit 1
  fi

  old_ifs="$IFS"
  IFS=','
  set -f
  pod_name_list="$KB_CLUSTER_COMPONENT_POD_NAME_LIST"
  pod_ip_list="$KB_CLUSTER_COMPONENT_POD_IP_LIST"
  set +f
  IFS="$old_ifs"

  for (( i=0; i<${#pod_name_list[@]}; i++ )); do
    pod_name="${pod_name_list_array[$i]}"
    host_ip="${pod_ip_list%%,*}"



    echo "podname: $pod_name,  host_ip: $host_ip，iteration count：${#pod_name_list[@]}"

    # 处理每个 Pod
    echo "processing $pod_name ($host_ip)"
    # wait for mysql to become available
    wait_for_connectivity "$host_ip"
    # create mysql user for orchestrator and grant permissions
    create_mysql_user "$host_ip"
    # register to orchestrator
    register_to_orchestrator "$host_ip"

    register_result=$(register_to_orchestrator "$host_ip")
    if [ $register_result -eq 0 ]; then
      echo "Registration for $pod_name successful."
    else
      echo "Registration for $pod_name failed."
      exit 1
    fi
  done
  echo "Initialization script completed！"
}

# 获取 Pod 名称和 IP 地址列表
process_each_pod

echo "completed"