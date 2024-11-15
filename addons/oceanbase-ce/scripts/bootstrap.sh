#!/usr/bin/env bash

#
# Copyright (c) 2023 OceanBase
# ob-operator is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#          http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.
#

source /scripts/sql.sh
source /scripts/utils.sh

ZONE_COUNT=${ZONE_COUNT:-3}
OB_HOME_DIR=${OB_HOME_DIR:-/home/admin/oceanbase}
OB_SERVICE_PORT=${OB_SERVICE_PORT:-2881}
OB_RPC_PORT=${OB_RPC_PORT:-2882}
OB_USE_CLUSTER_IP=${OB_USE_CLUSTER_IP:-enabled}
WAIT_SERVER_SLEEP_TIME="${WAIT_SERVER_SLEEP_TIME:-10}"
ORDINAL_INDEX=$(echo $POD_NAME | awk -F '-' '{print $(NF)}')
ZONE_NAME="zone$((${ORDINAL_INDEX}%${ZONE_COUNT}))"

echo "ORDINAL_INDEX: $ORDINAL_INDEX"
echo "ZONE_NAME: $ZONE_NAME"

function others_running {
  local alive_count=0
  local total_count=0
  replicas=$(eval echo ${OB_POD_LIST} | tr ',' '\n')
  for replica in ${replicas}; do
    total_count=$(($total_count+1))
    if [ $replica = $POD_NAME ] ; then
      continue
    fi
    ip=$(get_pod_ip $replica)
    nc -z $ip $OB_SERVICE_PORT
    if [ $? -ne 0 ]; then
      continue
    fi
    conn_remote $ip "show databases" &> /dev/null
    if [ $? -eq 0 ]; then
      alive_count=$(($alive_count+1))
    fi
  done
  # if more than half of the servers are up, return True
  if [ $(($alive_count*2)) -gt ${total_count} ]; then
    echo "True"
    return
  fi
  echo "False"
  return
}

function bootstrap_obcluster {
  ZONE_SERVER_LIST=""
  replicas=$(eval echo ${OB_POD_LIST} | tr ',' '\n')
  ordinal_index=0
  for replica in ${replicas}; do
    # choose the first ZONE_COUNT servers to bootstrap
    if [ $ordinal_index -ge $ZONE_COUNT ]; then
      break
    fi
    replica_ip=$(get_pod_ip $replica)
    while true; do
      nc -z $replica_ip $OB_SERVICE_PORT
      if [ $? -ne 0 ]; then
        echo "Replica $replica_ip is not up yet"
        sleep $WAIT_SERVER_SLEEP_TIME
      else
        echo "Replica $replica_ip is up"
        break
      fi
    done

    if [ $ordinal_index -lt $ZONE_COUNT ]; then
      if [ $ordinal_index -eq 0 ]; then
        ZONE_SERVER_LIST="ZONE 'zone${ordinal_index}' SERVER '${replica_ip}:$OB_RPC_PORT'"
      else
        ZONE_SERVER_LIST="${ZONE_SERVER_LIST},ZONE 'zone${ordinal_index}' SERVER '${replica_ip}:$OB_RPC_PORT'"
      fi
    fi
    ordinal_index=$(($ordinal_index+1))
  done

  echo "zone_server_list: $ZONE_SERVER_LIST"
  echo "ALTER SYSTEM BOOTSTRAP ${ZONE_SERVER_LIST};"
  conn_local_wo_passwd "SET SESSION ob_query_timeout=1000000000;ALTER SYSTEM BOOTSTRAP ${ZONE_SERVER_LIST};"

  if [ $? -ne 0 ]; then
    echo "Bootstrap failed, please check the store"
    exit 1
  fi
  # Wait for the server to be ready
  sleep $WAIT_SERVER_SLEEP_TIME
  conn_local_wo_passwd "SELECT * FROM oceanbase.DBA_OB_SERVERS\G"
  update_root_password
}

function add_server {
  echo "add server"
  curr_pod_ip=$(get_pod_ip ${POD_NAME})

  # Choose the first server and send the add server request
  replica=$(echo "$OB_POD_LIST" | cut -d',' -f1)
  replica_ip=$(get_pod_ip $replica)

  until conn_remote $replica_ip "SELECT * FROM oceanbase.DBA_OB_SERVERS\G"; do
    echo "the cluster has not been bootstrapped, wait for them..."
    sleep 10
  done

  echo "Add server ${curr_pod_ip}:${OB_RPC_PORT} to the cluster"
  until conn_remote $replica_ip "SET SESSION ob_query_timeout=1000000000;ALTER SYSTEM ADD SERVER '${curr_pod_ip}:${OB_RPC_PORT}' ZONE '${ZONE_NAME}'"; do
    echo "Failed to add server ${curr_pod_ip}:$OB_RPC_PORT to the cluster, retry..."
    sleep 10
  done

  echo "Get all ob servers"
  conn_remote $replica_ip "SELECT * FROM oceanbase.DBA_OB_SERVERS"

  until [ -n "$(conn_remote $replica_ip "SELECT * FROM oceanbase.DBA_OB_SERVERS WHERE SVR_IP = '${curr_pod_ip}' and STATUS = 'ACTIVE' and START_SERVICE_TIME IS NOT NULL")" ]; do
    echo "Wait for the server to be ready..."
    sleep 10
  done

  echo "Add the server to zone successfully"
}


function delete_inactive_servers {
  echo "delete inactive server"
  echo "sleep for a while before fetch INACTIVE servers"
  ## default lease time is 10s, so sleep 20s to make sure the server is inactive
  sleep 20
  # Choose the first server and send the add server request
  replica=$(echo "$OB_POD_LIST" | cut -d',' -f1)
  replica_ip=$(get_pod_ip $replica)

  inactive_ips=($(conn_remote_batch $replica_ip  "SELECT SVR_IP FROM DBA_OB_SERVERS WHERE STATUS = 'INACTIVE'" | tail -n +2))
  if [ ${#inactive_ips[@]} -eq 0 ]; then
    echo "No inactive servers"
    return
  fi

  echo "Inactive IPs: ${inactive_ips[*]}"
  for ip in ${inactive_ips[*]}; do
    svr="$ip:$OB_RPC_PORT"
    echo "ALTER SYSTEM DELETE SERVER '$svr'"
    conn_remote $replica_ip "ALTER SYSTEM DELETE SERVER '$svr'" || true
  done
  echo "Finish deleting inactive servers"
}