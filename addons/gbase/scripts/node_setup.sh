#!/bin/bash

LOG_FILE="/config_${KB_CLUSTER_COMP_NAME}.log"

> "$LOG_FILE"

if [ ! -f "$LOG_FILE" ]; then
  touch "$LOG_FILE"
fi

exec > >(tee -a "$LOG_FILE") 2>&1

output=$(sudo -i -u gbase gs_om -t status -h "$KB_POD_NAME" 2>&1)
cluster_state=$(echo "$output" | grep "cluster_state" | awk '{print $3}')
#instance_role=$(echo "$output" | grep "instance_role" | awk '{print $3}')

echo $cluster_state
if [ -z "$cluster_state" ]; then
  # no cluster_state meaning not in cluster or cluster not exist

  # config all nodes trust
  /scripts/set_trust.sh 
  
  /scripts/scale_out.sh
fi

if [ -d "/data/database/install/data/dn" ] && [ "$(ls -A /data/database/install/data/dn)" ]; then
  exit 0
fi

# only node-0 execute install or cluster start 
if [[ ${KB_POD_NAME: -1} == "0" ]]; then
  /scripts/start_replica_cluster.sh
  exit 0
fi


