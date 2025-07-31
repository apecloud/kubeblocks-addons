#!/bin/sh
set -e
paramName="${1:?missing param name}"
paramValue="${2:?missing value}"
paramName=${paramName#--*}
res=$(curl -X PUT -H "Content-Type: application/json" -d"{\"${paramName}\":\"${paramValue}\"}" -s "http://127.0.0.1:${HTTP_PORT}/flags")
echo $res
err_code=$(echo "${res}" | jq -r '.errCode')
if [ "$err_code" != 0 ]; then
    echo "Failed to update parameter ${paramName} with value ${paramValue}"
    exit 1
fi