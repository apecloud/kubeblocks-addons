set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

sqlplus ${DP_DB_USER}/${DP_DB_PASSWORD}@${DP_DB_HOST}:1521/$ORACLE_SID as sysdba <<EOF
GRANT DATAPUMP_EXP_FULL_DATABASE TO system;
create or replace directory KB_DUMP as '/opt/oracle/oradata/kb_dump';
EOF

expdp system/${DP_DB_PASSWORD}@${DP_DB_HOST}:1521/${ORACLE_PDB} DIRECTORY=KB_DUMP DUMPFILE=kb_oracle_data.dmp FULL=y NOLOGFILE=y

datasafed datasafed push /opt/oracle/oradata/kb_dump/kb_oracle_data.dmp "/${DP_BACKUP_NAME}.dmp"

sleep 10000