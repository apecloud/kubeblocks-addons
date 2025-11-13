#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

set -eo pipefail
shopt -s nullglob

# Constant Definition
readonly DORIS_HOME="/opt/apache-doris"
readonly MAX_RETRY_TIMES=60
readonly RETRY_INTERVAL=3
readonly FE_CONFIG_FILE="${DORIS_HOME}/fe/conf/fe.conf"
readonly FOLLOWER_NUMBER=3
readonly BACKUP_DIR="${DORIS_HOME}/fe/doris-meta/ape/backup"

export DATE="$(date +%Y%m%d-%H%M%S)"

cp /etc/config/fe.conf ${FE_CONFIG_FILE}

# Log Function
log_message() {
    local level="$1"
    shift
    local message="$*"
    if [ "$#" -eq 0 ]; then 
        message="$(cat)"
    fi
    local timestamp="$(date -Iseconds)"
    printf '%s [%s] [Entrypoint]: %s\n' "${timestamp}" "${level}" "${message}"
}

log_info() {
    log_message "INFO" "$@"
}

log_warn() {
    log_message "WARN" "$@" >&2
}

log_error() {
    log_message "ERROR" "$@" >&2
    exit 1
}

# Check if the parameter is empty
check_required_param() {
    local param_name="$1"
    local param_value="$2"
    if [ -z "$param_value" ]; then
        log_error "${param_name} is required but not set"
    fi
}

# Check whether it is a source file call
is_sourced() {
    [ "${#FUNCNAME[@]}" -ge 2 ] && 
    [ "${FUNCNAME[0]}" = 'is_sourced' ] && 
    [ "${FUNCNAME[1]}" = 'source' ]
}


# Parsing a comma-delimited string
parse_comma_separated() {
    local input="$1"
    local -n arr=$2  # 使用nameref来存储结果
    local IFS=','
    read -r -a arr <<< "$input"
}

# Configuring the election mode
setup_election_mode() {
    local pod_name_array
    local fqdn_array
    

    parse_comma_separated "$POD_NAME_LIST" pod_name_array
    parse_comma_separated "$POD_FQDN_LIST" fqdn_array

    local fe_edit_log_port="${FE_EDIT_LOG_PORT:-9010}"

    master_fe_ip="${fqdn_array[0]}"
    master_fe_port="${fe_edit_log_port}"
    
    local found=false
    local pod_name="${HOSTNAME}"
    for i in "${!pod_name_array[@]}"; do
        if [[ $i -ge ${FOLLOWER_NUMBER:-3} ]]; then
            is_observer_fe="true"
        fi

        if [[ "${pod_name_array[i]}" == "${pod_name}" ]]; then
            current_fe_ip="${fqdn_array[i]}"
            current_fe_port="${fe_edit_log_port}"
            found=true
            break
        fi
    done

    if [ "$found" = "false" ]; then
        log_info "Could not find configuration for pod '${pod_name}' in POD_FQDN_LIST"
        log_info "The pod may be removed by scale-in Ops"
        local retry_count=0
        while [ "$retry_count" -lt "$MAX_RETRY_TIMES" ]; do
            sleep ${RETRY_INTERVAL}
            retry_count=$((retry_count + 1))
        done 
        log_error "Pod should be removed by scale-in Ops after ${retry_count} retries"
    fi

    is_master_fe=$([[ "$pod_name" == "${pod_name_array[0]}" ]] && echo "true" || echo "false")
}


# Configure the specified mode
setup_assign_mode() {
    master_fe_ip="$FE_MASTER_IP"
    master_fe_port="$FE_MASTER_PORT"
    current_fe_ip="$FE_CURRENT_IP"
    current_fe_port="$FE_CURRENT_PORT"
    
    is_master_fe=$([[ "$master_fe_ip" == "$current_fe_ip" ]] && echo "true" || echo "false")
}

# Add RECOVERY mode configuration function
setup_recovery_mode() {
    # In recovery mode, we need to read the configuration from the metadata
    local meta_dir="${DORIS_HOME}/fe/doris-meta"
    if [ ! -d "$meta_dir" ] || [ -z "$(ls -A "$meta_dir")" ]; then
        log_error "Cannot start in recovery mode: meta directory is empty or does not exist"
    fi
    
    log_info "Starting in recovery mode, using existing meta directory"
    is_master_fe="true"  # In recovery mode, it starts as the master node by default
}

# Configuring FE Nodes
setup_fe_node() {
    declare -g master_fe_ip master_fe_port current_fe_ip current_fe_port
    declare -g is_master_fe

    case $run_mode in
        "ELECTION")
            setup_election_mode
            ;;
        "RECOVERY")
            setup_recovery_mode
            ;;
    esac
    
    # Print key configuration information
    log_info "==== FE Node Configuration ===="
    log_info "Run Mode: ${run_mode}"
    if [ "$run_mode" = "RECOVERY" ]; then
        log_info "Recovery Mode: true"
        log_info "Meta Directory: ${DORIS_HOME}/fe/doris-meta"
    else
        log_info "Is Master: ${is_master_fe}"
        log_info "Is Observer: ${is_observer_fe}"
        log_info "Master FE IP: ${master_fe_ip}"
        log_info "Master FE Port: ${master_fe_port}"
        log_info "Current FE IP: ${current_fe_ip}"
        log_info "Current FE Port: ${current_fe_port}"
        if [ "$run_mode" = "ELECTION" ]; then
            log_info "FE HOST: ${HOSTNAME}"
            log_info "FE Servers: ${POD_FQDN_LIST}"
        fi

    fi
    log_info "=========================="
}

