#!/bin/bash

function mysql_exec() {
    local query="$1"
    mysql --user="${MYSQL_ADMIN_USER}" --password="${MYSQL_ADMIN_PASSWORD}" --host=127.0.0.1 -P 3306 -NBe "${query}"
}

paramName="${1:?missing param name}"
paramValue="${2:?missing value}"

# loose_-prefixed parameters keep MySQL's loose semantics: absence of the
# variable (plugin not loaded) is tolerated, any other failure is not.
is_loose=false
if echo "${paramName}" | grep -q "^loose_"; then
    paramName=${paramName#loose_}
    is_loose=true
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
    # Reconfigure must not judge success by this single SET GLOBAL alone:
    # some parameters cannot be applied online and legitimately land here.
    # Tolerate exactly those, loudly; fail everything else so the Ops does
    # not report success for a value that was never applied.
    if echo "${ret}" | grep -q "ERROR 1238 "; then
        # Read-only variable: it cannot change online. The framework has
        # already persisted it into the rendered my.cnf, so it takes effect
        # on the next restart.
        echo "Parameter ${paramName} is read-only (ERROR 1238); it will take effect after the next restart."
        exit 0
    fi
    if [ "${is_loose}" = "true" ] && echo "${ret}" | grep -q "ERROR 1193 "; then
        # loose_ parameter whose plugin is not loaded: absence is tolerated
        # by MySQL's loose semantics, mirror that here.
        echo "Parameter loose_${paramName} is unknown on this instance (plugin not loaded); skipped."
        exit 0
    fi
    echo "Failed to set parameter ${paramName} to value ${paramValue}, result: ${ret}" >&2
    exit 1
fi
echo "Set parameter ${paramName} to value ${paramValue}"

