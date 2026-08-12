#! /bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Auto-detect sqlcmd path: mssql-tools18 (2022) vs mssql-tools (2019)
if [ -f /opt/mssql-tools18/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools18/bin/sqlcmd
elif [ -f /opt/mssql-tools/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools/bin/sqlcmd
else
  SQLCMD=sqlcmd
fi

function conn_execute {
    # -b makes sqlcmd exit non-zero when the batch raises a T-SQL error of
    # severity > 10 (e.g. RAISERROR, Msg 35283). Without it a failed batch
    # still exits 0 and ops action scripts report false success.
    $SQLCMD -S "$1" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -C -b -Q "$2"

    if [ $? -ne 0 ]; then
        # stderr, so the message never contaminates $(conn_execute ...)
        # response captures in callers.
        echo "Endpoint: $1 SQL: $2 execute failed" >&2
        return 1
    fi
}

# Get the primary node endpoint
# Output format: primary_endpoint
function get_primary_endpoint {
    local port=${MSSQL_SERVER_PORT:-1433}

    local sql="SELECT ar.endpoint_url AS primary_endpoint
               FROM sys.availability_groups ag
               JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
               JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
               WHERE ars.role_desc = 'PRIMARY';"

    # Split declaration from assignment: `local var=$(cmd)` returns local's
    # rc (always 0) and would mask a conn_execute failure.
    local response
    if ! response=$(conn_execute "${KB_POD_IP},$port" "$sql"); then
        return 1
    fi

    # response:
    # primary_endpoint
    # ----------------------------------------------------------------
    # tcp://m0-mssql-0.m0-mssql-headless:5022
    local endpoint_url
    endpoint_url=$(echo "$response" | awk '/tcp:\/\// || /TCP:\/\// {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}')

    if [ -z "$endpoint_url" ]; then
        return 1
    fi

    # Extract hostname from TCP://hostname:port format
    # For example, from tcp://m0-mssql-0.m0-mssql-headless:5022
    # we need m0-mssql-0.m0-mssql-headless
    local hostname=$(echo "$endpoint_url" | sed -e 's|^TCP://||i' -e 's|:[0-9]*$||')

    # Return hostname with MSSQL_SERVER_PORT instead of the HADR port
    echo "${hostname},${port}"
    return 0
}

function execute_on_primary {
    local sql="$1"
    # Split declaration from assignment so get_primary_endpoint's rc is
    # checked directly; the old `local var=$(cmd)` + echo sequence masked
    # the helper rc twice (local's rc, then echo's rc).
    local primary_endpoint
    if ! primary_endpoint=$(get_primary_endpoint); then
        echo "Error: Failed to get primary endpoint" >&2
        exit 1
    fi
    echo "found primary_endpoint: $primary_endpoint"

    conn_execute "$primary_endpoint" "$sql"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to execute SQL on primary node $primary_endpoint" >&2
        exit 1
    fi
}

function execute_on_local {
    local sql="$1"
    local local_endpoint="${KB_POD_IP},${MSSQL_SERVER_PORT:-1433}"

    conn_execute "$local_endpoint" "$sql"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to execute SQL on local node $local_endpoint" >&2
        exit 1
    fi
}
