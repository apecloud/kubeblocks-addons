#!/usr/bin/env bash

function prepare_dirs {
  # log dir
  mkdir -p /home/admin/log/log
  ln -sf /home/admin/log/log ${OB_HOME_DIR}/log

  mkdir -p  ${OB_HOME_DIR}/store
  # data log dir
  mkdir -p /home/admin/data-log/clog

  ln -sf /home/admin/data-log/clog ${OB_HOME_DIR}/store/clog
  mkdir -p /home/admin/data-log/ilog
  ln -sf /home/admin/data-log/ilog ${OB_HOME_DIR}/store/ilog

  mkdir -p /home/admin/data-file/slog
  ln -sf /home/admin/data-file/slog ${OB_HOME_DIR}/store/slog
  mkdir -p /home/admin/data-file/etc
  ln -sf /home/admin/data-file/etc ${OB_HOME_DIR}/store/etc
  mkdir -p /home/admin/data-file/sort_dir
  ln -sf /home/admin/data-file/sort_dir ${OB_HOME_DIR}/store/sort_dir
  mkdir -p /home/admin/data-file/sstable
  ln -sf /home/admin/data-file/sstable ${OB_HOME_DIR}/store/sstable
  # chown -R root:root ${OB_HOME_DIR}

  # link /home/admin/workdir/admin dir to /home/admin/oceanbase/admin
  ln -sf /home/admin/oceanbase/admin ${OB_HOME_DIR}/admin
}

