# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

if [ -z "$memberServerName" ]; then
    echo "Error: memberServerName is not provided" >&2
    exit 1
fi

# Allowlist validation: replica server names are pod-DNS-shaped
# (e.g. cluster-mssql-1.cluster-mssql-headless). Reject anything else to keep
# untrusted input out of the T-SQL text and out of sqlcmd's client-side
# $(VAR) scripting-variable substitution (the Job env contains
# MSSQL_SA_PASSWORD, so a value like '$(MSSQL_SA_PASSWORD)' must never reach
# sqlcmd).
if ! [[ "$memberServerName" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Error: invalid memberServerName '$memberServerName': only characters [A-Za-z0-9._-] are allowed" >&2
    exit 1
fi

AG_NAME="${DEFAULT_AG_NAME:-ag1}"
primary_endpoint="$(get_primary_endpoint)" || {
    echo "Error: Failed to get primary endpoint" >&2
    exit 1
}

# Returns 0 if sqlcmd output contains a T-SQL error marker (e.g. "Msg 35283,
# Level 16, ..."). conn_execute may not pass -b to sqlcmd, in which case the
# exit code alone does not reflect T-SQL errors.
has_tsql_error() {
    echo "$1" | grep -Eq '^Msg [0-9]+, Level [0-9]+'
}

member_count_sql="
USE [master];
SET NOCOUNT ON;
SELECT COUNT(*) FROM sys.availability_replicas ar
JOIN sys.availability_groups ag ON ag.group_id = ar.group_id
WHERE ag.name = N'$AG_NAME' AND ar.replica_server_name = N'$memberServerName';
"
member_count_response="$(conn_execute "$primary_endpoint" "$member_count_sql")"
member_count_rc=$?
member_count="$(echo "$member_count_response" | awk '/^[[:space:]]*[0-9]+[[:space:]]*$/ {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}')"
if [ $member_count_rc -ne 0 ] || has_tsql_error "$member_count_response" || [ -z "$member_count" ]; then
    echo "Error: could not determine membership of $memberServerName in availability group $AG_NAME" >&2
    echo "$member_count_response" >&2
    exit 1
fi
# A user-invoked remove-member OpsRequest names a specific replica. If that
# replica is not part of the AG (wrong name, or already removed by an earlier
# op), the operation cannot do what the user asked, so fail loudly instead of
# reporting success -- this op runs with backoffLimit: 0, so there is no
# controller retry that would need idempotent-success here. (Scale-in re-entry
# idempotency lives in member_leave.sh, which is a different code path.)
if [ "$member_count" -lt 1 ]; then
    echo "Error: member $memberServerName is not part of availability group $AG_NAME" >&2
    exit 1
fi

REMOVE_MEMBER_SQL="
USE [master];
ALTER AVAILABILITY GROUP [$AG_NAME]
REMOVE REPLICA ON N'$memberServerName';
"

echo "Removing member $memberServerName from availability group $AG_NAME..."
remove_response="$(conn_execute "$primary_endpoint" "$REMOVE_MEMBER_SQL")"
remove_rc=$?

if [ $remove_rc -eq 0 ] && ! has_tsql_error "$remove_response"; then
    echo "$remove_response"
    echo "Successfully removed member $memberServerName from availability group $AG_NAME"
    exit 0
else
    echo "Failed to remove member $memberServerName from availability group $AG_NAME" >&2
    echo "$remove_response" >&2
    exit 1
fi
