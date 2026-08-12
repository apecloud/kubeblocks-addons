#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set +x

source /scripts/common.sh

declare -A name_role_map

if [ -z ${KB_LEAVE_MEMBER_POD_NAME} ]; then
  KB_LEAVE_MEMBER_POD_NAME=${1:?"missing leave member pod name"}
fi

# NodeName               NodeRole
# ---------------------- ----------------
# mssql-mssql-0          PRIMARY
# mssql-mssql-1          SECONDARY
# mssql-mssql-2          SECONDARY
#
# (3 rows affected)
function get_all_nodes_role {
  # Clear the array instead of redeclaring it
  name_role_map=()

  sql=$(cat <<EOF
SELECT
    ar.replica_server_name AS NodeName,
    rs.role_desc AS NodeRole
FROM
    sys.availability_replicas ar
JOIN
    sys.dm_hadr_availability_replica_states rs
ON
    ar.replica_id = rs.replica_id;
EOF
)
  # eliminate first 2 lines and last 2 lines
  res=$(MSSQL_LOGIN_TIMEOUT=3 conn_local "$sql" | tail -n +3 | head -n -2)
  while IFS= read -r line; do
    host_name=$(echo "$line" | awk '{print $1}')
    role=$(echo "$line" | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
    # Ensure variables are not empty
    if [ -n "$host_name" ] && [ -n "$role" ]; then
      # Use correct syntax to add to global associative array
      name_role_map["$host_name"]="$role"
    fi
  done <<< "$res"
}

function primary_remove_replica_from_ag {
  remove_pod=$1
  log "Removing replica $remove_pod from AG $DEFAULT_AG_NAME"
  remove_replica_sql=$(cat <<EOF
USE [master]
ALTER AVAILABILITY GROUP $DEFAULT_AG_NAME REMOVE REPLICA ON '$remove_pod';
EOF
  )
  local res exit_code
  res=$(MSSQL_LOGIN_TIMEOUT=3 conn_pod "${primary_name}" "$remove_replica_sql" 2>&1) && exit_code=0 || exit_code=$?
  if [ $exit_code -eq 0 ]; then
    return 0
  fi
  # Idempotent: replica already absent from AG is success (re-entry after a
  # prior successful removal). Msg 35283 = AG does not contain a replica with
  # the specified name.
  if [[ "$res" == *"Msg 35283"* ]] || [[ "$res" == *"does not contain an availability replica"* ]]; then
    log "Replica $remove_pod already absent from AG (idempotent, treating as success)"
    return 0
  fi
  log "Failed to remove replica $remove_pod from AG: $res"
  return $exit_code
}

function get_candidate_node {
  # Get all node names and sort them, then select the smallest one that isn't the primary
  # or the node being removed
  local candidates=()
  IFS=' ' read -r -a pods <<< "$(get_pod_list false)"
  for pod in "${pods[@]}"; do
    if [[ "$pod" != "$KB_LEAVE_MEMBER_POD_NAME" ]]; then
      candidates+=("$pod")
    fi
  done

  # Sort candidates
  IFS=$'\n' sorted_candidates=($(sort <<<"${candidates[*]}"))
  unset IFS

  # Return the smallest candidate if available
  if [[ ${#sorted_candidates[@]} -gt 0 ]]; then
    echo "${sorted_candidates[0]}"
  else
    # If no other candidates available, return empty
    echo ""
  fi
}

########################################################
# main
########################################################

# memberLeave is a synchronous lifecycle action: kbagent caps each invocation
# at 60s and KubeBlocks re-invokes on failure. Each wait below is bounded so a
# single invocation stays well under the cap; on timeout we exit 1 (nothing
# destructive has happened yet — retry-safe) and let the next invocation
# re-observe state and continue.
max_wait_seconds=15
retry_interval=3
start_time=$(date +%s)

while true; do
  primary_name=$(MSSQL_LOGIN_TIMEOUT=3 get_primary_pod_name)
  if [ -n "$primary_name" ]; then
    break
  fi
  now=$(date +%s)
  elapsed=$((now - start_time))
  if [ $elapsed -ge $max_wait_seconds ]; then
    log "memberLeave deferred: primary pod name not resolvable within ${max_wait_seconds}s (retry-safe, next invocation will re-observe)"
    exit 1
  fi
  log "Primary pod name not found, retrying in $retry_interval seconds... (elapsed: $elapsed seconds)"
  sleep $retry_interval
done

log "primary pod name: $primary_name"

# get all nodes role
get_all_nodes_role

log "name_role_map keys: ${!name_role_map[*]}"
for key in "${!name_role_map[@]}"; do
  log "  $key: ${name_role_map[$key]}"
done

# if primary is being scaled in, switch it first
if [ "${name_role_map["$KB_LEAVE_MEMBER_POD_NAME"]}" == "primary" ]; then
  log "Primary $primary_name is being scaled in, switch it first"
  candidate=$(get_candidate_node)
  if [ -z "$candidate" ]; then
    log "No candidate node found for switchover, cannot proceed"
    exit 1
  fi
  log "Selected candidate node for switchover: $candidate"
  /tools/syncerctl switchover --primary "$KB_LEAVE_MEMBER_POD_NAME" --candidate "$candidate"
  role_sql="SET NOCOUNT ON; select role from sys.dm_hadr_availability_replica_states where is_local=1"
  # Bounded demotion wait: 5 polls, ~35s worst case including probe timeouts.
  # Whole-script worst case stays under the kbagent 60s cap. If the leaving
  # pod is still primary after that, defer (exit 1); the next invocation
  # re-reads roles and skips this branch once the switchover has completed.
  max_role_polls=5
  role_poll=0
  role=$(MSSQL_LOGIN_TIMEOUT=3 conn_pod "$KB_LEAVE_MEMBER_POD_NAME" "$role_sql")
  while [ "$role" == "1" ]; do
    role_poll=$((role_poll + 1))
    if [ $role_poll -ge $max_role_polls ]; then
      log "memberLeave deferred: $KB_LEAVE_MEMBER_POD_NAME still primary after $((max_role_polls * 5))s post-switchover (retry-safe, next invocation will re-observe)"
      exit 1
    fi
    log "Waiting for $KB_LEAVE_MEMBER_POD_NAME to become secondary... (${role_poll}/${max_role_polls})"
    sleep 5
    role=$(MSSQL_LOGIN_TIMEOUT=3 conn_pod "$KB_LEAVE_MEMBER_POD_NAME" "$role_sql")
  done
  # The loop also exits when conn_pod fails (role=""), which is not proof of
  # demotion. Only role=2 (SECONDARY) positively confirms it; anything else
  # (empty on connection failure, 0=RESOLVING) is a retry-safe deferral.
  if [ "$role" != "2" ]; then
    log "defer: cannot verify demotion of $KB_LEAVE_MEMBER_POD_NAME (connection failure or unexpected role '${role}'); retry-safe"
    exit 1
  fi

  primary_name=$candidate
  log "new primary pod name: $primary_name"
fi

if ! primary_remove_replica_from_ag "$KB_LEAVE_MEMBER_POD_NAME"; then
  log "Failed to remove replica $KB_LEAVE_MEMBER_POD_NAME from availability group"
  exit 1
fi

log "Member leave operation completed successfully for $KB_LEAVE_MEMBER_POD_NAME"