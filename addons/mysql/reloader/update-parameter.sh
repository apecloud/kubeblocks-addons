#!/bin/sh
set -e

function mysql_exec() {
    local query="$1"
    mysql --user=${MYSQL_ADMIN_USER} --password=${MYSQL_ADMIN_PASSWORD} --host=127.0.0.1 -P 3306 -NBe "${query}"
}

paramName="${1:?missing param name}"
paramValue="${2:?missing value}"

if echo "${paramName}" | grep -q "^loose_"; then
    paramName=$(echo "${paramName}" | sed 's/^loose_//')
fi

mysql_exec "SET GLOBAL ${paramName}=${paramValue};"