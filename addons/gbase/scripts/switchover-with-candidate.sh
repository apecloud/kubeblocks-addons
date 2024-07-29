#!/bin/bash

switchover_command="gs_ctl switchover -D /data/database/install/data/dn"
echo "switchover begin..."
output=$(timeout 10s sshpass -p "$GBASE_PASSWORD" ssh -o StrictHostKeyChecking=no gbase@$KB_SWITCHOVER_CANDIDATE_FQDN "$switchover_command")
echo $output
role_probe_command="gs_om -t status -h $KB_SWITCHOVER_CANDIDATE_NAME"
output=$(timeout 10s sshpass -p "$GBASE_PASSWORD" ssh -o StrictHostKeyChecking=no gbase@$KB_SWITCHOVER_CANDIDATE_FQDN "$role_probe_command")
primary_count=$(echo "$output" | grep -A 10 "instance_id" | grep "instance_role" | grep -c "Primary")
if [ "$primary_count" -gt 0 ]; then
  echo "switchover successfully"
else
  echo "switchover failed, please check!"
  exit 1
fi