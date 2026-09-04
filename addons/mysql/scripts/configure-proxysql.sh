#!/bin/bash

# use the current scrip name while putting log
script_name=${0##*/}

# used env var from container
# LOAD_BALANCE_MODE - value is either "Galera" or "GroupReplication"

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local log_type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$log_type] $msg"
}

log "" "From $script_name"

# Configs
opt=" -vvv -f "
TIMEOUT="10" # 10 sec timeout to wait for server

# Functions

function mysql_exec() {
    local user="$1"
    local pass="$2"
    local server="$3"
    local port="$4"
    local query="$5"
    local exec_opt="$6"
    pass_ssl=""
    if [ "$BACKEND_TLS_ENABLED" == "true" ]; then
        if [ $port == 3306 ]; then
            pass_ssl="--ssl-ca=/var/lib/certs/ca.crt"
        fi
    fi
    mysql $exec_opt ${pass_ssl} --user=${user} --password=${pass} --host=${server} -P${port} -NBe "${query}"
}

function wait_for_mysql() {
    local user="$1"
    local pass="$2"
    local server="$3"
    local port="$4"

    log "INFO" "Waiting for host $server to be online ..."
    for i in {900..0}; do
        out=$(mysql_exec ${user} ${pass} ${server} ${port} "select 1;")
        if [[ "$out" == "1" ]]; then
            break
        fi

        log "WARNING" "out is ---'$out'--- MySQL is not up yet ... sleeping ...${server}"
        sleep 1
    done

    if [[ "$i" == "0" ]]; then
        log "ERROR" "Server ${server} start failed ..."
        exit 1
    fi
}

function get_writable_mysql_server() {
    local server
    local super_read_only

    IFS=',' read -ra servers <<< "$MYSQL_FQDNS"
    for server in "${servers[@]}"; do
        super_read_only=$(mysql_exec ${MYSQL_ROOT_USER} ${MYSQL_ROOT_PASSWORD} ${server} ${MYSQL_PORT} "select @@global.super_read_only;" 2>/dev/null || true)
        if [[ "$super_read_only" == "0" || "$super_read_only" == "OFF" ]]; then
            echo "$server"
            return 0
        fi
    done

    echo "$BACKEND_SERVER"
}

function is_group_replication_backend() {
    local server="$1"
    local group_name

    group_name=$(mysql_exec ${MYSQL_ROOT_USER} ${MYSQL_ROOT_PASSWORD} ${server} ${MYSQL_PORT} "select @@global.group_replication_group_name;" 2>/dev/null || true)
    [[ -n "$group_name" && "$group_name" != "NULL" ]]
}

function init_group_replication_monitor_view() {
    local server="$1"
    local query

    query=$(cat <<'SQL'
CREATE DATABASE IF NOT EXISTS sys;
USE sys;
DROP VIEW IF EXISTS gr_member_routing_candidate_status;
DROP FUNCTION IF EXISTS gr_member_in_primary_partition;
DROP FUNCTION IF EXISTS gr_transactions_behind;
DROP FUNCTION IF EXISTS gr_transactions_to_cert;
CREATE FUNCTION gr_member_in_primary_partition() RETURNS VARCHAR(3) DETERMINISTIC READS SQL DATA
RETURN (
  SELECT IF(
    MEMBER_STATE = 'ONLINE'
    AND (
      (
        SELECT COUNT(*)
        FROM performance_schema.replication_group_members
        WHERE MEMBER_STATE != 'ONLINE'
      ) >= (
        (
          SELECT COUNT(*)
          FROM performance_schema.replication_group_members
        ) / 2
      ) = 0
    ),
    'YES',
    'NO'
  )
  FROM performance_schema.replication_group_members
    JOIN performance_schema.replication_group_member_stats rgms USING (member_id)
  WHERE rgms.MEMBER_ID = @@SERVER_UUID
);
CREATE FUNCTION gr_transactions_behind() RETURNS INT DETERMINISTIC READS SQL DATA
RETURN (
  SELECT COUNT_TRANSACTIONS_REMOTE_IN_APPLIER_QUEUE
  FROM performance_schema.replication_group_member_stats
  WHERE MEMBER_ID = @@SERVER_UUID
);
CREATE FUNCTION gr_transactions_to_cert() RETURNS INT DETERMINISTIC NO SQL
RETURN 0;
CREATE VIEW gr_member_routing_candidate_status AS
SELECT
  sys.gr_member_in_primary_partition() AS viable_candidate,
  IF(
    (
      SELECT GROUP_CONCAT(variable_value ORDER BY variable_name)
      FROM performance_schema.global_variables
      WHERE variable_name IN ('read_only', 'super_read_only')
    ) != 'OFF,OFF',
    'YES',
    'NO'
  ) AS read_only,
  sys.gr_transactions_behind() AS transactions_behind,
  sys.gr_transactions_to_cert() AS transactions_to_cert;
GRANT SELECT ON sys.gr_member_routing_candidate_status TO 'proxysql'@'%';
GRANT EXECUTE ON FUNCTION sys.gr_member_in_primary_partition TO 'proxysql'@'%';
GRANT EXECUTE ON FUNCTION sys.gr_transactions_behind TO 'proxysql'@'%';
GRANT SELECT ON performance_schema.replication_group_members TO 'proxysql'@'%';
GRANT SELECT ON performance_schema.replication_group_member_stats TO 'proxysql'@'%';
GRANT SELECT ON performance_schema.global_variables TO 'proxysql'@'%';
SQL
)

    log "INFO" "Initializing ProxySQL Group Replication monitor objects on $server"
    mysql_exec ${MYSQL_ROOT_USER} ${MYSQL_ROOT_PASSWORD} ${server} ${MYSQL_PORT} "$query" $opt
}

