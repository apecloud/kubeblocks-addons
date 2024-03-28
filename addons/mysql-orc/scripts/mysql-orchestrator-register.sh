#!/bin/sh
set -ex

# 定义 MySQL 连接参数
mysql_port="3306"
mysql_username="$MYSQL_ROOT_USER"
mysql_password="$MYSQL_ROOT_PASSWORD"

topology_user="$ORC_TOPOLOGY_USER"
topology_password="$ORC_TOPOLOGY_PASSWORD"



replica_count="$KB_REPLICA_COUNT"
cluster_component_pod_name="$KB_CLUSTER_COMP_NAME"
component_name="$KB_COMP_NAME"

# create orchestrator user in mysql
create_mysql_user() {
  local host=$1
  local service_name=$2

  echo "Create MySQL User and Grant Permissions..."
  exists=$(mysql -h $host -P 3306 -u $mysql_username -p$mysql_password -s -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'orchestrator');")

  if [ $exists -eq 0 ]; then
    echo "Create MySQL User and Grant Permissions..."
    mysql -h $host -P 3306 -u $mysql_username -p$mysql_password << EOF
CREATE USER '$topology_user'@'%' IDENTIFIED BY '$topology_password';
GRANT SUPER, PROCESS, REPLICATION SLAVE, RELOAD ON *.* TO '$topology_user'@'%';
GRANT SELECT ON mysql.slave_master_info TO '$topology_user'@'%';
GRANT DROP ON _pseudo_gtid_.* to '$topology_user'@'%';
set global slave_net_timeout = 4;
EOF
  else
    echo "MySQL user '$topology_user' already exists."
  fi

  mysql -h $host -P 3306 -u $mysql_username -p$mysql_password <<-EOSQL
CREATE DATABASE IF NOT EXISTS `kb_orc_meta_cluster`;
GRANT ALL ON `kb_orc_meta_cluster`.* TO '$topology_user'@'%';
CREATE TABLE IF NOT EXISTS kb_orc_meta_cluster.kb_orc_meta_cluster (
`anchor` tinyint(4) NOT NULL,
`host_name` varchar(128) NOT NULL DEFAULT '',
`cluster_name` varchar(128) NOT NULL DEFAULT '',
`cluster_domain` varchar(128) NOT NULL DEFAULT '',
`data_center` varchar(128) NOT NULL,
PRIMARY KEY (`anchor`)
);
INSERT INTO kb_orc_meta_cluster.kb_orc_meta_cluster (host_name,cluster_name, cluster_domain, data_center)
VALUES ('$service_name','$KB_CLUSTER_NAME', '', '');
EOSQL

}

# wait for mysql to be available
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

# register first pod to orchestrator
register_to_orchestrator() {
  local host_ip=$1

  local timeout=100
  local start_time=$(date +%s)
  local current_time


  local url="http://orc-cluster-orchestrator-orchestrator:80/api/discover/$host_ip/3306"
  local instance_url="http://orc-cluster-orchestrator-orchestrator:80/api/instance/$host_ip/330"

  echo "register first mysql pod to orchestrator..."
  instanceResponse=$(curl -s -o /dev/null -w "%{http_code}" $instance_url)
    if [ $instanceResponse -eq 200 ]; then
      echo "response success"
    fi

  while true; do
    # 注册到 Orchestrator
    echo "register $pod_name ($host_ip) to Orchestrator..."
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      echo "Timeout waiting for $host to become available."
      exit 1
    fi

    # url for orchestrator to discover this host_ip

    # 发送请求并获取响应
    response=$(curl -s -o /dev/null -w "%{http_code}" $url)
    if [ $response -eq 200 ]; then
        echo "response success"
        break
    fi
  done
  echo "register $pod_name ($host_ip) to Orchestrator successful."
}


change_master() {
  local host_ip=$1
  local master_host=$2
  local master_port=$3
  local username=$4
  local password=$5

  echo "Changing master to $host_ip..."

  # 使用提供的参数执行 CHANGE MASTER 语句
  mysql -h "$host_ip" -u "$username" -p"$password" <<-EOSQL
STOP SLAVE;
SET GLOBAL SQL_SLAVE_SKIP_COUNTER=1;
CHANGE MASTER TO
MASTER_CONNECT_RETRY=1,
MASTER_RETRY_COUNT=86400,
MASTER_HOST='$master_host',
MASTER_PORT=$master_port,
MASTER_USER='$username',
MASTER_PASSWORD='$password';
START SLAVE;
EOSQL

  echo "CHANGE MASTER successful for $master_host."

}



# 从环境变量中获取 Pod 名称列表和 IP 地址列表
process_each_pod() {

  if [ -z "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" ] || [ -z "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST" ]; then
    echo "Error: Required environment variables KB_CLUSTER_COMPONENT_POD_NAME_LIST or KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are not set."
    exit 1
  fi

  old_ifs="$IFS"
  IFS=','
  pod_name_list=($KB_CLUSTER_COMPONENT_POD_NAME_LIST)
  pod_ip_list=($KB_CLUSTER_COMPONENT_POD_IP_LIST)
  IFS="$old_ifs"
  echo "pod_name_list: $pod_name_list"

  first_mysql_service_host_name=$(echo "${cluster_component_pod_name}_${component_name}_0_SERVICE_HOST" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
  first_mysql_service_host=${!first_mysql_service_host_name}

  for (( i=0; i<${replica_count}; i++ )); do
    pod_name="${pod_name_list[$i]}"
    host_ip="${pod_ip_list%%,*}"

    mysql_service=$(echo "${cluster_component_pod_name}_${component_name}_${i}" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    mysql_service_host_name=$mysql_service"_SERVICE_HOST"
    mysql_service_host=${!mysql_service_host_name}

    # 处理每个 Pod
    echo "processing $pod_name ($mysql_service_host)"
    # wait for mysql to become available
    wait_for_connectivity "$mysql_service_host"

    create_mysql_user "$mysql_service_host" "$mysql_service"
    if [[ $i -eq 0 ]]; then
      # create mysql user for orchestrator and grant permissions
      register_to_orchestrator "$mysql_service_host"
    else
      change_master "$mysql_service_host" "$first_mysql_service_host" "$mysql_port" "$mysql_username" "$mysql_password"
    fi
  done
  echo "Initialization script completed！"
}
# 获取 Pod 名称和 IP 地址列表
process_each_pod

echo "completed"