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
readonly RETRY_INTERVAL=1

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

# Check whether it is a source file call
is_sourced() {
    [ "${#FUNCNAME[@]}" -ge 2 ] && 
    [ "${FUNCNAME[0]}" = 'is_sourced' ] && 
    [ "${FUNCNAME[1]}" = 'source' ]
}

# Parsing configuration parameters
parse_config() {
    declare -g FE_SERVICE_ADDR CURRENT_BE_FQDN CURRENT_BE_PORT #PRIORITY_NETWORKS
    
    # test-fe-fe
    FE_SERVICE_ADDR="$FE_DISCOVERY_SERVICE_NAME".${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}
    if [ -z "$FE_SERVICE_ADDR" ]; then
        log_error "FE_DISCOVERY_SERVICE_NAME is empty"
    fi

    BE_HEADLESS_SERVICE="${CLUSTER_NAME}-${COMPONENT_NAME}-headless"
    CURRENT_BE_FQDN="${POD_NAME}.${BE_HEADLESS_SERVICE}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
    CURRENT_BE_PORT="${HEARTBEAT_PORT:-9050}"

    # Exporting environment variables
    export FE_SERVICE_ADDR CURRENT_BE_FQDN CURRENT_BE_PORT #PRIORITY_NETWORKS
}

# Check BE status
check_be_status() {
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRY_TIMES ]; do
        if [ "$1" = "true" ]; then
            # Check FE status
            if mysql -u"${DORIS_USER}" -P"${FE_QUERY_PORT}" -h"${FE_SERVICE_ADDR}" \
                -N -e "SHOW FRONTENDS" 2>/dev/null | grep -w "${FE_SERVICE_ADDR}" &>/dev/null; then
                log_info "Master FE is ready"
                return 0
            fi
        else
            # Check BE status
            if mysql -u"${DORIS_USER}" -P"${FE_QUERY_PORT}" -h"${FE_SERVICE_ADDR}" \
                -N -e "SHOW BACKENDS" 2>/dev/null | grep -w "${CURRENT_BE_FQDN}" | grep -w "${CURRENT_BE_PORT}" | grep -w "true" &>/dev/null; then
                log_info "BE node is ready"
                return 0
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $((retry_count % 20)) -eq 1 ]; then
            if [ "$1" = "true" ]; then
                log_info "Waiting for master FE... ($retry_count/$MAX_RETRY_TIMES)"
            else
                log_info "Waiting for BE node... ($retry_count/$MAX_RETRY_TIMES)"
            fi
        fi
        sleep "$RETRY_INTERVAL"
    done
    
    return 1
}

# Processing initialization files
process_init_files() {
    local f
    for f; do
        case "$f" in
            *.sh)
                if [ -x "$f" ]; then
                    log_info "Executing $f"
                    "$f"
                else
                    log_info "Sourcing $f"
                    . "$f"
                fi
                ;;
            *.sql)    
                log_info "Executing SQL file $f"
                mysql -u"${DORIS_USER}" -P"${FE_QUERY_PORT}" -h"${FE_SERVICE_ADDR}" < "$f"
                ;;
            *.sql.gz)  
                log_info "Executing compressed SQL file $f"
                gunzip -c "$f" | mysql -u"${DORIS_USER}" -P"${FE_QUERY_PORT}" -h"${FE_SERVICE_ADDR}"
                ;;
            *)         
                log_warn "Ignoring $f"
                ;;
        esac
    done
}

# Main Function
main() {
    # validate_environment
    parse_config

    # Start BE Node
    {
        set +e
        bash /opt/apache-doris/scripts/init_be.sh 2>/dev/null
    } &

    # Waiting for BE node to be ready
    if ! check_be_status false; then
        log_error "BE node failed to start"
    fi

    # Processing initialization files
    if [ -d "/docker-entrypoint-initdb.d" ]; then
        sleep 15  # Wait for the system to fully boot up
        process_init_files /docker-entrypoint-initdb.d/*
    fi

    # Waiting for BE process
    wait
}

if ! is_sourced; then
    main "$@"
fi
