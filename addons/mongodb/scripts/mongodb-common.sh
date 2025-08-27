#!/bin/bash
# shellcheck disable=SC2086

function wait_restore_completion_by_cluster_cr() {
    local max_retries=$1
    local wait_interval=5
    local retries=0

    while true; do
        cluster_json=$(kubectl get clusters.apps.kubeblocks.io "${CLUSTER_NAME}" -n "${CLUSTER_NAMESPACE}" -o json 2>&1)
        kubectl_get_exit_code=$?
        if [ "$kubectl_get_exit_code" -ne 0 ]; then
            echo "INFO: Cluster ${CLUSTER_NAME} not found, sleep $wait_interval second and retry..."
            sleep $wait_interval
            ((retries++))
            if [[ -n "$max_retries" && "$retries" -ge "$max_retries" ]]; then
                echo "ERROR: Reached maximum retries ($max_retries) while waiting for cluster."
                exit 1
            fi
            continue
        fi

        restore_from_backup=$(echo "$cluster_json" | jq -r '.metadata.annotations["kubeblocks.io/restore-from-backup"] // empty')
        if [ -z "$restore_from_backup" ]; then
            # echo "INFO: No restore-from-backup annotation, do not need to restore."
            return 0
        else
            echo "INFO: Waiting for restore completion..."
            sleep $wait_interval
            ((retries++))
            if [[ -n "$max_retries" && "$retries" -ge "$max_retries" ]]; then
                echo "ERROR: Reached maximum retries ($max_retries) while waiting for restore completion."
                exit 1
            fi
        fi
    done
    return 0
}

function kill_process() {
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

function process_restore_signal() {
    local process="$1"
    local target_signal="$2"
    local pbm_backupfile=$MONGODB_ROOT/tmp/mongodb_pbm.backup
    restore_signal_cm_name="$CLUSTER_NAME-restore-signal" 
    restore_signal_cm_namespace="$CLUSTER_NAMESPACE"
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
                if [[ "$process" == mongos* ]]; then
                    kill_process "mongos"
                else
                    kill_process "pbm-agent-entrypoint"
                    kill_process "pbm-agent"
                    kill_process "mongod"
                fi
                wait
                if [ -f "$pbm_backupfile" ]; then
                    echo "INFO: Removing backup file $pbm_backupfile"
                    rm "$pbm_backupfile"
                fi
                exec $process
                exit 0
            else
                echo "INFO: Restore signal is $annotation_value, bad signal, exiting."
                exit 1
            fi
        fi
        sleep 1
    done
}

function boot_or_enter_restore() {
    local process="$1"
    local wait_interval=5
    local max_retries=12
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        cluster_json=$(kubectl get clusters.apps.kubeblocks.io ${CLUSTER_NAME} -n ${CLUSTER_NAMESPACE} -o json 2>&1)
        kubectl_get_exit_code=$?
        if [ "$kubectl_get_exit_code" -ne 0 ]; then
            echo "INFO: Cluster ${CLUSTER_NAME} not found, sleep $wait_interval second and retry... ($((retry_count+1))/$max_retries)"
            sleep $wait_interval
            retry_count=$((retry_count+1))
            continue
        fi

        restore_from_backup=$(echo "$cluster_json" | jq -r '.metadata.annotations["kubeblocks.io/restore-from-backup"] // empty')
        if [ -z "$restore_from_backup" ]; then
            # echo "INFO: No restore-from-backup annotation, do not need to restore."
            exec $process
            exit 0
        else
            break
        fi
    done
    if [ $retry_count -ge $max_retries ]; then
        echo "ERROR: Cluster ${CLUSTER_NAME} not found after $max_retries retries, exiting."
        exit 1
    fi
}

generate_endpoints() {
    local fqdns=$1
    local port=$2

    if [ -z "$fqdns" ]; then
        echo "ERROR: No FQDNs provided." >&2
        exit 1
    fi

    IFS=',' read -ra fqdn_array <<< "$fqdns"
    local endpoints=()

    for fqdn in "${fqdn_array[@]}"; do
        trimmed_fqdn=$(echo "$fqdn" | xargs)
        if [[ -n "$trimmed_fqdn" ]]; then
            endpoints+=("${trimmed_fqdn}:${port}")
        fi
    done

    IFS=','; echo "${endpoints[*]}"
}

function get_mongodb_client_name() {
    local client_name=$(mongosh --version 1>/dev/null&&echo mongosh||echo mongo)
    echo $client_name
}
