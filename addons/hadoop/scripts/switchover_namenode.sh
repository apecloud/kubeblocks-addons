#!/bin/bash

. /opt/scripts/libs/libos.sh
export HADOOP_LOG_DIR=/hadoop/logs
export HADOOP_CONF_DIR=/hadoop/conf
export PATH=$PATH:$HADOOP_HOME/bin
export PATH=$PATH:$HADOOP_HOME/sbin

# CURRENT_POD_NAME defined in the switchover action env
# Check pod role
if [[ "$KB_SWITCHOVER_ROLE" != "active" ]]; then
  echo "Switchover not triggered for non-active role, skipping." >&2
  exit 0
fi

get_server_id(){
  pod_name=$1
  idx=$(echo "$pod_name" | awk -F'-' '{print $NF}')
  echo "nn$idx"
}

pick_standby_namenode(){
  for pod_name in $(echo ${POD_NAME_LIST} | tr ',' '\n'); do
    if [[ "$pod_name" == "$KB_SWITCHOVER_CURRENT_NAME" ]]; then
      continue
    fi
    service_id="$(get_server_id ${pod_name})"
    role=$(hdfs haadmin -getServiceState ${service_id})
    if [[ "$role" == "standby" ]]; then
      echo $service_id
      return
    fi
  done
}

if [ -n "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
  # 1. Switchover to specific candidate
  candidate_id=$(get_server_id "${KB_SWITCHOVER_CANDIDATE_NAME}")
  hdfs haadmin -failover $(get_server_id "${KB_SWITCHOVER_CURRENT_NAME}") ${candidate_id}
  # 2. wait candidate to active

  for i in {1..12}; do
    role=$(hdfs haadmin -getServiceState ${candidate_id})
    echo "$KB_SWITCHOVER_CANDIDATE_NAME: $role"
    if [[ "$role" == "active" ]]; then
      echo "promote active to ${KB_SWITCHOVER_CANDIDATE_NAME} (${candidate_id})" >&2
      exit 0
    fi
    sleep 5
  done
  echo "Promote ${KB_SWITCHOVER_CANDIDATE_NAME} (${candidate_id}) failed: timeout waiting for active state" >&2
  exit 1
else
  # 1. pick a standby namenode to switchover
  candidate_id=$(pick_standby_namenode)
  if [ -z "$candidate_id" ]; then
    echo "No any standby namenode found to switchover, exit 0" >&2
    exit 0
  fi
  # 2. execute switchover
  hdfs haadmin -failover $(get_server_id "${KB_SWITCHOVER_CURRENT_NAME}") ${candidate_id}
fi