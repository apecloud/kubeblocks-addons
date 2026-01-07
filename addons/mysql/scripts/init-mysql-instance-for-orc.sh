#!/bin/bash
CONNECTION_TIMEOUT=${CONNECTION_TIMEOUT:-600}
SUBDOMAIN=${CLUSTER_COMPONENT_NAME}-headless

# logging functions
mysql_log() {
	local type="$1"; shift
	# accept argument string or stdin
	local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
	local dt; dt="$(date --rfc-3339=seconds)"
	printf '%s [%s] [WRAPPER]: %s\n' "$dt" "$type" "$text"
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

# create orchestrator user in mysql
create_mysql_user() {
  mysql_note "Create MySQL User and Grant Permissions..."

  mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
set SQL_LOG_BIN=off;
CREATE USER IF NOT EXISTS '$ORC_TOPOLOGY_USER'@'%' IDENTIFIED BY '$ORC_TOPOLOGY_PASSWORD';
ALTER USER '$ORC_TOPOLOGY_USER'@'%' IDENTIFIED BY '$ORC_TOPOLOGY_PASSWORD';
GRANT SUPER, PROCESS, REPLICATION SLAVE, REPLICATION CLIENT, RELOAD ON *.* TO '$ORC_TOPOLOGY_USER'@'%';
GRANT SELECT ON mysql.slave_master_info TO '$ORC_TOPOLOGY_USER'@'%';
GRANT DROP ON _pseudo_gtid_.* to '$ORC_TOPOLOGY_USER'@'%';
FLUSH PRIVILEGES;
set SQL_LOG_BIN=on;
EOF

  mysql_note "Create MySQL User and Grant Permissions completed."
}

# Register cluster with alias via HTTP API for MASTER node only
register_cluster_in_orchestrator() {
  # reset slave info if any
  mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
RESET SLAVE;
RESET SLAVE ALL;
EOF

  local instance="${POD_NAME}.${SUBDOMAIN}"
  local cluster_alias="${CLUSTER_NAME}"
  local orchestrator_url="${ORC_ENDPOINTS}" # for example, http://orchestrator:3000

  mysql_note "Registering cluster in Orchestrator"
  mysql_note "  Instance: $instance"
  mysql_note "  Alias: $cluster_alias"

  # First, trigger discovery
  mysql_note "Discovering instance..."
  /scripts/orchestrator-client -c discover -i "$instance" 2>/dev/null || true

  # Wait for discovery and check if instance is registered
  local max_attempts=30
  local attempt=0
  local cluster_info=""

  mysql_note "Waiting for instance to be discovered..."

  while [ $attempt -lt $max_attempts ]; do
    ## check master
    cluster_info=$(/scripts/orchestrator-client -c which-cluster-master -i "$instance" 2>/dev/null) || true

    if [ -n "$cluster_info" ]; then
      mysql_note "Instance successfully discovered and registered"
      break
    fi

    mysql_note "Instance not yet discovered, waiting... (attempt $((attempt + 1))/$max_attempts)"
    sleep 3
    attempt=$((attempt + 1))

    # if attempt mod 10 is 0, then discover the instance
    if [ $((attempt % 10)) -eq 0 ]; then
      /scripts/orchestrator-client -c discover -i "$instance" 2>/dev/null || true
      mysql_note "Discovering instance..."
    fi
  done

  if [ -z "$cluster_info" ]; then
    mysql_error "Instance was not discovered after $max_attempts attempts"
  fi

  # Set alias via API
  curl --silent -X GET "http://${orchestrator_url}/api/set-cluster-alias/${cluster_info}?alias=${cluster_alias}"
  sleep 3
  result=""
  attempt=0
  while [ "$result" != "$cluster_alias" ] && [ $attempt -lt $max_attempts ]; do
    result=$(/scripts/orchestrator-client -c which-cluster-alias -i "${instance}")
    mysql_note "Cluster alias: $result"
    if [ "$result" == "$cluster_alias" ]; then
      break
    fi
    mysql_note "Cluster alias not set yet, waiting... (attempt $((attempt + 1))/$max_attempts)"
    attempt=$((attempt + 1))
    curl --silent -X GET "http://${orchestrator_url}/api/set-cluster-alias/${cluster_info}?alias=${cluster_alias}"
    sleep 3
  done
  if [ $attempt -eq $max_attempts ]; then
    mysql_error "Failed to set cluster alias via API"
  fi
  mysql_note "Cluster alias set successfully: $cluster_alias"
  return 0
}

# wait for mysql to be available
wait_for_connectivity() {
  local timeout=$CONNECTION_TIMEOUT
  local start_time
  local current_time

  start_time=$(date +%s)

  while true; do
    current_time=$(date +%s)
    if (( current_time - start_time > timeout )); then
      mysql_error "Timeout waiting for mysql to be available."
    fi

    # Send SELECT 1 and check for mysql response
    if mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
      mysql_note "mysql is reachable."
      break
    else
      mysql_note "mysql is not reachable yet..."
    fi
    sleep 5
  done
}

init_semi_sync_config() {
  mysql_note "setup semi_sync"
  if [[ "${MYSQL_MAJOR}" == "5.7" ]]; then
    mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
SET GLOBAL slave_net_timeout = 4;
SET GLOBAL rpl_semi_sync_slave_enabled = 1;
SET GLOBAL rpl_semi_sync_master_enabled = 1;
EOF
  else
    mysql -P 3306 -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" --get-server-public-key << EOF
SET GLOBAL slave_net_timeout = 4;
SET GLOBAL rpl_semi_sync_replica_enabled = 1;
SET GLOBAL rpl_semi_sync_source_enabled = 1;
EOF
  fi
}

change_master() {
  local master_host=$1
  local master_port=3306

  mysql_note "Change master"

  if [[ "${MYSQL_MAJOR}" == "5.7" ]]; then
    mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
SET GLOBAL READ_ONLY=1;
SET GLOBAL SUPER_READ_ONLY=1;
STOP SLAVE;
CHANGE MASTER TO
MASTER_AUTO_POSITION=1,
MASTER_CONNECT_RETRY=1,
MASTER_RETRY_COUNT=86400,
MASTER_HOST='$master_host',
MASTER_PORT=$master_port,
MASTER_USER='$MYSQL_ROOT_USER',
MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD';
START SLAVE;
EOF
  else
    mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOF
SET GLOBAL READ_ONLY=1;
SET GLOBAL SUPER_READ_ONLY=1;
STOP SLAVE;
CHANGE MASTER TO
SOURCE_AUTO_POSITION=1,
SOURCE_SSL=1,
MASTER_CONNECT_RETRY=1,
MASTER_RETRY_COUNT=86400,
MASTER_HOST='$master_host',
MASTER_PORT=$master_port,
MASTER_USER='$MYSQL_ROOT_USER',
MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD';
START SLAVE;
EOF
  fi
  mysql_note "CHANGE MASTER successful for $master_host."
}

setup_master_slave() {
  mysql_note "setup_master_slave"

  local timeout=50
  local start_time
  local current_time

  start_time=$(date +%s)

  master_info=$(/scripts/orchestrator-client -c which-cluster-master -alias "${CLUSTER_NAME}")

  while [ -z "$master_info" ]; do
    mysql_note "Waiting for master info..."
    mysql_note "  Instance: $POD_NAME"
    mysql_note "  Cluster: $CLUSTER_NAME"

    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      mysql_error "Timeout waiting for topology info."
    fi

    self_last_digit=${POD_NAME##*-}
    if [ "$self_last_digit" -eq 0 ]; then
      mysql_note "This is the first instance, registering cluster with alias..."
      create_mysql_user
      register_cluster_in_orchestrator
      return 0
    fi

    sleep 5
    mysql_note "Checking topology info."
    master_info=$(/scripts/orchestrator-client -c which-cluster-master -alias "${CLUSTER_NAME}")
  done

  mysql_note "  Master info: $master_info"
  master_from_orc="${master_info%%:*}"
  if [ "$master_from_orc" == "${POD_NAME}.${SUBDOMAIN}" ]; then
    mysql_note "This instance is the master"
    return 0
  fi

  # get all instances from the same cluster as master
  # replicas=$(/scripts/orchestrator-client -c which-cluster-instances -i "${master_info}")


  create_mysql_user
  # init_semi_sync_config
  change_master "$master_from_orc"
  # discover the instance
  attempt=0
  max_attempts=30
  while true; do
    if [ $attempt -gt $max_attempts ]; then
      mysql_error "Timeout waiting for instance to be discovered."
    fi
    cluster_info=$(/scripts/orchestrator-client -c which-cluster -i "${POD_NAME}.${SUBDOMAIN}" 2>/dev/null)
    if [ -n "$cluster_info" ]; then
      break
    fi
    mysql_note "Instance not yet registered, waiting... (attempt $((attempt + 1))/$max_attempts)"
    # discover the instance
    sleep 5
    attempt=$((attempt + 1))

    /scripts/orchestrator-client -c discover -i "${master_from_orc}" 2>/dev/null || true
  done
  return 0
}
