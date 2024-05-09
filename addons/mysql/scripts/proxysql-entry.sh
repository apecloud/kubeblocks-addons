#!/bin/bash
set -e

# use the current scrip name while putting log
script_name=${0##*/}

# pid stores the process id of the proxysql process
declare -i pid

if [ $FRONTEND_TLS_ENABLED == "true" ]; then
    cp /var/lib/frontend/server/ca.crt /var/lib/proxysql/proxysql-ca.pem
    cp /var/lib/frontend/server/tls.crt /var/lib/proxysql/proxysql-cert.pem
    cp /var/lib/frontend/server/tls.key /var/lib/proxysql/proxysql-key.pem
fi

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local log_type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$log_type] $msg"
}

# If command has arguments, prepend proxysql
if [ "${1:0:1}" = '-' ]; then
    CMDARG="$@"
fi

# Start ProxySQL with PID 1
exec proxysql -c /etc/custom-config/proxysql.cnf -f $CMDARG &
pid=$!

log "INFO" "Configuring proxysql ..."
/scripts/proxysql/configure-proxysql.sh

log "INFO" "Waiting for proxysql ..."
wait $pid

