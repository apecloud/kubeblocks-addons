#!/bin/bash

# Execute entrypoint as usual after obtaining ZOO_SERVER_ID
# check ZOO_SERVER_ID in persistent volume via myid
# if not present, set based on POD hostname
if [[ -f "/bitnami/zookeeper/data/myid" ]]; then
  export ZOO_SERVER_ID="$(cat /bitnami/zookeeper/data/myid)"
else
  SERVICE_ID=${CURRENT_POD_NAME##*-}
  export ZOO_SERVER_ID=$SERVICE_ID
  echo $ZOO_SERVER_ID > /bitnami/zookeeper/data/myid
fi

function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }
function version_le() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" == "$1"; }
function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }
function version_ge() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; }


if [ -z "${ZOOKEEPER_IMAGE_VERSION}" ] ||  version_lt "3.6.0" "${ZOOKEEPER_IMAGE_VERSION%%-*}"  ; then
  scripts_path="/opt/bitnami/scripts/zookeeper"
else
  scripts_path=""
fi

exec ${scripts_path}/entrypoint.sh ${scripts_path}/run.sh