#!/bin/bash
# shellcheck disable=SC2086

{{- $mongodb_root := getVolumePathByName ( index $.podSpec.containers 0 ) "data" }}
{{- $mongodb_port_info := getPortByName ( index $.podSpec.containers 0 ) "mongodb" }}

# require port
{{- $mongodb_port := 27017 }}
{{- if $mongodb_port_info }}
{{- $mongodb_port = $mongodb_port_info.containerPort }}
{{- end }}

PORT={{ $mongodb_port }}
MONGODB_ROOT={{ $mongodb_root }}
mkdir -p $MONGODB_ROOT/db
mkdir -p $MONGODB_ROOT/logs
mkdir -p $MONGODB_ROOT/tmp
export PATH=$MONGODB_ROOT/tmp/bin:$PATH

client_path=$(whereis mongosh | awk '{print $2}')
CLIENT="mongosh"
if [ -z "$client_path" ]; then
    CLIENT="mongo"
fi

wait_interval=5
while true; do
    cluster_json=$(kubectl get clusters.apps.kubeblocks.io ${KB_CLUSTER_NAME} -n ${KB_NAMESPACE} -o json 2>&1)
    kubectl_get_exit_code=$?
    if [ "$kubectl_get_exit_code" -ne 0 ]; then
        echo "INFO: Cluster ${KB_CLUSTER_NAME} not found, sleep $wait_interval second and retry..."
        sleep $wait_interval
        continue
    fi

    restore_from_backup=$(echo "$cluster_json" | jq -r '.metadata.annotations["kubeblocks.io/restore-from-backup"] // empty')
    if [ -z "$restore_from_backup" ]; then
        echo "INFO: No restore-from-backup annotation, do not need to restore."
        exec syncer -- mongod --bind_ip_all --port $PORT --replSet $KB_CLUSTER_COMP_NAME --config /etc/mongodb/mongodb.conf
        exit 0
    else
        break
    fi
done

kill_process() {
    local process_name="$1"
    local process_pid=$(pgrep -x "$process_name")
    if [ -z "$process_pid" ]; then
        process_pid=$(pgrep -f "$process_name")
    fi
    if [ -n "$process_pid" ]; then
        kill -9 $process_pid
        echo "INFO: kill $process_name with pid $process_pid"
    fi
}

echo "INFO: Startup backup agent for restore."
pbm-agent-entrypoint &

echo "INFO: Start mongodb for restore."
syncer -- mongod --bind_ip_all --port $PORT --replSet $KB_CLUSTER_COMP_NAME --config /etc/mongodb/mongodb.conf &

restore_signal_cm_name="$KB_CLUSTER_NAME-restore-signal" 
restore_signal_cm_namespace="$KB_NAMESPACE"
while true; do
    kubectl_get_result=$(kubectl get configmap $restore_signal_cm_name -n $restore_signal_cm_namespace -o json 2>&1)
    kubectl_get_exit_code=$?
    if [ "$kubectl_get_exit_code" -ne 0 ]; then
        echo "INFO: Waiting for restore signal..."
    else
        annotation_value=$(echo "$kubectl_get_result" | jq -r '.metadata.labels["apps.kubeblocks.io/restore-mongodb-shard"] // empty')
        if [[ "$annotation_value" == "start" ]]; then
            echo "INFO: Restore signal received, starting restore..."
            break
        elif [[ "$annotation_value" == "end" ]]; then
            echo "INFO: Restore completed, exiting."
            kill_process "syncer"
            kill_process "mongod"
            kill_process "pbm-agent-entrypoint"
            kill_process "pbm-agent"
            exec syncer -- mongod --bind_ip_all --port $PORT --replSet $KB_CLUSTER_COMP_NAME --config /etc/mongodb/mongodb.conf
            exit 0
        else
            echo "INFO: Restore signal is $annotation_value, bad signal, exiting."
            exit 1
        fi
    fi
    sleep 1
done

kill_process "syncer"

while true; do
    kubectl_get_result=$(kubectl get configmap $restore_signal_cm_name -n $restore_signal_cm_namespace -o json 2>&1)
    kubectl_get_exit_code=$?
    if [ "$kubectl_get_exit_code" -ne 0 ]; then
        echo "INFO: Waiting for restore signal..."
    else
        annotation_value=$(echo "$kubectl_get_result" | jq -r '.metadata.labels["apps.kubeblocks.io/restore-mongodb-shard"] // empty')
        if [[ "$annotation_value" == "end" ]]; then
            echo "INFO: Restore completed, exiting."
            kill_process "syncer"
            kill_process "mongod"
            kill_process "pbm-agent-entrypoint"
            kill_process "pbm-agent"
            exec syncer -- mongod --bind_ip_all --port $PORT --replSet $KB_CLUSTER_COMP_NAME --config /etc/mongodb/mongodb.conf
            exit 0
        elif [[ "$annotation_value" == "start" ]]; then
            echo "INFO: Restore signal is $annotation_value."
        else
            echo "INFO: Restore signal is $annotation_value, bad signal, exiting."
            exit 1
        fi
    fi
    sleep 1
done
