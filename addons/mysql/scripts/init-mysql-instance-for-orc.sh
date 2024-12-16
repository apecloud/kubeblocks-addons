#!/bin/sh
# This script initializes MySQL instances for use with Orchestrator.
# It handles instance configuration, user creation, replication setup,
# and cluster metadata initialization.
set -ex

# Logging functions for different message levels.
# These functions add timestamps and message types to log output.
mysql_log() {
	local type="$1"; shift
	local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
	local dt; dt="$(date --rfc-3339=seconds)"
	printf '%s [%s] [Entrypoint]: %s\n' "$dt" "$type" "$text"
}

# Wrapper functions for different log levels
mysql_note() { mysql_log Note "$@"; }
mysql_warn() { mysql_log Warn "$@" >&2; }
mysql_error() { mysql_log ERROR "$@" >&2; exit 1; }

# Validates that all required environment variables are set.
# Checks for MySQL root credentials and Orchestrator topology user credentials.
validate_env_vars() {
	if [ -z "$MYSQL_ROOT_USER" ] || [ -z "$MYSQL_ROOT_PASSWORD" ]; then
		mysql_error "Required environment variables MYSQL_ROOT_USER or MYSQL_ROOT_PASSWORD not set"
	fi
	if [ -z "$ORC_TOPOLOGY_USER" ] || [ -z "$ORC_TOPOLOGY_PASSWORD" ]; then
		mysql_error "Required environment variables ORC_TOPOLOGY_USER or ORC_TOPOLOGY_PASSWORD not set"
	fi
}

# Creates the Orchestrator topology user and grants necessary permissions.
# This user is used by Orchestrator to monitor and manage MySQL replication.
create_orc_user() {
	mysql_note "Creating orchestrator user and granting permissions..."

	mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
CREATE USER IF NOT EXISTS '$ORC_TOPOLOGY_USER'@'%' IDENTIFIED BY '$ORC_TOPOLOGY_PASSWORD';
GRANT SUPER, PROCESS, REPLICATION SLAVE, RELOAD ON *.* TO '$ORC_TOPOLOGY_USER'@'%';
GRANT SELECT ON mysql.slave_master_info TO '$ORC_TOPOLOGY_USER'@'%';
GRANT DROP ON _pseudo_gtid_.* to '$ORC_TOPOLOGY_USER'@'%';
GRANT ALL ON kb_orc_meta_cluster.* TO '$ORC_TOPOLOGY_USER'@'%';
EOF

	if [ $? -ne 0 ]; then
		mysql_error "Failed to create orchestrator user"
	fi
	mysql_note "Created orchestrator user successfully"
}

# Creates the ProxySQL user and grants required permissions.
# This user is used by ProxySQL to monitor MySQL instances and manage connections.
create_proxy_user() {
	mysql_note "Creating ProxySQL user and granting permissions..."

	mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
CREATE USER IF NOT EXISTS 'proxysql'@'%' IDENTIFIED BY 'proxysql';
GRANT SELECT ON performance_schema.* TO 'proxysql'@'%';
GRANT SELECT ON sys.* TO 'proxysql'@'%';
set global slave_net_timeout = 4;
EOF

	if [ $? -ne 0 ]; then
		mysql_error "Failed to create ProxySQL user"
	fi
	mysql_note "Created ProxySQL user successfully"
}

# Initializes the cluster information database.
# Creates and populates the kb_orc_meta_cluster database with cluster metadata.
init_cluster_info_db() {
	local service_name=$1
	mysql_note "Initializing cluster info database..."

	mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
CREATE DATABASE IF NOT EXISTS kb_orc_meta_cluster;
EOF

	if [ $? -ne 0 ]; then
		mysql_error "Failed to create kb_orc_meta_cluster database"
	fi

	mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e 'source /scripts/cluster-info.sql'
	if [ $? -ne 0 ]; then
		mysql_error "Failed to import cluster-info.sql"
	fi

	mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
USE kb_orc_meta_cluster;
INSERT INTO kb_orc_meta_cluster (anchor,host_name,cluster_name,cluster_domain,data_center)
VALUES (1, '$service_name', '$KB_CLUSTER_NAME', '', '')
ON DUPLICATE KEY UPDATE
	cluster_name = VALUES(cluster_name),
	cluster_domain = VALUES(cluster_domain),
	data_center = VALUES(data_center);
EOF

	if [ $? -ne 0 ]; then
		mysql_error "Failed to insert cluster info"
	fi
	mysql_note "Initialized cluster info database successfully"
}

