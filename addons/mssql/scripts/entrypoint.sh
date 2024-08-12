#!/bin/bash
set -x
function conn_local {
  echo "[DEBUG] $1"
  /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P $MSSQL_SA_PASSWORD -C -Q "$1"
}
function build_create_ag_sql {
  create_ag_sql=$(cat <<EOF
CREATE AVAILABILITY GROUP [ag1]
      WITH (DB_FAILOVER = ON, CLUSTER_TYPE = EXTERNAL)
      FOR REPLICA ON
EOF
  )
  KB_POD_LIST="mssql-mssql-0,mssql-mssql-1,mssql-mssql-2"
  KB_CLUSTER_COMP_NAME="mssql-mssql"
  IFS=',' read -ra pods <<< "$KB_POD_LIST"
  for i in "${!pods[@]}"; do
    pod_dns="${pods[$i]}.$KB_CLUSTER_COMP_NAME-headless"
    conf=$(cat <<EOF
         N'${pods[$i]}'
         WITH (
              ENDPOINT_URL = N'tcp://$pod_dns:<5022>',
              AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
              FAILOVER_MODE = EXTERNAL,
              SEEDING_MODE = AUTOMATIC
              )
EOF
    )
    create_ag_sql="$create_ag_sql\n$conf"
    if [[ $i -eq $((${#pods[@]} - 1)) ]]; then
      create_ag_sql="$create_ag_sql;"
    else
      create_ag_sql="$create_ag_sql,"
    fi
  done
  create_ag_sql="$create_ag_sql\nALTER AVAILABILITY GROUP [ag1] GRANT CREATE ANY DATABASE;"
}
/opt/mssql/bin/mssql-conf set hadr.hadrenabled 1
/opt/mssql/bin/sqlservr
build_create_ag_sql
echo $create_ag_sql