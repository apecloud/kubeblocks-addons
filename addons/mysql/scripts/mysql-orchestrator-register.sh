#!/bin/sh
# This script handles the registration of MySQL instances with Orchestrator.
# It validates required environment variables, gets the first MySQL instance,
# and registers it with the Orchestrator API.
set -ex

# Logging functions for different message levels.
mysql_log() {
  local type="$1"; shift
  local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
  local dt; dt="$(date --rfc-3339=seconds)"
  printf '%s [%s] [Orchestrator]: %s\n' "$dt" "$type" "$text"
}

# Wrapper functions for different log levels
mysql_note() { mysql_log Note "$@"; }
mysql_warn() { mysql_log Warn "$@" >&2; }
mysql_error() { mysql_log ERROR "$@" >&2; exit 1; }

# Validates that all required environment variables are set.
# This includes ORC_ENDPOINTS, ORC_PORTS for Orchestrator connection,
# MYSQL_POD_FQDN_LIST for pod information, and cluster-related variables.
validate_env_vars() {
  if [ -z "$ORC_ENDPOINTS" ] || [ -z "$ORC_PORTS" ]; then
    mysql_error "Required environment variables ORC_ENDPOINTS or ORC_PORTS not set"
  fi
  if [ -z "$MYSQL_POD_FQDN_LIST" ]; then
    mysql_error "Required environment variable MYSQL_POD_FQDN_LIST not set"
  fi
  if [ -z "$KB_CLUSTER_COMP_NAME" ] || [ -z "$KB_NAMESPACE" ]; then
    mysql_error "Required environment variables KB_CLUSTER_COMP_NAME or KB_NAMESPACE not set"
}

# Constructs and returns the Orchestrator endpoint URL by combining
# the host from ORC_ENDPOINTS with the port from ORC_PORTS.
get_orchestrator_endpoint() {
  endpoint=${ORC_ENDPOINTS%%:*}:${ORC_PORTS}
  echo "$endpoint"
}

# Registers a MySQL instance with Orchestrator by making API calls.
# This function will retry the registration for a specified timeout period,
# checking the instance availability through Orchestrator's API.
# If registration succeeds, it logs success; if it times out, it exits with error.
register_to_orchestrator() {
  local host_ip=$1
  local endpoint=$(get_orchestrator_endpoint)
  local url="http://${endpoint}/api/discover/$host_ip/3306"
  local instance_url="http://${endpoint}/api/instance/$host_ip/3306"

  mysql_note "Registering MySQL instance $host_ip to orchestrator..."

  local timeout=100
  local start_time=$(date +%s)
  local current_time
  local response

  while true; do
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      mysql_error "Timeout waiting for $host_ip to become available"
    fi

    # send request to orchestrator for discovery
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    if [ "$response" -eq 200 ]; then
      mysql_note "Registration successful for $host_ip"
      return 0
    fi
    sleep 5
  done
}

# Get first MySQL instance FQDN
get_first_mysql_instance() {
  IFS=',' read -r -a replicas <<< "${MYSQL_POD_FQDN_LIST}"

  local fqdn_name=${replicas[0]}
  local last_digit=${fqdn_name##*-}
  echo "${KB_CLUSTER_COMP_NAME}-mysql-${last_digit}.${KB_NAMESPACE}"
}

# Coordinates the registration of the first MySQL instance with Orchestrator.
# This function validates environment variables, gets the first instance's FQDN,
# and triggers the registration process. It ensures proper error handling and
# logging throughout the process.
register_first_mysql_instance() {
  # Source environment preparation script
  source "$(dirname "$0")/prepare_env.sh"
  validate_env_vars

  local first_mysql_instance
  first_mysql_instance=$(get_first_mysql_instance)

  if [ -z "$first_mysql_instance" ]; then
    mysql_error "Failed to get first MySQL instance FQDN"
  fi

  register_to_orchestrator "$first_mysql_instance"
  mysql_note "First MySQL instance registered successfully"
}

# Main entry point for the script.
# Executes the registration process and ensures proper completion logging.
main() {
  register_first_mysql_instance
  mysql_note "Orchestrator registration completed successfully"
}

main
