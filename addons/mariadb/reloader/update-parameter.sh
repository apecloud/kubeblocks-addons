#!/bin/bash

mariadb_exec() {
    local query="$1"
    mariadb --user="${MARIADB_ROOT_USER}" --password="${MARIADB_ROOT_PASSWORD}" --host=127.0.0.1 -P 3306 -NBe "${query}"
}

param_name="${1:?missing param name}"
param_value="${2:?missing value}"

if [[ "${param_name}" =~ ^loose_ ]]; then
    param_name="${param_name#loose_}"
fi
param_name="$(echo "${param_name}" | tr '-' '_')"

numeric_value=-1
if [[ "${param_value}" =~ ^[0-9]+$ ]]; then
    numeric_value="${param_value}"
fi
if [[ "${numeric_value}" -lt 0 ]]; then
    if [[ "${param_value}" =~ ^([0-9]+)(K|KB|k|kb)$ ]]; then
        numeric_value=$((${BASH_REMATCH[1]} * 1024))
    elif [[ "${param_value}" =~ ^([0-9]+)(M|MB|m|mb)$ ]]; then
        numeric_value=$((${BASH_REMATCH[1]} * 1024 * 1024))
    elif [[ "${param_value}" =~ ^([0-9]+)(G|GB|g|gb)$ ]]; then
        numeric_value=$((${BASH_REMATCH[1]} * 1024 * 1024 * 1024))
    fi
fi

if [[ "${numeric_value}" -ge 0 ]]; then
    output=$(mariadb_exec "SET GLOBAL \`${param_name}\` = ${numeric_value};" 2>&1)
    status=$?
else
    escaped_value="$(printf "%s" "${param_value}" | sed "s/'/''/g")"
    output=$(mariadb_exec "SET GLOBAL \`${param_name}\` = '${escaped_value}';" 2>&1)
    status=$?
fi

if [[ ${status} -ne 0 ]]; then
    if grep -q "ERROR 1045 (28000)" <<<"${output}"; then
        echo "Failed to set parameter ${param_name} to value ${param_value}: ${output}" >&2
        exit 1
    fi
    echo "Skipping parameter ${param_name}=${param_value}: ${output}" >&2
    exit 0
fi

echo "Set parameter ${param_name} to value ${param_value}"
