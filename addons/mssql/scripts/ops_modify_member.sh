# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

if [[ -z "$memberServerName" ]]; then
  echo "Error: memberServerName is required"
  exit 1
fi

# Allowlist: replica server names are pod-DNS-shaped. Reject anything else so
# untrusted input cannot break out of the N'...' T-SQL literal below, or trigger
# sqlcmd's client-side $(VAR) substitution -- the Job env holds MSSQL_SA_PASSWORD,
# so a value like '$(MSSQL_SA_PASSWORD)' must never reach sqlcmd.
if ! [[ "$memberServerName" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Error: invalid memberServerName '$memberServerName': only [A-Za-z0-9._-] are allowed" >&2
  exit 1
fi

if [[ -z "$memberEndpoint" ]]; then
  echo "Error: memberEndpoint is required"
  exit 1
fi

# Parse and validate the endpoint as a WHOLE string: it must be exactly
# {host}:{port} with a DNS/IP-shaped host and a numeric port. Matching the whole
# string (instead of cut -f1/-f2) rejects extra ':'-separated segments such as
# "host:5022:extra" rather than silently truncating them, and keeps untrusted
# input out of the ENDPOINT_URL literal and sqlcmd's $(VAR) substitution -- the
# Job env holds MSSQL_SA_PASSWORD.
if [[ "$memberEndpoint" =~ ^([A-Za-z0-9._-]+):([0-9]+)$ ]]; then
  host="${BASH_REMATCH[1]}"
  port="${BASH_REMATCH[2]}"
else
  echo "Error: invalid memberEndpoint '$memberEndpoint': must be {host}:{port} with host [A-Za-z0-9._-] and a numeric port" >&2
  exit 1
fi

# Construct the SQL command to modify AG member
modify_member_sql=$(cat <<EOF
USE [master];
ALTER AVAILABILITY GROUP [${DEFAULT_AG_NAME:-ag1}]
MODIFY REPLICA ON N'$memberServerName' WITH (ENDPOINT_URL = N'TCP://$host:$port');
EOF
)

# Execute the SQL command
echo "Modifying AG member '$memberServerName' with new endpoint 'TCP://$host:$port'..."
execute_on_local "$modify_member_sql"

# Check if the operation was successful
if [ $? -eq 0 ]; then
  echo "Successfully modified AG member '$memberServerName'"
  exit 0
else
  echo "Failed to modify AG member '$memberServerName'"
  exit 1
fi
