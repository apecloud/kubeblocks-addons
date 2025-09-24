#!/usr/bin/env bash

idx=${POD_NAME##*-}
if [ $idx -ne 0 ]; then
    exit 0
fi

while true; do
    mysql --connect-timeout="1" -h"127.0.0.1" -u"${DORIS_USER}" -P"${FE_QUERY_PORT}" -p"${DORIS_PASSWORD}" -e "select 1"
    if [ $? == 0 ]; then
        break
    fi
    MYSQL_PWD="" mysql --connect-timeout="1" -h"127.0.0.1" -u"${DORIS_USER}" -P"${FE_QUERY_PORT}" -e "SET PASSWORD = PASSWORD('${DORIS_PASSWORD}')"
    if [ $? != 0 ]; then
        log_warn "Failed to set root password"
    fi
    sleep "${RETRY_INTERVAL}"
done