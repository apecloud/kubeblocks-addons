#!/bin/bash

set -ex
if [[ -z "$KB_LEAVE_MEMBER_POD_NAME" ]]; then
    echo "no leave member name provided"
    exit 1
fi

if [[ -f /tmp/member_leave.lock ]]; then
    echo "member_leave.sh is already running"
    exit 1
fi

touch /tmp/member_leave.lock
CURRENT_POD_NAME=$(echo "${RABBITMQ_NODENAME}"|grep -oP '(?<=rabbit@).*?(?=\.)')

# the node to leave the cluster
LEAVE_NODE="${RABBITMQ_NODENAME/$CURRENT_POD_NAME/$KB_LEAVE_MEMBER_POD_NAME}"

# the output of rabbitmqctl cluster_status
CLUSTER_STATUS=$(rabbitmqctl cluster_status --formatter table)

# get the list of running nodes
RUNNING_NODES=$(echo "$CLUSTER_STATUS" | grep -A 3 "Running Nodes" | tail -n +3 | grep 'rabbit@')

while read -r line; do
    if [ ! -z "$line" ]; then
        NODES+=("$line")
    fi
done <<< "$RUNNING_NODES"

# found the target node to execute forget_cluster_node
TARGET_NODE=""
for NODE in "${NODES[@]}"; do
    if [[ "$NODE" != "$LEAVE_NODE" ]]; then
        TARGET_NODE=$NODE
        break
    fi
done

if [[ -z "$TARGET_NODE" ]]; then
    echo "no target node found to execute forget_cluster_node."
    exit 1
fi

# execute forget_cluster_node on the target node
rabbitmqctl -n $LEAVE_NODE stop_app
rabbitmqctl -n $TARGET_NODE forget_cluster_node $LEAVE_NODE

rm -f /tmp/member_leave.lock

if [[ $? -eq 0 ]]; then
    echo "Leave member success: $LEAVE_NODE."
else
    echo "leave member failed: $LEAVE_NODE."
    exit 1
fi