# if test by shellspec include, just return 0
if [ "${__SOURCED__:+x}" ]; then
  return 0
fi


log "INFO" "backend user=$MYSQL_ROOT_USER server=$BACKEND_SERVER port=$MYSQL_PORT"
wait_for_mysql $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER $MYSQL_PORT

writable_mysql_server=$(get_writable_mysql_server)
mysql_version=$(mysql_exec $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $writable_mysql_server $MYSQL_PORT  'select @@version')

# echo "mysql version $mysql_version"
# if [[ $mysql_version == *"8"* ]]; then
#     additional_sys_query=$(cat /scripts/proxysql/addition_to_sys_v8.sql)
# elif [[ $mysql_version == *"5"* ]]; then
#     additional_sys_query=$(cat /scripts/proxysql/addition_to_sys_v5.sql)
# else
#     log "Unsupported mysql version"
# fi

log "INFO" "connecting to mysql user=$MYSQL_ROOT_USER server=$writable_mysql_server port=$MYSQL_PORT"
if is_group_replication_backend "$writable_mysql_server"; then
    init_group_replication_monitor_view "$writable_mysql_server"
fi
mysql_exec $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $writable_mysql_server $MYSQL_PORT "$additional_sys_query" $opt

# wait for proxysql process to run
wait_for_mysql admin ${PROXYSQL_ADMIN_PASSWORD} 127.0.0.1 6032

log "INFO" "CURRENT CONFIGURATION"

configuration_sql="
show variables;

select * from mysql_group_replication_hostgroups\G;

select rule_id,match_digest,destination_hostgroup from runtime_mysql_query_rules;

select * from runtime_mysql_servers;

select * from runtime_proxysql_servers;

"

mysql -uadmin -p${PROXYSQL_ADMIN_PASSWORD} -h127.0.0.1 -P6032 -vvve "$configuration_sql"

mysql -uadmin -p${PROXYSQL_ADMIN_PASSWORD} -h127.0.0.1 -P6032 -vvve "delete from mysql_query_rules;insert into mysql_query_rules (rule_id,active,match_digest,destination_hostgroup,apply,re_modifiers) values (1,1,'^SELECT.*FOR UPDATE$',1,1,'CASELESS'),(2,1,'^SELECT',2,1,'CASELESS');LOAD MYSQL QUERY RULES TO RUNTIME;SAVE MYSQL QUERY RULES TO DISK;"
# no -vvv here: the statement carries the MySQL root password and must not be echoed to stdout
mysql -uadmin -p${PROXYSQL_ADMIN_PASSWORD} -h127.0.0.1 -P6032 -e "insert or replace into mysql_users (username,password,default_hostgroup) values ('$MYSQL_ROOT_USER','$MYSQL_ROOT_PASSWORD',1);LOAD MYSQL USERS TO RUNTIME;SAVE MYSQL USERS TO DISK;"
if is_group_replication_backend "$writable_mysql_server"; then
    mysql -uadmin -p${PROXYSQL_ADMIN_PASSWORD} -h127.0.0.1 -P6032 -vvve "insert or replace into mysql_group_replication_hostgroups (writer_hostgroup,backup_writer_hostgroup,reader_hostgroup,offline_hostgroup,active,max_writers,writer_is_also_reader,max_transactions_behind,comment) values (1,4,2,3,1,1,0,100,'proxy');LOAD MYSQL SERVERS TO RUNTIME;SAVE MYSQL SERVERS TO DISK;"
    mysql -uadmin -p${PROXYSQL_ADMIN_PASSWORD} -h127.0.0.1 -P6032 -vvve "select * from runtime_mysql_group_replication_hostgroups; select * from mysql_group_replication_hostgroups;"
else
    mysql -uadmin -p${PROXYSQL_ADMIN_PASSWORD} -h127.0.0.1 -P6032 -vvve "insert or replace into mysql_replication_hostgroups (writer_hostgroup,reader_hostgroup,comment) values (1,2,'proxy');LOAD MYSQL SERVERS TO RUNTIME;SAVE MYSQL SERVERS TO DISK;"
    mysql -uadmin -p${PROXYSQL_ADMIN_PASSWORD} -h127.0.0.1 -P6032 -vvve "select * from main.runtime_mysql_replication_hostgroups; select * from main.mysql_replication_hostgroups; select * from mysql_replication_hostgroups;"
fi
