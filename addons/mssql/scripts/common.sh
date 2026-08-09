#! /bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

MSSQL_LOGIN_TIMEOUT=${MSSQL_LOGIN_TIMEOUT:-60}
MSSQL_QUERY_TIMEOUT=${MSSQL_QUERY_TIMEOUT:-300}

# Auto-detect sqlcmd path: mssql-tools18 (2022+) vs mssql-tools (2019)
if [ -n "$SQLCMD" ] && [ -f "$SQLCMD" ]; then
  SQLCMD="$SQLCMD"
elif [ -f /opt/mssql-tools18/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools18/bin/sqlcmd
elif [ -f /opt/mssql-tools/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools/bin/sqlcmd
else
  SQLCMD=sqlcmd
fi
export SQLCMD

function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

function conn_local_with_database {
  $SQLCMD -x -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -d "$1" -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -b -Q "$2"
}

function conn_local {
  $SQLCMD -x -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -b -Q "$1"
}

function conn_local_with_database_retry {
  local database_name="$1"
  local sql_command="$2"
  local max_retries=${3:-12}
  local retry_delay=${4:-5}
  local operation_name=${5:-"SQL database operation"}
  local retry_count=0
  local res=""
  local exit_code=0

  while [ "$retry_count" -lt "$max_retries" ]; do
    log "Attempting $operation_name on database '$database_name' (attempt $((retry_count + 1))/$max_retries)"
    res=$(conn_local_with_database "$database_name" "$sql_command" 2>&1)
    exit_code=$?

    if [ "$exit_code" -eq 0 ] && [[ "$res" != *"Msg "* ]] && [[ "$res" != *"Error:"* ]] && [[ "$res" != *"Login failed"* ]]; then
      echo "$res"
      return 0
    fi

    retry_count=$((retry_count + 1))
    if [ "$retry_count" -lt "$max_retries" ]; then
      log "Failed $operation_name on database '$database_name' (exit_code: $exit_code), waiting $retry_delay seconds before retry..."
      log "Error details: $res"
      sleep "$retry_delay"
    fi
  done

  log "Failed $operation_name on database '$database_name' after $max_retries attempts"
  log "Final error: $res"
  return 1
}

# Generic retry function for local SQL Server connections
# Usage: conn_local_with_retry "SQL_COMMAND" [max_retries] [retry_delay] [operation_name] [increase_delay]
function conn_local_with_retry {
  local sql_command="$1"
  local max_retries=${2:-10}
  local retry_delay=${3:-5}
  local operation_name=${4:-"SQL operation"}
  local increase_delay=${5:-true}  # true/false to control delay increment
  local retry_count=0
  local current_delay=$retry_delay

  while [ $retry_count -lt $max_retries ]; do
    log "Attempting $operation_name (attempt $((retry_count + 1))/$max_retries)"

    # Execute SQL command and capture both output and exit code
    local res
    res=$(conn_local "$sql_command" 2>&1)
    local exit_code=$?

    # Check for success conditions
    if [ $exit_code -eq 0 ] && [[ "$res" != *"Msg "* ]] && [[ "$res" != *"Error:"* ]] && [[ "$res" != *"timeout"* ]] && [[ "$res" != *"Login timeout"* ]]; then
      log "Successfully completed $operation_name"
      echo "$res"
      return 0
    fi

    # Check for "already exists" or "already member" type errors that should be treated as success
    local is_already_exists_error=false

    # AG already exists errors
    if [[ "$res" == *"already exists"* ]] || [[ "$res" == *"already a member"* ]] || [[ "$res" == *"already joined"* ]]; then
      is_already_exists_error=true
    fi

    # Msg 35282: Availability replica cannot be added (replica name already exists in AG)
    if [[ "$res" == *"Msg 35282"* ]] || [[ "$res" == *"already contains an availability replica with the specified name"* ]]; then
      is_already_exists_error=true
    fi

    # Msg 41106: Cannot create availability replica (replica already exists on this instance)
    if [[ "$res" == *"Msg 41106"* ]] || [[ "$res" == *"An availability replica of the specified availability group already exists on this instance"* ]]; then
      is_already_exists_error=true
    fi

    # Login already exists errors
    if [[ "$res" == *"already exists"* ]] && [[ "$sql_command" == *"CREATE LOGIN"* ]]; then
      is_already_exists_error=true
    fi

    # AG join specific errors that indicate already joined
    if [[ "$res" == *"is already a member of availability group"* ]] || [[ "$res" == *"replica is already joined"* ]]; then
      is_already_exists_error=true
    fi

    # Database already in AG errors
    if [[ "$res" == *"is already a member of availability group"* ]] && [[ "$sql_command" == *"ADD DATABASE"* ]]; then
      is_already_exists_error=true
    fi

    # Permission already granted errors
    if [[ "$res" == *"already has"* ]] && [[ "$sql_command" == *"GRANT"* ]]; then
      is_already_exists_error=true
    fi

    # Server role membership already exists
    if [[ "$res" == *"is already a member of role"* ]] || [[ "$res" == *"already exists in the current database"* ]]; then
      is_already_exists_error=true
    fi

    if [[ "$res" == *"already exists"* ]] && [[ "$sql_command" == *"CREATE CERTIFICATE"* ]]; then
      is_already_exists_error=true
    fi

    if [[ "$res" == *"already exists"* ]] && [[ "$sql_command" == *"CREATE ENDPOINT"* ]]; then
      is_already_exists_error=true
    fi

    if [[ "$res" == *"already exists"* ]] && [[ "$sql_command" == *"CREATE MASTER KEY"* ]]; then
      is_already_exists_error=true
    fi

    if [ "$is_already_exists_error" = true ]; then
      log "Operation $operation_name completed successfully (resource already exists)"
      log "Details: $res"
      echo "$res"
      return 0
    fi

    # If not a success or "already exists" error, continue with retry logic
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      log "Failed $operation_name (exit_code: $exit_code), waiting $current_delay seconds before retry..."
      log "Error details: $res"
      sleep $current_delay

      # Increase delay for subsequent retries if enabled
      if [ "$increase_delay" = "true" ]; then
        current_delay=$((current_delay + 5))
      fi
    fi
  done

  # All retries exhausted
  log "Failed $operation_name after $max_retries attempts"
  log "Final error: $res"
  return 1
}

function conn_primary {
  $SQLCMD -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P $MSSQL_SA_PASSWORD -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -b -Q "$1"
}

function conn_remote_readonly {
  $SQLCMD -S "$1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -Kreadonly -b -Q "$2"
}

function conn_remote {
  $SQLCMD -S "$1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -h-1 -W -b -Q "$2"
}

function conn_remote_primary {
  $SQLCMD -S "${PRIMARY_HOST},${PRIMARY_PORT}" -U "${PRIMARY_USER:-sa}" -P "${PRIMARY_PASSWORD:-${MSSQL_SA_PASSWORD}}" -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -Q "$1"
}

function conn_pod {
  endpoint="${1}.${KB_CLUSTER_COMP_NAME}-headless"
  suffix=$(get_fqdn_suffix)
  if [ -n "$suffix" ]; then
    endpoint="${endpoint}.$suffix"
  fi
  $SQLCMD -S "${endpoint},${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -h-1 -W -C -b -Q "$2"
}

function get_fqdn_suffix {
  # Purpose: Extract the Kubernetes cluster domain suffix from pod FQDNs
  # Returns: The cluster domain suffix (e.g., "namespace.svc.cluster.local") or empty string if not available

  # Parse pod FQDNs from environment variable by splitting on commas
  IFS=',' read -ra fqdns <<< "${MSSQL_POD_FQDNS:-}"

  # Return empty string if no FQDNs are available
  if [ ${#fqdns[@]} -eq 0 ]; then
    echo ""
    return 0
  fi

  # Take the first FQDN from the array
  local first_fqdn="${fqdns[0]}"

  # Extract domain suffix by removing pod name and headless service parts
  # Example transformation:
  # pod-0.mssql-headless.namespace.svc.cluster.local → namespace.svc.cluster.local
  local suffix="${first_fqdn#*.}"  # Remove pod name (everything before first dot)
  suffix="${suffix#*.}"            # Remove headless service name (everything before next dot)

  echo "${suffix}"
}

function get_pod_fqdns {
  local pod_fqdns
  IFS=',' read -r -a pod_fqdns <<< "${MSSQL_POD_FQDNS:-}"
  echo "${pod_fqdns[@]}"
}

function get_pod_list {
  local show_info=${1:-false}
  # Convert string output to array
  IFS=' ' read -r -a pod_fqdns <<< "$(get_pod_fqdns)"
  local pods=()
  for pod_fqdn in "${pod_fqdns[@]}"; do
    pod_name=$(echo "$pod_fqdn" | cut -d '.' -f 1)
    pods+=("$pod_name")
  done
  if [ "$show_info" == "true" ]; then
    log "pods: ${pods[*]}"
  fi
  echo "${pods[@]}"
}

function get_pod_list_by_fqdns {
  # Accept pod FQDNs as function parameters
  local pod_fqdns=("$@")
  local pods=()
  for pod_fqdn in "${pod_fqdns[@]}"; do
    pod_name=$(echo "$pod_fqdn" | cut -d '.' -f 1)
    pods+=("$pod_name")
  done
  echo "${pods[@]}"
}

function get_primary_pod_name {
  local primary_pod_name
  IFS=' ' read -r -a pods <<< "$(get_pod_list false)"
  local role_sql="SET NOCOUNT ON; select role from sys.dm_hadr_availability_replica_states where is_local=1"
  for pod in "${pods[@]}"; do
    log "Getting role for $pod"
    local role=$(conn_pod "$pod" "$role_sql")
    if [ $? -ne 0 ]; then
      log "Failed to get role from $pod"
      continue
    fi
    if [[ "$role" == "1" ]]; then
      primary_pod_name=${pod}
      break
    fi
  done
  echo "$primary_pod_name"
}

function get_replica_name {
  local pod_dns=$1
  local replica_name=$2

  if [ "${HOST_NETWORK}" == "true" ]; then
    local max_attempts=200
    local attempt=1
    local retry_delay=5

    while [ $attempt -le $max_attempts ]; do
      log "Attempt $attempt/$max_attempts: Getting replica name from $pod_dns"

      #
      # get the server name
      # the response looks like this:
      # tansy-74fb957d7d-mssql-0
      #
      # (1 rows affected)
      #
      local response=$(conn_remote "$pod_dns" "SELECT @@SERVERNAME" 2>&1)
      local exit_code=$?

      if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
        # Check if the response contains error messages like "Login timeout expired"
        if echo "$response" | grep -q "Login timeout expired" || echo "$response" | grep -q "Error:"; then
          log "SQL Server connection error detected: $response"
        else
          # Filter out lines like '(1 rows affected)' and empty lines, trim spaces
          replica_name=$(echo "$response" | awk 'NR==1 {print}' | tr -d '\n' | awk '{gsub(/^ *| *$/, ""); print}')
          if [ -n "$replica_name" ]; then
            # Verify replica name doesn't contain error messages
            if echo "$replica_name" | grep -qv "Error:" && echo "$replica_name" | grep -qv "timeout" && echo "$replica_name" | grep -qv "ODBC"; then
              log "Successfully retrieved replica name: $replica_name"
              break
            else
              log "Invalid replica name contains error text: $replica_name"
              replica_name=""
            fi
          fi
        fi
      fi

      log "Failed to get replica name on attempt $attempt, error: $response, will retry in $retry_delay seconds"
      attempt=$((attempt+1))
      if [ $attempt -le $max_attempts ]; then
        sleep $retry_delay
      fi
    done

    if [ $attempt -gt $max_attempts ]; then
      log "Failed to get replica name after $max_attempts attempts, last error: $response"
    fi
  fi
  echo "$replica_name"
}

function get_primary_pod_host() {
   sql="SET NOCOUNT ON; select role from sys.dm_hadr_availability_replica_states where is_local=1"
   for i in $(seq 0 $((KB_COMP_REPLICAS - 1))); do
     pod_name="${KB_CLUSTER_COMP_NAME}-${i}"
     endpoint="${pod_name}.${KB_CLUSTER_COMP_NAME}-headless"
     suffix=$(get_fqdn_suffix)
     if [ -n "$suffix" ]; then
       endpoint="${endpoint}.$suffix"
     fi
     role=$(conn_remote "${endpoint}" "${sql}")
     if [[ "$role" == "1" ]]; then
       echo ${endpoint}
       break
     fi
   done
}

function get_pod_ip_and_wait_scheduled {
  local pod_svc=$1
  while true; do
    ip=$(ping -c 1 ${pod_svc} | grep PING | awk -F'[()]' '{print $2}')
    if [ ! -z ${ip} ]; then
      echo ${ip}
      break
    fi
    sleep 1
  done
}

function primary_add_replica_to_ag {
  log "primary add replica to ag: $1, primary_host: $2"
  new_pod=$1
  primary_host="$2"
  suffix=$(get_fqdn_suffix)
  new_pod_dns="${new_pod}.$KB_CLUSTER_COMP_NAME-headless"
  if [ -n "$suffix" ]; then
    new_pod_dns="${new_pod_dns}.$suffix"
  fi
  if [ "${HOST_NETWORK}" == "true" ]; then
    new_pod_dns=$(get_pod_ip_and_wait_scheduled ${new_pod_dns})
  fi
  if [ -z "${primary_host}" ]; then
    primary_host="127.0.0.1"
  fi
  # FAILOVER_MODE must match the AG's cluster type or ADD REPLICA is rejected:
  # CLUSTER_TYPE=NONE only accepts MANUAL (Msg 47101), CLUSTER_TYPE=EXTERNAL
  # only accepts EXTERNAL (Msg 47102). Derive it from the AG itself instead of
  # hardcoding, so the script works on clusters created with either type.
  local cluster_type_raw cluster_type failover_mode
  # `|| true` keeps a transient query failure from aborting callers running
  # under `set -e`; the positive match below classifies it as a deferral.
  cluster_type_raw=$(conn_remote "${primary_host}" "SET NOCOUNT ON; SELECT cluster_type_desc FROM sys.availability_groups WHERE name = '$DEFAULT_AG_NAME'" 2>&1) || true
  # tr to uppercase: cluster_type_desc casing varies (observed lowercase "none" on 2022)
  cluster_type=$(echo "$cluster_type_raw" | awk 'NR==1{print}' | tr -d ' \r\n' | tr '[:lower:]' '[:upper:]')
  # Positive match only: anything other than a definite NONE/EXTERNAL answer
  # (connection failure, empty result, error text) is a retry-safe deferral.
  # Guessing here reproduces Msg 47101/47102 on a mismatched cluster type.
  if [ "$cluster_type" == "NONE" ]; then
    failover_mode="MANUAL"
  elif [ "$cluster_type" == "EXTERNAL" ]; then
    failover_mode="EXTERNAL"
  else
    log "defer: cannot determine cluster type of AG $DEFAULT_AG_NAME (observed: '${cluster_type_raw}'); retry-safe"
    return 1
  fi
  log "AG cluster_type=$cluster_type -> FAILOVER_MODE=$failover_mode"
  add_replica_sql=$(cat <<EOF
USE [master]
ALTER AVAILABILITY GROUP $DEFAULT_AG_NAME ADD REPLICA ON '$new_pod'
   WITH (
         ENDPOINT_URL = 'TCP://$new_pod_dns:$MSSQL_HADR_ENDPOINT_PORT',
         PRIMARY_ROLE ( ALLOW_CONNECTIONS = READ_WRITE ),
         SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY ),
         AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
         FAILOVER_MODE = $failover_mode,
         SEEDING_MODE = AUTOMATIC
         );
EOF
  )
  local res exit_code
  res=$(conn_remote "${primary_host}" "$add_replica_sql" 2>&1) && exit_code=0 || exit_code=$?
  if [ $exit_code -eq 0 ]; then
    log "Successfully added replica $new_pod to AG"
    return 0
  fi
  # Idempotent: treat "already exists" as success
  if [[ "$res" == *"already exists"* ]] || [[ "$res" == *"already a member"* ]] || \
     [[ "$res" == *"Msg 35282"* ]] || [[ "$res" == *"Msg 41106"* ]]; then
    log "Replica $new_pod already exists in AG (idempotent, treating as success)"
    return 0
  fi
  log "Failed to add replica $new_pod to AG: $res"
  return $exit_code
}
