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
kb_cluster_name="$KB_CLUSTER_NAME"
ORCHESTRATOR_API=""

prepare_orchestrator_env() {
   i=0
   port_name=ORC_PORTS_${i}
   endpoint_name=ORC_ENDPOINTS_${i}
   while [[ -n "${!port_name}" ]] && [[ -n "${!endpoint_name}" ]]; do
     port=${!port_name}
     endpoint=${!endpoint_name}

     api="https://$endpoint:$port/api"

     if [[ -z "$ORCHESTRATOR_API" ]]; then
       ORCHESTRATOR_API="$api"
     else
       ORCHESTRATOR_API="$ORCHESTRATOR_API $api"
     fi
     ((i++))
     port_name=ORC_PORTS_${i}
     endpoint_name=ORC_ENDPOINTS_${i}
   done
}

install_jq_dependency() {
  rpm -ivh https://yum.oracle.com/repo/OracleLinux/OL8/appstream/x86_64/getPackage/oniguruma-6.8.2-2.1.el8_9.x86_64.rpm
  rpm -ivh https://mirrors.aliyun.com/centos/8/AppStream/x86_64/os/Packages/jq-1.5-12.el8.x86_64.rpm
}

# create orchestrator user in mysql
create_mysql_user() {
  local service_name=$(echo "${cluster_component_pod_name}_${component_name}_${i}" | tr '-' '_' | tr '[:lower:]' '[:upper:]')

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

  echo "Checking mysql connectivity to $host on port $mysql_port ..."
  while true; do
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      echo "Timeout waiting for $host to become available."
      exit 1
    fi

    # Send PING and check for mysql response
    if  mysqladmin -h  -P 3306 -u "$mysql_username" -p"$mysql_password" PING | grep -q "mysqld is alive"; then
      echo "mysql is reachable."
      break
    fi

    sleep 5
  done
}

change_master() {

  username=$mysql_username
  password=$mysql_password

  master_host_name=$(echo "${cluster_component_pod_name}_${component_name}_0_SERVICE_HOST" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
  master_host=${!first_mysql_service_host_name}

  echo "Changing master to $host_ip..."

  # 使用提供的参数执行 CHANGE MASTER 语句
  mysql  -u "$username" -p"$password" <<-EOSQL
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

find_master_from_orchestrator() {
  ./orchestrator-client -c topology $kb_cluster_name
}

install_jq_dependency
prepare_orchestrator_env
wait_for_connectivity
create_mysql_user
