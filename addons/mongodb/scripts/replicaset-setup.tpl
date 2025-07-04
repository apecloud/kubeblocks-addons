#!/bin/sh

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

cp /etc/mongodb/keyfile $MONGODB_ROOT/keyfile
chmod 600 $MONGODB_ROOT/keyfile

PBM_BACKUPFILE=$MONGODB_ROOT/tmp/mongodb_pbm.backup
CLIENT=`mongosh --version 1>/dev/null&&echo mongosh||echo mongo`
if [ ! -f $PBM_BACKUPFILE ]
then
  echo "INFO: Do not need to restore."
  exec syncer -- mongod --bind_ip_all --port $PORT --replSet $KB_CLUSTER_COMP_NAME --config /etc/mongodb/mongodb.conf
  exit 0
fi

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

process_restore_signal() {
    target_signal="$1"
    restore_signal_cm_name="$KB_CLUSTER_NAME-restore-signal" 
    restore_signal_cm_namespace="$KB_NAMESPACE"
    while true; do
        kubectl_get_result=$(kubectl get configmap $restore_signal_cm_name -n $restore_signal_cm_namespace -o json 2>&1)
        kubectl_get_exit_code=$?
        if [ "$kubectl_get_exit_code" -ne 0 ]; then
            echo "INFO: Waiting for restore signal..."
        else
            annotation_value=$(echo "$kubectl_get_result" | jq -r '.metadata.labels["apps.kubeblocks.io/restore-mongodb-shard"] // empty')
            echo "INFO: Restore signal is $annotation_value."
            if [[ "$annotation_value" == "start" ]]; then
                if [[ "$target_signal" == "start" ]]; then
                    echo "INFO: Restore $annotation_value signal received, starting restore..."
                    break
                fi
            elif [[ "$annotation_value" == "end" ]]; then
                echo "INFO: Restore completed, exiting."
                kill_process "syncer"
                kill_process "mongod"
                kill_process "pbm-agent-entrypoint"
                kill_process "pbm-agent"
                rm $PBM_BACKUPFILE
                exec syncer -- mongod --bind_ip_all --port $PORT --replSet $KB_CLUSTER_COMP_NAME --config /etc/mongodb/mongodb.conf
                exit 0
            else
                echo "INFO: Restore signal is $annotation_value, bad signal, exiting."
                exit 1
            fi
        fi
        sleep 1
    done
}

echo "INFO: Startup backup agent for restore."
pbm-agent-entrypoint &

echo "INFO: Start mongodb for restore."
syncer -- mongod --bind_ip_all --port $PORT --replSet $KB_CLUSTER_COMP_NAME --config /etc/mongodb/mongodb.conf &

process_restore_signal "start"

# syncer affects pbm-agent to shutdown and restart mongod, so we need to kill syncer.
kill_process "syncer"

process_restore_signal "end"