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
    if [ $BACKEND_TLS_ENABLED == "true" ]; then
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

log "$MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER $MYSQL_PORT"
wait_for_mysql $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER $MYSQL_PORT

mysql_version=$(mysql_exec $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER $MYSQL_PORT  'select @@version')

# echo "mysql version $mysql_version"
# if [[ $mysql_version == *"8"* ]]; then
#     additional_sys_query=$(cat /scripts/proxysql/addition_to_sys_v8.sql)
# elif [[ $mysql_version == *"5"* ]]; then
#     additional_sys_query=$(cat /scripts/proxysql/addition_to_sys_v5.sql)
# else
#     log "Unsupported mysql version"
# fi

log "connecting to mysql $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER $MYSQL_PORT"
mysql_exec $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER $MYSQL_PORT "$additional_sys_query" $opt

mysql_exec $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER $MYSQL_PORT << EOF
CREATE USER 'monitor'@'%' IDENTIFIED BY 'monitor';
GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';
EOF
# wait for proxysql process to run
wait_for_mysql admin admin 127.0.0.1 6032

log "INFO" "CURRENT CONFIGURATION"

configuration_sql="
show variables;

select * from mysql_group_replication_hostgroups\G;

select rule_id,match_digest,destination_hostgroup from runtime_mysql_query_rules;

select * from runtime_mysql_servers;

select * from runtime_proxysql_servers;

"

mysql -uadmin -padmin -h127.0.0.1 -P6032 -vvve "$configuration_sql"


mysql -uadmin -padmin -h127.0.0.1 -P6032 -vvve "insert or replace into mysql_users (username,password) values ('$MYSQL_ROOT_USER','$MYSQL_ROOT_PASSWORD');LOAD MYSQL USERS TO RUNTIME;SAVE MYSQL USERS TO DISK;"
mysql -uadmin -padmin -h127.0.0.1 -P6032 -vvve "insert into mysql_replication_hostgroups ( writer_hostgroup, reader_hostgroup, comment) values (2,3,'proxy');load mysql servers to runtime;save mysql servers to disk;"
mysql -uadmin -padmin -h127.0.0.1 -P6032 -vvve "select * from main.runtime_mysql_replication_hostgroups; select * from main.mysql_replication_hostgroups; select * from mysql_replication_hostgroups;"
