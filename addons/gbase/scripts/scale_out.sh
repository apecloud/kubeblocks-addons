#!/bin/bash
# find all node if the cluster installed
echo "KB_POD_LIST  $KB_POD_LIST"
IFS=',' read -r -a KB_POD_ARRAY <<< "$KB_POD_LIST"
for POD_NAME in "${KB_POD_ARRAY[@]}"; do
    POD_FQDN="${POD_NAME}.${KB_CLUSTER_COMP_NAME}-headless.${KB_NAMESPACE}.svc"
    echo "POD_FQDN  $POD_FQDN"
    remote_command="gs_om -t status -h $POD_NAME"
    output=$(timeout 10s sshpass -p "$GBASE_PASSWORD" ssh -o StrictHostKeyChecking=no gbase@$POD_FQDN "$remote_command")
    instance_role=$(echo "$output" | grep -A 20 "node_name\s*:\s*$POD_NAME" | grep "instance_role" | awk '{print $3}')
    echo $output
    echo $instance_role
    if [[ "$instance_role" == "Primary" || "$instance_role" == "Normal" ]]; then
        # Primary = HA mode;  Normal = single node -> HA mode
        # cluster exist , but now node not in cluster, scale out 
        echo "success begin"
        sshpass -p "$GBASE_PASSWORD" ssh -o StrictHostKeyChecking=no root@${KB_CLUSTER_COMP_NAME}-0.${KB_CLUSTER_COMP_NAME}-headless.${KB_NAMESPACE}.svc "/scripts/memberJoin.sh $KB_POD_NAME $KB_POD_IP"  
        echo "success end"
        break
    fi
done

exit 0