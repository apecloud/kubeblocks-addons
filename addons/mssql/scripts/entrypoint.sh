#!/bin/bash
set -x
function conn_local {
  echo "[DEBUG] $1"
  /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P $MSSQL_SA_PASSWORD -C -Q "$1"
}
/opt/mssql/bin/mssql-conf set hadr.hadrenabled 1
/opt/mssql/bin/sqlservr
create_ag_sql=$(cat <<EOF
CREATE AVAILABILITY GROUP [ag1]
      WITH (DB_FAILOVER = ON, CLUSTER_TYPE = EXTERNAL)
      FOR REPLICA ON
         N'<node1>'
         WITH (
            ENDPOINT_URL = N'tcp://<node1>:<5022>',
            AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
            FAILOVER_MODE = EXTERNAL,
            SEEDING_MODE = AUTOMATIC
            ),
         N'<node2>'
         WITH (
            ENDPOINT_URL = N'tcp://<node2>:<5022>',
            AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
            FAILOVER_MODE = EXTERNAL,
            SEEDING_MODE = AUTOMATIC
            ),
         N'<node3>'
         WITH(
            ENDPOINT_URL = N'tcp://<node3>:<5022>',
            AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
            FAILOVER_MODE = EXTERNAL,
            SEEDING_MODE = AUTOMATIC
            );
ALTER AVAILABILITY GROUP [ag1] GRANT CREATE ANY DATABASE;
EOF
)
KB_REPLICA_COUNT=3
for i in {0..$KB_REPLICA_COUNT}; do
  conf=$(cat <<EOF
         N'$node'
         WITH (
              ENDPOINT_URL = N'tcp://$node:<5022>',
              AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
              FAILOVER_MODE = EXTERNAL,
              SEEDING_MODE = AUTOMATIC
              )
  EOF
  )
  create_ag_sql="$create_ag_sql\n$conf"
done