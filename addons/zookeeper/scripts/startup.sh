#!/bin/bash

myid_file="/bitnami/zookeeper/data/myid"

# Execute entrypoint as usual after obtaining ZOO_SERVER_ID, check ZOO_SERVER_ID in persistent volume via myid, if not present, set based on POD hostname
set_zookeeper_server_id() {
  if [[ -f "$myid_file" ]]; then
    ZOO_SERVER_ID="$(cat $myid_file)"
    export ZOO_SERVER_ID
  else
    SERVICE_ID="${CURRENT_POD_NAME##*-}"
    ZOO_SERVER_ID="$SERVICE_ID"
    export ZOO_SERVER_ID
    echo "$ZOO_SERVER_ID" > $myid_file
  fi
}

compare_version() {
  local op=$1
  local v1=$2
  local v2=$3
  local result

  result=$(echo -e "$v1\n$v2" | sort -V | head -n 1)

  case $op in
    gt) [[ "$result" != "$v1" ]];;
    le) [[ "$result" == "$v1" ]];;
    lt) [[ "$result" != "$v2" ]];;
    ge) [[ "$result" == "$v2" ]];;
  esac
}

set_scripts_path() {
  if [[ -z "${ZOOKEEPER_IMAGE_VERSION}" ]] || compare_version "lt" "${ZOOKEEPER_IMAGE_VERSION%%-*}" "3.6.0"; then
    scripts_path="/opt/bitnami/scripts/zookeeper"
  else
    scripts_path=""
  fi
}

start() {
  set_zookeeper_server_id
  set_scripts_path
  exec "${scripts_path}/entrypoint.sh" "${scripts_path}/run.sh"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
start "$@"