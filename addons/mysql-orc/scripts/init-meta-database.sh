#!/bin/sh
set -ex
# 定义 MySQL 连接参数
mysql_port="3306"
meta_mysql_user="$META_MYSQL_USER"
meta_mysql_password="$META_MYSQL_PASSWORD"
meta_mysql_host=${META_MYSQL_ENDPOINT%:*}
meta_mysql_port=${META_MYSQL_ENDPOINT#*:}

meta_user="$ORC_META_USER"
meta_password="$ORC_META_PASSWORD"
meta_database="$ORC_META_DATABASE"

# create orchestrator user in mysql
init_meta_databases() {
  wait_for_connectivity $meta_mysql_host


  echo "Create MySQL User and Grant Permissions..."
  mysql -h $meta_mysql_host -P $meta_mysql_port -u $meta_user -p$meta_password << EOF
CREATE USER IF NOT EXISTS '$ORC_META_USER'@'%' IDENTIFIED BY '$ORC_META_PASSWORD';
EOF


  mysql -h $meta_mysql_host -P $meta_mysql_port -u $meta_user -p$meta_password << EOF
CREATE DATABASE IF NOT EXISTS $meta_database;
GRANT ALL PRIVILEGES ON `$meta_database`.* TO '$ORC_META_USER'@'%';
EOF
  echo "init meta databases done"
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
    if  mysqladmin -h "$meta_mysql_host" -P $meta_mysql_port -u "$meta_user" -p"$meta_password" PING | grep -q "mysqld is alive"; then
      echo "$meta_mysql_host is reachable."
      break
    fi

    sleep 5
  done
}

init_meta_databases
echo "script completed scccessfully"