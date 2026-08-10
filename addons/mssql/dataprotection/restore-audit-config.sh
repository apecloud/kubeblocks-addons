#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set -e

# Auto-detect sqlcmd path: mssql-tools18 (2022) vs mssql-tools (2019)
if [ -f /opt/mssql-tools18/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools18/bin/sqlcmd
elif [ -f /opt/mssql-tools/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools/bin/sqlcmd
else
  SQLCMD=sqlcmd
fi

# Function to execute SQL command on a specific endpoint
function conn_execute {
    $SQLCMD -S "$1" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -C -x -Q "$2"

    if [ $? -ne 0 ]; then
        echo "Endpoint: $1 SQL: $2 execute failed"
        return 1
    fi
}

function quote_tsql_identifier() {
  local value=${1:?'T-SQL identifier is required'}
  printf '[%s]' "${value//]/]]}"
}

function quote_tsql_literal() {
  local value=${1-}
  printf "N'"
  printf '%s' "$value" | sed "s/'/''/g"
  printf "'"
}

function load_database_names() {
  local query encoded_output encoded decoded
  query="SET NOCOUNT ON; SELECT CONVERT(varchar(max), CONVERT(varbinary(max), name), 2) FROM sys.databases WHERE name NOT IN ('tempdb','model','msdb','master') ORDER BY database_id;"
  DP_DATABASE_NAMES=()
  encoded_output=$($SQLCMD -S "$DP_DB_HOST" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -C -h-1 -W -x -Q "$query") || return 1
  while IFS= read -r encoded || [ -n "$encoded" ]; do
    [ -z "$encoded" ] && continue
    if [[ ! "$encoded" =~ ^[0-9A-Fa-f]+$ ]] || (( ${#encoded} % 4 != 0 )); then
      DP_DATABASE_NAMES=()
      return 1
    fi
    decoded=$(perl -MEncode=decode,encode,FB_CROAK -e '
      my $value = decode("UTF-16LE", pack("H*", $ARGV[0]), FB_CROAK);
      print encode("UTF-8", $value, FB_CROAK);
    ' "$encoded" && printf x) || {
      DP_DATABASE_NAMES=()
      return 1
    }
    DP_DATABASE_NAMES+=("${decoded%x}")
  done <<< "$encoded_output"
}

# Check if current node is primary
function is_primary {
    local sql="SELECT ars.role_desc
               FROM sys.availability_replicas ar
               INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
               WHERE replica_server_name = @@SERVERNAME;"

    local role
    role=$(conn_execute "${DP_DB_HOST}" "$sql" | awk 'NR==3 {print}' | tr '[:upper:]' '[:lower:]' | tr -d ' \n')

    if [[ "$role" == "primary" ]]; then
        return 0  # true
    else
        return 1  # false
    fi
}

function re_enable_audit() {
  local database_name="$1"
  local audit_name="${database_name}DatabaseAudit"
  local database_sql audit_identifier audit_literal
  database_sql=$(quote_tsql_identifier "$database_name")
  audit_identifier=$(quote_tsql_identifier "$audit_name")
  audit_literal=$(quote_tsql_literal "$audit_name")

  # Query audit status (we're already on primary)
  local check_audit_sql
  check_audit_sql=$(cat <<EOF
USE ${database_sql};
SET NOCOUNT ON;
SELECT is_state_enabled FROM sys.database_audit_specifications WHERE name = ${audit_literal};
EOF
)

  echo "Checking audit status for database: ${database_name}"
  local enabled
  enabled=$(conn_execute "${DP_DB_HOST}" "${check_audit_sql}" | awk 'NR==3 {print}' | tr -d ' \n')

  if [[ "${enabled}" == "1" ]]; then
      echo "Re-enabling Database audit for ${database_name}."
      local alter_audit_sql
      alter_audit_sql=$(cat <<EOF
USE ${database_sql};
ALTER DATABASE AUDIT SPECIFICATION ${audit_identifier} WITH (STATE = OFF);
ALTER DATABASE AUDIT SPECIFICATION ${audit_identifier} FOR SERVER AUDIT [kbAuditLog];
ALTER DATABASE AUDIT SPECIFICATION ${audit_identifier} WITH (STATE = ON);
EOF
)
     # Execute on current primary node
     conn_execute "${DP_DB_HOST}" "${alter_audit_sql}"
     echo "Successfully re-enabled audit for database: ${database_name}"
  else
     echo "Database audit for ${database_name} is not enabled or does not exist, skipping."
  fi
}

# Check if we are running on primary node, if not, exit gracefully
echo "Checking if current node is primary..."
if ! is_primary; then
    echo "Current node is not primary, skipping audit configuration restore."
    exit 0
fi

echo "Current node is primary, proceeding with audit configuration restore..."

# Get database list from current primary node
echo "Getting database list..."
if ! load_database_names; then
   echo "Failed to enumerate databases for audit configuration restore." >&2
   exit 1
fi
for database in "${DP_DATABASE_NAMES[@]}"; do
   re_enable_audit "${database}"
done