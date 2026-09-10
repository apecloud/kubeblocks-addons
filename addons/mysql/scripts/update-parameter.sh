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

# MySQL 8.4 removed several system variables. Reject a reconfigure of any of
# them BEFORE the SET GLOBAL / config write, so it fails explicitly with a
# clear reason instead of silently landing in my.cnf and crash-looping the
# instance on the next restart. The SET GLOBAL unknown-variable error below is
# a backstop; this by-name check makes the rejection deterministic and visible.
mysql_84_removed_vars="expire_logs_days default_authentication_plugin binlog_transaction_dependency_tracking transaction_write_set_extraction slave_rows_search_algorithms master_info_repository relay_log_info_repository log_bin_use_v1_row_events"
server_version=$(mysql_exec "SELECT VERSION();" 2>/dev/null | head -n1)
server_major=$(echo "${server_version}" | cut -d. -f1)
server_minor=$(echo "${server_version}" | cut -d. -f2)
if [[ "${server_major}" =~ ^[0-9]+$ ]] && [[ "${server_minor}" =~ ^[0-9]+$ ]]; then
    if [ "${server_major}" -gt 8 ] || { [ "${server_major}" -eq 8 ] && [ "${server_minor}" -ge 4 ]; }; then
        for removed in ${mysql_84_removed_vars}; do
            if [ "${paramName}" = "${removed}" ]; then
                echo "Parameter ${paramName} was removed in MySQL 8.4 and cannot be set on server version ${server_version}; rejecting reconfigure." >&2
                exit 1
            fi
        done
    fi
fi

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

