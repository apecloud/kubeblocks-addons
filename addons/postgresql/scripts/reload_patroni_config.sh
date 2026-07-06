#!/bin/bash
# Script to reload Patroni configuration for PostgreSQL
set -e

# Tunables (overridable for tests)
RELOAD_CONFIG_MAX_RETRIES=${RELOAD_CONFIG_MAX_RETRIES:-5}
RELOAD_CONFIG_RETRY_INTERVAL=${RELOAD_CONFIG_RETRY_INTERVAL:-10}

# PATCH the patroni config and fail loudly on connection errors or non-2xx
# responses (curl -f), instead of printing 'done' over a rejected change.
patch_patroni_config() {
    local patroniurl=$1
    local payload=$2
    local response
    if ! response=$(curl -s -f -X PATCH -d "$payload" "${patroniurl}/config"); then
        echo "ERROR: PATCH ${patroniurl}/config failed (payload: $payload)" >&2
        return 1
    fi
    echo "Patched patroni config: $response"
}

process_standby_config() {
    # PG_MODE decides whether this cluster is a standby. It is injected by the
    # cluster chart; when it is missing entirely, taking the non-standby branch
    # would PATCH standby_cluster:null and silently destroy a standby cluster's
    # replication config — so fail closed instead.
    if [ -z "${PG_MODE:-}" ]; then
        echo "ERROR: PG_MODE is not set; refusing to reconcile standby config (an empty PG_MODE would clear standby_cluster)" >&2
        return 1
    fi

    local is_standby
    is_standby=$(echo "${PG_MODE}" | tr '[:upper:]' '[:lower:]' | grep -q "standby" && echo "true" || echo "false")
    local patroniurl="http://${CURRENT_POD_IP:-localhost}:8008"
    echo "patroniurl: $patroniurl, isStandby: $is_standby"
    # Get current config; the assignment runs in an if-condition so a curl
    # failure feeds the retry loop instead of tripping set -e.
    local result=""
    local retry_count=0
    local max_retries=$RELOAD_CONFIG_MAX_RETRIES

    while [ $retry_count -lt $max_retries ]; do
        if result=$(curl -s -f ${patroniurl}/config) && [ -n "$result" ]; then
            break
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "Failed to get config, retrying in ${RELOAD_CONFIG_RETRY_INTERVAL}s (attempt $retry_count/$max_retries)..."
            sleep "$RELOAD_CONFIG_RETRY_INTERVAL"
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
            patch_patroni_config "$patroniurl" "$patch_config"
        else
            echo "env_host: $env_host, env_port: $env_port, need_patch: false"
        fi
    else
        # Clear standby config if it exists and we're not in remote backup mode
        echo "Clear standby config"
        patch_patroni_config "$patroniurl" '{"standby_cluster":null}'
    fi
}

# This is magic for shellspec ut framework.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

echo -e "\n==== Reload patroni config begin ====\n"
process_standby_config
echo -e "\n==== Reload patroni config done ====\n"
