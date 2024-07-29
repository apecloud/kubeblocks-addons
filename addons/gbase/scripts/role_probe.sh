#!/bin/bash     
        
remote_command="gs_om -t status -h $HOSTNAME"
output=$(sshpass -p "$GBASE_PASSWORD" ssh -o StrictHostKeyChecking=no gbase@$KB_POD_FQDN "$remote_command")
if [ $? -ne 0 ]; then
    echo -n "role probe error"
    exit 1
fi
instance_role=$(echo "$output" | grep -A 20 "node_name\s*:\s*$POD_NAME" | grep "instance_role" | awk '{print $3}')
if [[ "$instance_role" == "Primary" ]]; then
    echo -n "primary"
else
    echo -n "secondary"
fi