# Waits for MySQL to become available.
# Repeatedly attempts to connect until success or timeout.
wait_for_mysql() {
	local timeout=600
	local start_time=$(date +%s)
	local current_time

	mysql_note "Waiting for MySQL to be available..."
	while true; do
		current_time=$(date +%s)
		if [ $((current_time - start_time)) -gt $timeout ]; then
			mysql_error "Timeout waiting for MySQL to be available"
		fi

		if mysqladmin -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" ping &>/dev/null; then
			mysql_note "MySQL is now available"
			break
		fi
		sleep 5
	done
}

# Retrieves master information from Orchestrator.
# Queries Orchestrator's topology API and parses the response to find the current master.
get_master_from_orc() {
	local timeout=50
	local start_time=$(date +%s)
	local current_time

	while true; do
		current_time=$(date +%s)
		if [ $((current_time - start_time)) -gt $timeout ]; then
			mysql_note "Timeout waiting for master info from orchestrator"
			return 0
		fi

		topology_info=$(/scripts/orchestrator-client -c topology -i "$KB_CLUSTER_NAME") || true
		if [ -z "$topology_info" ] || [[ $topology_info =~ ^ERROR ]]; then
			return 0
		fi

		parse_topology_info "$topology_info"
		if [ -n "$master_from_orc" ] && [ "$status" = "ok" ]; then
			break
		fi
		sleep 5
	done
	return 0
}

# Parses topology information from Orchestrator's response.
# Extracts status information and master node details from the topology output.
parse_topology_info() {
	local topology_info=$1

	# Extract first line
	local first_line=$(echo "$topology_info" | head -n 1)
	local cleaned_line=$(echo "$first_line" | tr -d '[]')

	# Parse status variables
	IFS=',' read -ra status_array <<< "$cleaned_line"

	lag="${status_array[0]}"
	status="${status_array[1]}"
	version="${status_array[2]}"
	rw="${status_array[3]}"
	mod="${status_array[4]}"
	type="${status_array[5]}"
	GTID="${status_array[6]}"
	GTIDMOD="${status_array[7]}"

	local address_port=$(echo "$first_line" | awk '{print $1}')
	if [ -n "$address_port" ]; then
		master_from_orc="${address_port%:*}"
	fi
}

# Configures MySQL replication with the specified master.
# Sets up GTID-based replication and starts the slave process.
setup_replication() {
	local master_host=$1
	mysql_note "Configuring replication with master $master_host..."

	mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
SET GLOBAL READ_ONLY=1;
STOP SLAVE;
CHANGE MASTER TO
GET_MASTER_PUBLIC_KEY=1,
MASTER_AUTO_POSITION=1,
MASTER_CONNECT_RETRY=1,
MASTER_RETRY_COUNT=86400,
MASTER_HOST='$master_host',
MASTER_PORT=3306,
MASTER_USER='$MYSQL_ROOT_USER',
MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD';
START SLAVE;
EOF

	if [ $? -ne 0 ]; then
		mysql_error "Failed to configure replication"
	fi
	mysql_note "Configured replication successfully"
}

# Main function that coordinates the MySQL instance initialization process.
# Handles environment validation, MySQL availability check, and either
# initializes the first instance or configures replication for subsequent instances.
main() {
	validate_env_vars
	wait_for_mysql

	# Get pod info
	local self_last_digit=${SYNCER_POD_NAME##*-}
	local self_service_name=$(echo "${KB_CLUSTER_COMP_NAME}_MYSQL_${self_last_digit}" | tr '_' '-' | tr '[:upper:]' '[:lower:]')

	# Get master info
	local master_from_orc=""
	get_master_from_orc

	# Initialize first pod or configure replication
	if [ -z "$master_from_orc" ] && [ "$self_last_digit" -eq 0 ]; then
		create_orc_user
		create_proxy_user
		init_cluster_info_db "$self_service_name"
	else
		setup_replication "$master_from_orc"
	fi

	mysql_note "MySQL instance initialization completed successfully"
}

main
