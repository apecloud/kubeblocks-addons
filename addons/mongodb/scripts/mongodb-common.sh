#!/bin/bash
# shellcheck disable=SC2086

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
