#!/usr/bin/env bash

set -x

function info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

mysql_exec="mysql -h ${FE_DISCOVERY_ADDR} -P 9030 -u${STARROCKS_USER} -p${STARROCKS_PASSWORD}"

warehouse=${WAREHOUSE_NAME}
if [ -z "${warehouse}" ]; then
    info "No warehouse name specified, skip drop warehouse"
    exit 0
fi

if [ "${warehouse}" == "default_warehouse" ]; then
    info "Default warehouse can not be dropped"
    exit 0
fi

${mysql_exec} -e "drop warehouse ${warehouse}"