function clean_dirs {
  rm -rf ${OB_HOME_DIR}/etc
  rm -rf ${OB_HOME_DIR}/store/*
  rm -rf /home/admin/data-log/*
  rm -rf /home/admin/data-file/*
  rm -rf /home/admin/log/log
}

function is_recovering {
  if [ -f "/home/admin/workdir/etc/observer.config.bin" ]; then
    echo "True"
  else
    echo "False"
  fi
}

function check_if_ip_changed {
  curr_pod_ip=$(get_pod_ip ${POD_NAME})
  if [ -z "$(cat /home/admin/data-file/etc/observer.conf.bin | grep ${curr_pod_ip})" ]; then
    echo "Changed"
  else
    echo "Not Changed"
  fi
}

function create_ready_flag {
  touch /tmp/ready
}

function wait_for_observer_ready {
  echo "Wait for observer on this node to be ready"
  until nc -z 127.0.0.1 $OB_SERVICE_PORT; do
    echo "observer on this node is not ready, wait for a moment..."
    sleep 10
  done
}

function wait_for_observer_active {
  curr_pod_ip=$(get_pod_ip ${POD_NAME})
  until conn_local_obdb "SELECT * FROM DBA_OB_SERVERS\G"; do
    echo "the server is not ready yet, wait for it..."
    sleep 10
  done

  until [ -n "$(conn_local_obdb "SELECT * FROM DBA_OB_SERVERS WHERE SVR_IP = '${curr_pod_ip}' and STATUS = 'ACTIVE' and START_SERVICE_TIME IS NOT NULL")" ]; do
    echo "Wait for the server to be ready..."
    sleep 10
  done
}

function wait_for_observer_start {
  echo "check if the server has been initialized"
  wait_time=30  # wait up to 30 seconds
  elapsed_time=0
  filename=$OB_HOME_DIR/log/observer.log
  while [ $elapsed_time -lt $wait_time ]; do
    if grep -q 'success to start root service monitor' $filename; then
      echo "oceanbase has been initialized successfully"
      break
    else
      echo "oceanbase is not initialized yet, wait for it..."
      sleep 1
      elapsed_time=$((elapsed_time + 1))
    fi
  done

  if [ $elapsed_time -ge $wait_time ]; then
    echo "Failed to init server exit..."
    exit 1
  fi
}

function get_pod_ip {
  SUBDOMAIN=${OB_COMPONENT_NAME}-headless
  pod_name=${1:?missing pod name}
  if [ "$OB_USE_CLUSTER_IP" = "enabled" ]; then
    # get suffix of pod name
    pod_ordinal=$(echo $pod_name | awk -F '-' '{print $(NF)}')
    # parse service name
    replica_hostname=${OB_COMPONENT_NAME}-ordinal-${pod_ordinal}
  else
    replica_hostname=${pod_name}.${SUBDOMAIN}
  fi
  while true; do
    replica_ip=$(nslookup $replica_hostname | tail -n 2 | grep -P "(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})" --only-matching)
    if [ $? -ne 0 ]; then
      sleep 5
    else
      echo $replica_ip
      break
    fi
  done
}

function start_observer {
  echo "Start observer process as normal server..."
  # if debug mode is enabled, set log level to debug
  local loglevel="INFO"
  # parse the config file
  default_configs='cpu_count=4,memory_limit=8G,system_memory=1G,__min_full_resource_pool_memory=1073741824,datafile_size=40G,log_disk_size=40G,net_thread_count=2,stack_size=512K,cache_wash_threshold=1G,schema_history_expire_time=1d'

  # check if file exists
  if [ -f "/kb-config/oceanbase.conf" ]; then
    echo "observer.conf.bin exists, start observer with existing configs"
    customized_config=$(cat "/kb-config/oceanbase.conf" | sed 's/ \+/ /g' | tr '\n' ',')
    # remove all spaces and the last comma
    customized_config=$(echo "$customized_config"  | sed 's/,$//' | sed 's/^,//')
    echo "customized_config: $customized_config"
    default_configs=$customized_config
  fi

  # get IP address of the current pod
  curr_pod_ip=$(get_pod_ip ${POD_NAME})

  cluster_id=${OB_CLUSTER_ID:-1}

  /home/admin/oceanbase/bin/observer --appname ${OB_COMPONENT_NAME} \
    --cluster_id ${cluster_id} --zone $ZONE_NAME \
    -I ${curr_pod_ip} \
    --rpc_port ${OB_RPC_PORT} \
    --mysql_port ${OB_SERVICE_PORT} \
    -d ${OB_HOME_DIR}/store/ \
    -l "INFO" -o config_additional_dir=${OB_HOME_DIR}/store/etc,${default_configs}
}

function start_observer_with_exsting_configs {
  echo "Start observer with existing configs"
  # Start observer w/o any flags
  /home/admin/oceanbase/bin/observer
}

function update_root_password {
  echo "update root password"
  conn_local_wo_passwd "ALTER USER 'root'@'%' IDENTIFIED BY '${OB_ROOT_PASSWD}';"
  echo "root password has been updated"
}

function get_ob_major_version {
  version=$(/home/admin/oceanbase/bin/observer --version 2>&1  | grep -oP '(\d+\.\d+\.\d+)')
  echo $version
}

function get_ob_full_version {
  version=$(/home/admin/oceanbase/bin/observer --version 2>&1  | grep -oP '(\d+\.\d+\.\d+\.\d+)')
  echo $version
}

function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }
function version_le() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" == "$1"; }
function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }
function version_ge() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; }
function version_eq() {
  version_ge $1 $2
  ret1=$?
  version_le $1 $2
  ret2=$?
  return $(($ret1 || $ret2))
}

function adjust_ob_cluster_ip_feat {
  if [ "$OB_USE_CLUSTER_IP" = "enabled" ]; then
  current_version=$(get_ob_full_version)
  major_version=$(get_ob_major_version)
  # >= 4.2.1.4 && != 4.2.2.x
  # if major_version = 4.2.2, set OB_USE_CLUSTER_IP to disabled
  # if major versioni >= 4.2.3, set OB_USE_CLUSTER_IP to enabled
  # if major version = 4.2.1, and full version > 4.2.1.3, set OB_USE_CLUSTER_IP to enabled
  # otherwise, set OB_USE_CLUSTER_IP to disabled
  if version_eq $major_version  "4.2.2"; then
    OB_USE_CLUSTER_IP="disabled"
  elif version_ge $major_version "4.2.3"; then
    OB_USE_CLUSTER_IP="enabled"
  elif version_eq $major_version "4.2.1"; then
    if version_gt $current_version "4.2.1.3"; then
      OB_USE_CLUSTER_IP="enabled"
    else
      OB_USE_CLUSTER_IP="disabled"
    fi
  else
    OB_USE_CLUSTER_IP="disabled"
  fi
fi
echo "OB_USE_CLUSTER_IP: $OB_USE_CLUSTER_IP"
}

function wait_for_observer_to_term {
# wait for observer to exit
  while true; do
    if [ -z "$(pidof observer)" ]; then
      exit 1
    fi
    sleep 5
  done
}