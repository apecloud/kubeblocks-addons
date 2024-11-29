#!/bin/bash


is_node_deleted() {
    local disk_nodes_str=$(echo "$1" | awk '/^Disk Nodes$/{flag=1;next} /^$/{flag++} {if(NF>0 && flag==2){print}}')
    while read -r line; do
        if $(echo "$line" | grep -q "$KB_LEAVE_MEMBER_POD_NAME"); then
            return 1
        fi
    done <<< "$disk_nodes_str"
    return 0
}

cleanup() {
    echo "Cleaning up..."
    rm -f /tmp/member_leave.lock
}

get_target_node() {
    # get the list of running nodes
    RUNNING_NODES=$(echo "$1" | grep -A 3 "Running Nodes" | tail -n +3 | grep 'rabbit@')

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
        return 1
    fi
    echo "$TARGET_NODE"
}

# if test by shellspec include, just return 0
if [ "${__SOURCED__:+x}" ]; then
  return 0
fi

set -ex
if [[ -z "$KB_LEAVE_MEMBER_POD_NAME" ]]; then
    echo "no leave member name provided"
    exit 1
fi

if [[ -f /tmp/member_leave.lock ]]; then
    echo "member_leave.sh is already running"
    exit 1
fi

CURRENT_POD_NAME=$(echo "${RABBITMQ_NODENAME}"|grep -oP '(?<=rabbit@).*?(?=\.)')
if [[ -f /tmp/${KB_LEAVE_MEMBER_POD_NAME}_leave.success ]]; then
    echo "member_leave.sh is already leave success"
    # if the current pod is the leave member pod, exit directly without delete the success file, because the leave member can't execute cluster_status anymore after leave the cluster.
    if [[ "$CURRENT_POD_NAME" == "$KB_LEAVE_MEMBER_POD_NAME" ]]; then
        exit 0
    fi
    rm -f /tmp/${KB_LEAVE_MEMBER_POD_NAME}_leave.success
    exit 0
fi


touch /tmp/member_leave.lock
# Define the cleanup function

# Set the trap to call the cleanup function on script exit
trap cleanup EXIT

# the node to leave the cluster
LEAVE_NODE="${RABBITMQ_NODENAME/$CURRENT_POD_NAME/$KB_LEAVE_MEMBER_POD_NAME}"

# the output of rabbitmqctl cluster_status
CLUSTER_STATUS=$(rabbitmqctl cluster_status --formatter table)

if is_node_deleted "$CLUSTER_STATUS"; then
    echo "Node $KB_LEAVE_MEMBER_POD_NAME has been deleted."
    touch /tmp/${KB_LEAVE_MEMBER_POD_NAME}_leave.success
    exit 0
fi


TARGET_NODE=$(get_target_node "$CLUSTER_STATUS")
if [[ $? -ne 0 ]]; then
    echo "no target node found to execute forget_cluster_node."
    exit 1
fi

# execute forget_cluster_node on the target node
rabbitmqctl -n $LEAVE_NODE stop_app
rabbitmqctl -n $TARGET_NODE forget_cluster_node $LEAVE_NODE

touch /tmp/${KB_LEAVE_MEMBER_POD_NAME}_leave.success

if [[ $? -eq 0 ]]; then
    echo "Leave member success: $LEAVE_NODE."
else
    echo "leave member failed: $LEAVE_NODE."
    exit 1
fi