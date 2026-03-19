#!/bin/bash

function mysql_exec() {
    local query="$1"
    mysql --user="${MYSQL_ADMIN_USER}" --password="${MYSQL_ADMIN_PASSWORD}" --host=127.0.0.1 -P 3306 -NBe "${query}"
}

paramName="${1:?missing param name}"
paramValue="${2:?missing value}"

if echo "${paramName}" | grep -q "^loose_"; then
    paramName=${paramName//"loose_"/}
fi
paramName=$(echo "${paramName}" | tr '-' '_')

var_int=-1
if [[ "${paramValue}" =~ ^[0-9]+$ ]]; then
    var_int="${paramValue}"
fi
if [ "${var_int}" -lt 0 ]; then
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

if [ "${var_int}" -ge 0 ]; then
    ret=$(mysql_exec "SET GLOBAL ${paramName} = ${var_int};" 2>&1)
    status=$?
else
    ret=$(mysql_exec "SET GLOBAL ${paramName} = '${paramValue}';" 2>&1)
    status=$?
fi

if [ $status -ne 0 ]; then
    if echo "${ret}" | grep -q "ERROR 1045 (28000)"; then
        echo "Failed to set parameter ${paramName} to value ${paramValue}, result: ${ret}"
        exit 1
    fi
    # Ignore other errors
else
    echo "Set parameter ${paramName} to value ${paramValue}, result: ${ret}"
fi

