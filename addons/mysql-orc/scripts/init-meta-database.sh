#!/bin/sh
set -ex
# 定义 MySQL 连接参数
mysql_port="3306"
meta_mysql_username="$META_MYSQL_USER"
meta_mysql_password="$META_MYSQL_PASSWORD"
meta_mysql_endpoint="$META_MYSQL_USER"
meta_mysql_host=${meta_mysql_endpoint%:*}
meta_mysql_port=${meta_mysql_endpoint#*:}

meta_user="$ORC_META_USER"
meta_password="$ORC_META_PASSWORD"
meta_database="$ORC_META_DATABASE"

# create orchestrator user in mysql
init_meta_databases() {
  wait_for_connectivity $meta_mysql_host

  echo "Create MySQL User and Grant Permissions..."
  exists=$(mysql -h $meta_mysql_host -P $meta_mysql_port -u $meta_mysql_username -p$meta_mysql_password -s -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = $meta_user);")

  if [ $exists -eq 0 ]; then
    echo "Create MySQL User and Grant Permissions..."
    mysql -h $meta_mysql_host -P $meta_mysql_port -u $meta_mysql_username -p$meta_mysql_password << EOF
CREATE DATABASE IF NOT EXISTS $meta_database;
CREATE USER '$meta_user'@'%' IDENTIFIED BY '$meta_password';
GRANT ALL PRIVILEGES ON `$meta_database`.* TO '$meta_user'@'%';
EOF
  else
    echo "MySQL user '$meta_user' already exists."
  fi
}

wait_for_connectivity() {
  local timeout=600
  local start_time=$(date +%s)
  local current_time

  echo "Checking mysql connectivity to $meta_mysql_host on port $meta_mysql_port ..."
  while true; do
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      echo "Timeout waiting for $host to become available."
      exit 1
    fi
    # Send PING and check for mysql response
    if  mysqladmin -h "$meta_mysql_host" -P $meta_mysql_port -u "$meta_mysql_username" -p"$meta_mysql_password" PING | grep -q "mysqld is alive"; then
      echo "$meta_mysql_host is reachable."
      break
    fi

    sleep 5
  done
}


wait_for_connectivity
create_mysql_user
