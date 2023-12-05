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

ZONE_COUNT=${ZONE_COUNT:-3}
WAIT_SERVER_SLEEP_TIME="${WAIT_SERVER_SLEEP_TIME:-3}"
WAIT_K8S_DNS_READY_TIME="${WAIT_K8S_DNS_READY_TIME:-10}"
SVC_NAME="${KB_CLUSTER_COMP_NAME}-headless.${KB_NAMESPACE}.svc"
HOSTNAME=$(hostname)


function get_pod_ip_list {
  # Get the headless service name
  ZONE_SERVER_LIST=""
  RS_LIST=""
  IP_LIST=()

  # Get every replica's IP
  for i in $(seq 0 $(($KB_REPLICA_COUNT-1))); do
    local REPLICA_HOSTNAME="${KB_CLUSTER_COMP_NAME}-${i}"
    local replica_ip=""
    if [ $i -ne $ORDINAL_INDEX ]; then
      while true; do
        echo "nslookup $REPLICA_HOSTNAME.$SVC_NAME"
        nslookup $REPLICA_HOSTNAME.$SVC_NAME | tail -n 2 | grep -P "(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})" --only-matching
        if [ $? -ne 0 ]; then
          echo "$REPLICA_HOSTNAME.$SVC_NAME is not ready yet"
          sleep $WAIT_K8S_DNS_READY_TIME
        else
          break
        fi
      done

      while true; do
        replica_ip=$(nslookup $REPLICA_HOSTNAME.$SVC_NAME | tail -n 2 | grep -P "(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})" --only-matching)
        # check if the IP is empty
        if [ -z "$replica_ip" ]; then
          echo "nslookup $REPLICA_HOSTNAME.$SVC_NAME failed, wait for a moment..."
          sleep $WAIT_K8S_DNS_READY_TIME
        else
          echo "nslookup $REPLICA_HOSTNAME.$SVC_NAME success, IP: $replica_ip"
          break
        fi
      done
    else
      replica_ip=$KB_POD_IP
    fi

    IP_LIST+=("$replica_ip")

    # Construct the ZONE_SERVER_LIST and RS_LIST
    if [ $i -lt $ZONE_COUNT ]; then
      if [ $i -eq 0 ]; then
        ZONE_SERVER_LIST="ZONE 'zone${i}' SERVER '${replica_ip}:2882'"
        RS_LIST="${replica_ip}:2882:2881"
      else
        ZONE_SERVER_LIST="${ZONE_SERVER_LIST},ZONE 'zone${i}' SERVER '${replica_ip}:2882'"
        RS_LIST="${RS_LIST};${replica_ip}:2882:2881"
      fi
    fi
  done

  echo "get_pod_ip_list: ${IP_LIST[*]}"
  echo "rs_list: $RS_LIST"
}

function prepare_dirs {
  mkdir -p /home/admin/log/log
  ln -sf /home/admin/log/log /home/admin/oceanbase/log
  mkdir -p /home/admin/oceanbase/store
  mkdir -p /home/admin/data-log/clog
  ln -sf /home/admin/data-log/clog /home/admin/oceanbase/store/clog
  mkdir -p /home/admin/data-log/ilog
  ln -sf /home/admin/data-log/ilog /home/admin/oceanbase/store/ilog
  mkdir -p /home/admin/data-file/slog
  ln -sf /home/admin/data-file/slog /home/admin/oceanbase/store/slog
  mkdir -p /home/admin/data-file/etc
  ln -sf /home/admin/data-file/etc /home/admin/oceanbase/store/etc
  mkdir -p /home/admin/data-file/sort_dir

  ln -sf /home/admin/data-file/sort_dir /home/admin/oceanbase/store/sort_dir
  mkdir -p /home/admin/data-file/sstable
  ln -sf /home/admin/data-file/sstable /home/admin/oceanbase/store/sstable
  chown -R root:root /home/admin/oceanbase
}

function start_observer {
  echo "Start observer process as normal server..."
  /home/admin/oceanbase/bin/observer --appname ${KB_CLUSTER_COMP_NAME} \
    --cluster_id 1 --zone $ZONE_NAME --devname eth0 \
    -p 2881 -P 2882 -d /home/admin/oceanbase/store/ \
    -l info -o config_additional_dir=/home/admin/oceanbase/store/etc,cpu_count=6,memory_limit=10G,system_memory=1G,__min_full_resource_pool_memory=1073741824,datafile_size=40G,log_disk_size=40G,net_thread_count=2,stack_size=512K,cache_wash_threshold=1G,schema_history_expire_time=1d,enable_separate_sys_clog=false,enable_merge_by_turn=false,enable_syslog_recycle=true,enable_syslog_wf=false,max_syslog_file_count=4
}