# Start FE node
start_fe() {
    if [ "$run_mode" = "RECOVERY" ]; then
        log_info "Starting FE node in recovery mode"
        ${DORIS_HOME}/fe/bin/start_fe.sh --metadata_failure_recovery
        return
    fi

    if [ "$is_master_fe" = "true" ]; then
        log_info "Starting master FE node"
        ${DORIS_HOME}/fe/bin/start_fe.sh --console
    else
        log_info "Starting follower FE node"
        ${DORIS_HOME}/fe/bin/start_fe.sh --helper "${master_fe_ip}:${master_fe_port}" --console
    fi
}

# Check whether the FE node is registered
check_fe_registered() {
    local query_result
    query_result=$(mysql -uroot -P"${FE_QUERY_PORT}" -h"${master_fe_ip}" -p"${DORIS_PASSWORD}" \
        -N -e "SHOW FRONTENDS" 2>/dev/null | grep -w "${current_fe_ip}" | grep -w "${current_fe_port}" || true)
        
    if [ -n "$query_result" ]; then
        log_info "FE node ${current_fe_ip}:${current_fe_port} is already registered"
        return 0
    fi
    return 1
}

# Check the metadata directory
check_meta_dir() {
    local meta_dir="${DORIS_HOME}/fe/doris-meta"
    if [ -d "$meta_dir/image" ] && [ -n "$(ls -A "$meta_dir/image")" ]; then
        log_info "Meta directory already exists and not empty"
        return 0
    fi
    return 1
}

# Register FE Node
register_fe() {
    if [ "$is_master_fe" = "true" ]; then
        log_info "Master FE node does not need registration"
        return
    fi
    local fe_role=${1:-"FOLLOWER"}
    # First check if the node is registered
    if check_fe_registered; then
        return
    fi

    local retry_count=0
    while [ $retry_count -lt $MAX_RETRY_TIMES ]; do
        if mysql -uroot -P"${FE_QUERY_PORT}" -h"${master_fe_ip}" -p"${DORIS_PASSWORD}" \
            -e "ALTER SYSTEM ADD ${fe_role} '${current_fe_ip}:${current_fe_port}'" 2>/dev/null; then
            log_info "Successfully registered FE node"
            return
        fi
        
        retry_count=$((retry_count + 1))
        if [ $((retry_count % 20)) -eq 1 ]; then
            log_warn "Failed to register FE node, retrying... ($retry_count/$MAX_RETRY_TIMES)"
        fi
        sleep "$RETRY_INTERVAL"
    done
    
    log_error "Failed to register FE node after ${MAX_RETRY_TIMES} attempts"
}

# Cleanup Function
cleanup() {
    log_info "Stopping FE node"
    ${DORIS_HOME}/fe/bin/stop_fe.sh
}

# Config FE TLS
config_fe_tls() {
    if [ -n "$TLS_ENABLED" ] && [ "$TLS_ENABLED" = "true" ]; then
        openssl pkcs12 -inkey /certificates/ca-key.pem -in /etc/pki/tls/ca.pem -export -out /opt/apache-doris/fe/mysql_ssl_default_certificate/ca_certificate.p12 -passout pass:"doris"
        if [ $? -ne 0 ]; then
            log_error "Failed to create CA certificate.p12"
        else
            log_info "Successfully created CA certificate.p12"
        fi
        openssl pkcs12 -inkey /etc/pki/tls/key.pem -in /etc/pki/tls/cert.pem -export -out /opt/apache-doris/fe/mysql_ssl_default_certificate/server_certificate.p12 -passout pass:"doris"
        if [ $? -ne 0 ]; then
            log_error "Failed to create server certificate.p12"
        else
            log_info "Successfully created server certificate.p12"
        fi
    fi
}


# Main Function
main() {
    # validate_environment
    trap cleanup SIGTERM SIGINT
    run_mode="${run_mode:-ELECTION}"

    # if [ -f "${BACKUP_DIR}/.restore" ]; then
    #     log_info "Found .restore file, run_mode set to RECOVERY"
    #     run_mode="RECOVERY"
    #     rm "${BACKUP_DIR}/.restore"
    # fi

    # Config FE TLS
    config_fe_tls

   if [ "$run_mode" = "RECOVERY" ]; then
        setup_fe_node
        start_fe &
        wait $!
    else
        setup_fe_node
        
        # Check the metadata directory
        if check_meta_dir; then
            log_info "Meta directory exists, starting FE directly"
            start_fe &
            wait $!
            return
        fi
        
        # The metadata directory does not exist and needs to be initialized and registered.
        log_info "Initializing meta directory"     
        if [ "$is_observer_fe" = "true" ]; then
            log_info "Register FE Node as OBSERVER.."
            register_fe "OBSERVER"
        else
            register_fe "FOLLOWER"
        fi
        start_fe &
        wait $!
    fi
}

if ! is_sourced; then
    main "$@"
fi
