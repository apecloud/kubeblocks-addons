#!/bin/bash
# Script to reload Patroni configuration for PostgreSQL
set -e

process_standby_config() {
    local is_standby
    is_standby=$(echo "${PG_MODE:-}" | tr '[:upper:]' '[:lower:]' | grep -q "standby" && echo "true" || echo "false")
    local patroniurl="http://${CURRENT_POD_IP:-localhost}:8008"
    echo "patroniurl: $patroniurl, isStandby: $is_standby"
    # Get current config
    local result
    local retry_count=0
    local max_retries=5

    while [ $retry_count -lt $max_retries ]; do
        result=$(curl -s ${patroniurl}/config)
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            break
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "Failed to get config, retrying in 10s (attempt $retry_count/$max_retries)..."
            sleep 10
        else
            echo "Failed to get config after $max_retries attempts, giving up."
            return 1
        fi
    done

    echo "Origin patroni config: $result"

    if [[ "$is_standby" == "true" ]]; then
        local primary_endpoint="${primaryEndpoint:-}"
        local env_host=""
        local env_port=""

        if [[ -n "$primary_endpoint" && "$primary_endpoint" == *":"* ]]; then
            env_host=$(echo "$primary_endpoint" | cut -d':' -f1)
            env_port=$(echo "$primary_endpoint" | cut -d':' -f2)
            export STANDBY_HOST="$env_host"
            export STANDBY_PORT="$env_port"
            echo "Set STANDBY_HOST=$env_host, STANDBY_PORT=$env_port from primary_endpoint"
        elif [[ -n "$primary_endpoint" ]]; then
            echo "Invalid primary_endpoint format: $primary_endpoint, expected host:port"
            return 1
        fi

        # Check if we need to patch the config
        if [[ -n "$env_host" && -n "$env_port" ]]; then
            local patch_config="{\"standby_cluster\":{\"create_replica_methods\":[\"basebackup_fast_xlog\"],\"host\":\"$env_host\",\"port\":$env_port}}"
            echo "patch_config: $patch_config"
            curl -X PATCH -d "$patch_config" ${patroniurl}/config
        else
            echo "env_host: $env_host, env_port: $env_port, need_patch: false"
        fi
    else
        # Clear standby config if it exists and we're not in remote backup mode
        echo "Clear standby config"
        curl -X PATCH -d '{"standby_cluster":null}' ${patroniurl}/config
    fi
}

echo -e "\n==== Reload patroni config begin ====\n"
process_standby_config
echo -e "\n==== Reload patroni config done ====\n"
