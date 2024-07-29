#!/bin/bash

LOG_FILE="/config_${KB_CLUSTER_COMP_NAME}.log"

> "$LOG_FILE"

if [ ! -f "$LOG_FILE" ]; then
  touch "$LOG_FILE"
fi

exec > >(tee -a "$LOG_FILE") 2>&1

echo "root:$GBASE_PASSWORD" | sudo chpasswd
echo "gbase:$GBASE_PASSWORD" | sudo chpasswd

sudo chown -R gbase:gbase /data

/scripts/set_ssh.sh

output=$(sudo -i -u gbase gs_om -t status -h "$KB_POD_NAME" 2>&1)
cluster_state=$(echo "$output" | grep "cluster_state" | awk '{print $3}')
instance_role=$(echo "$output" | grep "instance_role" | awk '{print $3}')

if [[ "$cluster_state" == "Normal" ]]; then
  if [[ "$instance_role" == "Primary" ]]; then
    echo "The cluster_state is Normal and the instance_role is Primary."
    /scripts/start_cluster.sh
  fi
else
  if [[ ${KB_POD_NAME: -1} == "0" ]]; then
    /scripts/start_cluster.sh
  fi
fi

