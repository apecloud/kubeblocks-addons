#!/bin/bash

# only cm server exist can use, can future implementation.

switchover_command="cm_ctl switchover -A"

switchover_command="cm_ctl switchover -A"
echo "switchover begin..."
output=$(timeout 10s sshpass -p "$GBASE_PASSWORD" ssh -o StrictHostKeyChecking=no gbase@$KB_LEADER_POD_FQDN "$switchover_command")
echo $output
role_probe_command="gs_om -t status -h $KB_LEADER_POD_NAME "
output=$(timeout 10s sshpass -p "$GBASE_PASSWORD" ssh -o StrictHostKeyChecking=no gbase@$KB_LEADER_POD_FQDN "$role_probe_command")
instance_role=$(echo "$output" | grep -A 20 "node_name\s*:\s*$POD_NAME" | grep "instance_role" | awk '{print $3}')
if [[ "$instance_role" == "Standby" ]]; then
  echo "switchover successfully"
else
  echo "switchover failed, please check!"
  exit 1
fi