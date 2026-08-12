#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
set +x
set -eo pipefail

source /scripts/common.sh

if [ -z "${KB_JOIN_MEMBER_POD_NAME}" ]; then
  KB_JOIN_MEMBER_POD_NAME=${1:?"missing join member pod name"}
fi

primary_host=$(get_primary_pod_host)
primary_add_replica_to_ag "$KB_JOIN_MEMBER_POD_NAME" "$primary_host"

# Sync logins to the newly joined replica
log "Syncing logins to new replica: $KB_JOIN_MEMBER_POD_NAME"

# Build the new replica's FQDN
new_replica_fqdn="${KB_JOIN_MEMBER_POD_NAME}.${KB_CLUSTER_COMP_NAME}-headless"
suffix=$(get_fqdn_suffix)
if [ -n "$suffix" ]; then
  new_replica_fqdn="${new_replica_fqdn}.$suffix"
fi

# Generate login script from primary and push to new replica
help_revlogin_sql="/tmp/help_revlogin_join.sql"
if [ -n "$primary_host" ]; then
  conn_remote "$primary_host" "EXEC sp_help_revlogin" > "${help_revlogin_sql}" 2>/dev/null
else
  conn_local "EXEC sp_help_revlogin" > "${help_revlogin_sql}" 2>/dev/null
fi

if [ -s "${help_revlogin_sql}" ]; then
  # Wait for the new replica to be accepting connections.
  # memberJoin is a synchronous lifecycle action capped at 60s per invocation
  # by kbagent, so this wait is bounded: 5 probes x (3s login timeout + 5s
  # sleep) ~= 40s worst case. If the replica is not ready in time we defer
  # (exit 1) instead of blocking the operator; re-entry is safe because the
  # ADD REPLICA above is idempotent (Msg 35282/41106 treated as success).
  replica_ready=false
  retry_count=0
  max_retries=5
  while [ $retry_count -lt $max_retries ]; do
    if MSSQL_LOGIN_TIMEOUT=3 conn_remote_readonly "$new_replica_fqdn" "SELECT 1" >/dev/null 2>&1; then
      replica_ready=true
      break
    fi
    log "Waiting for new replica $new_replica_fqdn to be ready (attempt $((retry_count+1))/$max_retries)..."
    sleep 5
    retry_count=$((retry_count + 1))
  done

  if [ "$replica_ready" != "true" ]; then
    # rc=0 must mean positively converged; an unreachable replica is not.
    log "defer: replica $new_replica_fqdn not accepting connections yet; retry-safe"
    exit 1
  fi

  if $SQLCMD -S "${new_replica_fqdn},${MSSQL_SERVER_PORT}" \
    -U "${MSSQL_SA_USER:-sa}" -P "$MSSQL_SA_PASSWORD" -C \
    -l 10 -t "${MSSQL_QUERY_TIMEOUT:-300}" \
    -i "${help_revlogin_sql}" >/dev/null 2>&1; then
    log "Successfully synced logins to new replica $KB_JOIN_MEMBER_POD_NAME"
  else
    log "WARNING: Failed to sync logins to new replica $KB_JOIN_MEMBER_POD_NAME"
  fi
  rm -f "${help_revlogin_sql}"
else
  log "WARNING: Could not generate login script for new replica"
  rm -f "${help_revlogin_sql}"
fi