function clean_dirs {
  rm -rf /home/admin/oceanbase/store/*
  rm -rf /home/admin/data-log/*
  rm -rf /home/admin/data-file/*
  rm -rf /home/admin/log/log
}

function is_recovering {
  # test whether the config folders and files are empty or not
  if [ -z "$(ls -A /home/admin/data-file)" ]; then
    echo "False"
  else
    echo "True"
  fi
}

function others_running {
  local alive_count=0
  for i in $(seq 0 $(($KB_REPLICA_COUNT-1))); do
    if [ $i -eq $ORDINAL_INDEX ]; then
      continue
    fi
    nc -z ${IP_LIST[$i]} 2881
    if [ $? -ne 0 ]; then
      continue
    fi
    # If at least one server is up, return True
    conn_remote ${IP_LIST[$i]} "show databases" &> /dev/null
    if [ $? -eq 0 ]; then
      alive_count=$(($alive_count+1))
    fi
  done
  # if more than half of the servers are up, return True
  if [ $(($alive_count*2)) -gt ${KB_REPLICA_COUNT} ]; then
    echo "True"
    return
  fi
  echo "False"
  return
}

function bootstrap_obcluster {
  for i in $(seq 0 $(($KB_REPLICA_COUNT-1))); do
    local REPLICA_HOSTNAME="${KB_CLUSTER_COMP_NAME}-${i}"
    local replica_ip=$(nslookup $REPLICA_HOSTNAME.$SVC_NAME | tail -n 2 | grep -P "(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})" --only-matching)

    echo "hostname.svc:" $REPLICA_HOSTNAME.$SVC_NAME "ip:" $replica_ip
    while true; do
      nc -z $replica_ip 2881
      if [ $? -ne 0 ]; then
        echo "Replica $REPLICA_HOSTNAME.$SVC_NAME is not up yet"
        sleep $WAIT_SERVER_SLEEP_TIME
      else
        echo "Replica $REPLICA_HOSTNAME.$SVC_NAME is up"
        break
      fi
    done
  done

  echo "SET SESSION ob_query_timeout=1000000000;"
  conn_local "SET SESSION ob_query_timeout=1000000000;"
  echo "ALTER SYSTEM BOOTSTRAP ${ZONE_SERVER_LIST};"
  conn_local "ALTER SYSTEM BOOTSTRAP ${ZONE_SERVER_LIST};"

  if [ $? -ne 0 ]; then
    # Bootstrap failed, clean the dirs and retry
    echo "Bootstrap failed, please check the store"
    exit 1
  fi

  # Wait for the server to be ready
  sleep $WAIT_SERVER_SLEEP_TIME

  conn_local "show databases"

  conn_local_obdb "SELECT * FROM DBA_OB_SERVERS\g"
}

function add_server {
  echo "add server"
  echo "IP_LIST: ${IP_LIST[*]}"
  # Choose a running server and send the add server request
  for i in $(seq 0 $(($KB_REPLICA_COUNT-1))); do
    if [ $i -eq $ORDINAL_INDEX ]; then
      continue
    fi
    until conn_remote_obdb ${IP_LIST[$i]} "SELECT * FROM DBA_OB_SERVERS\g"; do
      echo "the cluster has not been bootstrapped, wait for them..."
      sleep 10
    done

    local RETRY_MAX=5
    local retry_times=0
    until conn_remote ${IP_LIST[$i]} "ALTER SYSTEM ADD SERVER '${KB_POD_IP}:2882' ZONE '${ZONE_NAME}'"; do
      echo "Failed to add server ${KB_POD_IP}:2882 to the cluster, retry..."
      retry_times=$(($retry_times+1))
      sleep $((3*${retry_times}))
      if [ $retry_times -gt ${RETRY_MAX} ]; then
        echo "Failed to add server ${KB_POD_IP}:2882 to the cluster finally, exit..."
        exit 1
      fi
    done

    until [ -n "$(conn_remote_obdb ${IP_LIST[$i]} "SELECT * FROM DBA_OB_SERVERS WHERE SVR_IP = '${KB_POD_IP}' and STATUS = 'ACTIVE' and START_SERVICE_TIME IS NOT NULL")" ]; do
      echo "Wait for the server to be ready..."
      sleep 10
    done

    echo "Add the server to zone successfully"
    break
  done
}

function check_if_ip_changed {
  echo "check_if_ip_changed"
  echo "IP_LIST: ${IP_LIST[*]}"
  if [ -z "$(cat /home/admin/oceanbase/store/etc/observer.conf.bin | grep \"${KB_POD_IP}\")" ]; then
    echo "Changed"
  else
    echo "Not Changed"
  fi
}

function delete_inactive_servers {
  echo "delete inactive server"
  echo "IP_LIST: ${IP_LIST[*]}"
  for i in $(seq 0 $(($KB_REPLICA_COUNT-1))); do
    if [ $i -eq $ORDINAL_INDEX ]; then
      continue
    fi
    inactive_ips=($(conn_remote_batch ${IP_LIST[$i]} "SELECT SVR_IP FROM DBA_OB_SERVERS WHERE STATUS = 'INACTIVE'" | tail -n +2))
    if [ ${#inactive_ips[@]} -eq 0 ]; then
      echo "No inactive servers"
      break
    fi
    echo "Inactive IPs: ${inactive_ips[*]}"
    for ip in ${inactive_ips[*]}; do
      svr="$ip:2882"
      echo "ALTER SYSTEM DELETE SERVER '$svr'"
      conn_remote ${IP_LIST[$i]} "ALTER SYSTEM DELETE SERVER '$svr'" || true
    done
    break
  done
  echo "Finish deleting inactive servers"
}

function start_observer_with_exsting_configs {
  # Start observer w/o any flags
  /home/admin/oceanbase/bin/observer
}

function create_ready_flag {
  touch /tmp/ready
}
