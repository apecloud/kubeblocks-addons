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

log "$MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER 3306"
wait_for_mysql $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER 3306

#additional_sys_query=$(cat /scripts/sql/addition_to_sys_v5.sql)
#log "mysql version:"
#if [[ $MYSQL_VERSION == "8"* ]]; then
    additional_sys_query=$(cat /scripts/sql/addition_to_sys_v8.sql)
#fi
log "connecting to mysql $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER 3306"
mysql_exec $MYSQL_ROOT_USER $MYSQL_ROOT_PASSWORD $BACKEND_SERVER 3306 "$additional_sys_query" $opt

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