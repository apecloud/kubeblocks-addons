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
paramName=$(echo "${paramName}" | tr '-' '_')

var_int=-1
if [[ "${paramValue}" =~ ^[0-9]+$ ]]; then
    var_int="${paramValue}"
fi
if [ ${var_int} -lt 0 ]; then
    if [[ "${paramValue}" =~ ^([0-9]+)(K|KB|k|kb)$ ]]; then
        number="${BASH_REMATCH[1]}"
        var_int=$((number * 1024))
    elif [[ "${paramValue}" =~ ^([0-9]+)(M|MB|m|mb)$ ]]; then
        number="${BASH_REMATCH[1]}"
        var_int=$((number * 1024 * 1024))
    elif [[ "${paramValue}" =~ ^([0-9]+)(G|GB|g|gb)$ ]]; then
        number="${BASH_REMATCH[1]}"
        var_int=$((number * 1024 * 1024 * 1024))
    fi
fi

if [ ${var_int} -ge 0 ]; then
    mysql_exec "SET GLOBAL ${paramName} = ${var_int};"
else
    mysql_exec "SET GLOBAL ${paramName} = '${paramValue}';"
fi

