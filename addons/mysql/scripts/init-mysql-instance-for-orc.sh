#!/bin/sh
set -ex

# logging functions
mysql_log() {
	local type="$1"; shift
	# accept argument string or stdin
	local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
	local dt; dt="$(date --rfc-3339=seconds)"
	printf '%s [%s] [Entrypoint]: %s\n' "$dt" "$type" "$text"
}
mysql_note() {
	mysql_log Note "$@"
}
mysql_warn() {
	mysql_log Warn "$@" >&2
}
mysql_error() {
	mysql_log ERROR "$@" >&2
	exit 1
}


mysql_port="3306"
topology_user="$ORC_TOPOLOGY_USER"
topology_password="$ORC_TOPOLOGY_PASSWORD"


replica_count="$KB_REPLICA_COUNT"
cluster_component_pod_name="$KB_CLUSTER_COMP_NAME"
component_name="$KB_COMP_NAME"
kb_cluster_name="$KB_CLUSTER_NAME"


# create orchestrator user in mysql
create_mysql_user() {
  local service_name=$(echo "${cluster_component_pod_name}_${component_name}_${i}" | tr '-' '_' | tr '[:lower:]' '[:upper:]')

  mysql_note "Create MySQL User and Grant Permissions..."

  mysql -P 3306 -u $MYSQL_ROOT_USER -p$MYSQL_ROOT_PASSWORD << EOF
CREATE USER IF NOT EXISTS '$topology_user'@'%' IDENTIFIED BY '$topology_password';
GRANT SUPER, PROCESS, REPLICATION SLAVE, RELOAD ON *.* TO '$topology_user'@'%';
GRANT SELECT ON mysql.slave_master_info TO '$topology_user'@'%';
GRANT DROP ON _pseudo_gtid_.* to '$topology_user'@'%';
GRANT ALL ON kb_orc_meta_cluster.* TO '$topology_user'@'%';
CREATE USER IF NOT EXISTS 'proxysql'@'%' IDENTIFIED BY 'proxysql';
GRANT SELECT ON performance_schema.* TO 'proxysql'@'%';
GRANT SELECT ON sys.* TO 'proxysql'@'%';
set global slave_net_timeout = 4;
EOF

  mysql_note "Create MySQL User and Grant Permissions completed."

}

init_cluster_info_database() {
  i=$1
  local service_name=$(echo "${cluster_component_pod_name}_${component_name}_${i}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )
  mysql_note "init cluster info database"
  mysql -P 3306 -u $MYSQL_ROOT_USER -p$MYSQL_ROOT_PASSWORD << EOF
CREATE DATABASE IF NOT EXISTS kb_orc_meta_cluster;
EOF
  mysql -P 3306 -u $MYSQL_ROOT_USER -p$MYSQL_ROOT_PASSWORD -e 'source /scripts/cluster-info.sql'
  if [ "${MYSQL_MAJOR}" = '5.7' ]; then
  mysql -P 3306 -u $MYSQL_ROOT_USER -p$MYSQL_ROOT_PASSWORD -e 'source /scripts/addition_to_sys_v5.sql'
  else
  mysql -P 3306 -u $MYSQL_ROOT_USER -p$MYSQL_ROOT_PASSWORD -e 'source /scripts/addition_to_sys_v8.sql'
  fi
  mysql -P 3306 -u $MYSQL_ROOT_USER -p$MYSQL_ROOT_PASSWORD << EOF
USE kb_orc_meta_cluster;
INSERT INTO kb_orc_meta_cluster (anchor,host_name,cluster_name, cluster_domain, data_center)
SELECT 1, '$service_name','$KB_CLUSTER_NAME', '', ''
    WHERE NOT EXISTS (
    SELECT 1
    FROM kb_orc_meta_cluster
    WHERE anchor = 1
);
EOF

}

# wait for mysql to be available
wait_for_connectivity() {
  local timeout=600
  local start_time=$(date +%s)
  local current_time

  mysql_note "Checking mysql connectivity to $host on port $mysql_port ..."
  while true; do
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      mysql_note "Timeout waiting for $host to become available."
      exit 1
    fi

    # Send PING and check for mysql response
    if  mysqladmin -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" PING | grep -q "mysqld is alive"; then
      mysql_note "mysql is reachable."
      break
    fi

    sleep 5
  done
}

setup_master_slave() {
  mysql_note "setup_master_slave"
  master_host_name=$(echo "${cluster_component_pod_name}_${component_name}_0_SERVICE_HOST" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
  master_host=${!master_host_name}
  mysql_note "wait_for_connectivity"
  wait_for_connectivity



  last_digit=${KB_POD_NAME##*-}
  if [[ $last_digit -eq 0 ]]; then
    echo "Create MySQL User and Grant Permissions"
    create_mysql_user
    init_cluster_info_database last_digit

  else
    mysql_note "Wait for master to be ready"
    change_master "$master_host"
  fi
  return 0
}

get_master_from_orc() {
  topology_info=$(/scripts/orchestrator-client -c topology -i $kb_cluster_name)
  if [[ $output =~ ^ERROR ]]; then
      return 1
  fi
  # Extract the first line
  first_line=$(echo "$topology_info" | head -n 1)

  # Remove square brackets and split by comma
  cleaned_line=$(echo "$first_line" | tr -d '[]')

  # Parse the status variables using comma as the delimiter
  old_ifs="$IFS"
  IFS=',' read -ra status_array <<< "$cleaned_line"
  IFS="$old_ifs"

  # Save individual status variables
  lag="${status_array[0]}"
  status="${status_array[1]}"
  version="${status_array[2]}"
  rw="${status_array[3]}"
  mod="${status_array[4]}"
  type="${status_array[5]}"
  GTID="${status_array[6]}"
  GTIDMOD="${status_array[7]}"

  address_port=$(echo "$first_line" | awk '{print $1}')
  address="${address_port%*:}"
  port="${address_port#*:}"

  if [ -n "$address_port" && $status == "ok" ]; then
    master_host="${address_port%:*}"
  fi
}

change_master() {
  mysql_note "Change master"
  master_host=$1
  master_port=3306

  username=$mysql_username
  password=$mysql_password

  mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
SET GLOBAL READ_ONLY=1;
STOP SLAVE;
CHANGE MASTER TO
MASTER_CONNECT_RETRY=1,
MASTER_RETRY_COUNT=86400,
MASTER_HOST='$master_host',
MASTER_PORT=$master_port,
MASTER_USER='$MYSQL_ROOT_USER',
MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD';
START SLAVE;
EOF
  mysql_note "CHANGE MASTER successful for $master_host."

}
main() {
  setup_master_slave
  echo "init mysql instance for orc completed"
}

main
