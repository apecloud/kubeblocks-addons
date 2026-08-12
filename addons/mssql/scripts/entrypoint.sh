#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set +x
set -eo pipefail

# ShellSpec loads this file with ut_mode=true so tests exercise the production
# functions directly without requiring container mounts or running main.
ut_mode="${ut_mode:-false}"
if [ "$ut_mode" != "true" ] || [ -z "${__SOURCED__:-}" ]; then
  source /scripts/common.sh
fi

# TODO: 当开启hostnetwork，sqlcmd使用localhost会无法连接，暂时使用127.0.0.1代替，后续需要支持ipv6

ROOT_DIR="/var/opt/mssql"
TMP_DIR="/tmp"
SQL_DIR="/scripts"
REMOTE_STANDBY_FLAG="${ROOT_DIR}/.remotestandby"
BACKUP_DIR="${ROOT_DIR}/backup"
AUDIT_SERVER_NAME="kbAuditLog"
AUDIT_LOG_DIRECTORY="${AUDIT_LOG_DIRECTORY:-${ROOT_DIR}/audit}"

# Log rotation settings
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB
MAX_LOG_BACKUPS=5
LOG_FILES=(
  "/log/ag.log"
  "/log/sqlserver.log"
  # Add more log files here if needed
)

# Rotate logs if they exceed the maximum size, keeping at most MAX_LOG_BACKUPS backups
function rotate_log_if_needed() {
  for LOG_FILE in "${LOG_FILES[@]}"; do
    if [ -f "$LOG_FILE" ]; then
      log_size=$(stat -c%s "$LOG_FILE")
      if [ "$log_size" -ge "$MAX_LOG_SIZE" ]; then
        # Remove the oldest backup if it exists
        if [ -f "${LOG_FILE}.${MAX_LOG_BACKUPS}" ]; then
          rm -f "${LOG_FILE}.${MAX_LOG_BACKUPS}"
        fi
        # Shift backups: .4 -> .5, .3 -> .4, etc.
        for ((i=MAX_LOG_BACKUPS-1; i>=1; i--)); do
          if [ -f "${LOG_FILE}.$i" ]; then
            mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i+1))"
          fi
        done
        # Move current log to .1
        mv "$LOG_FILE" "${LOG_FILE}.1"
        : > "$LOG_FILE"
        log "Rotated $LOG_FILE"
      fi
    fi
  done
}

# Log rotation daemon: checks all logs every 60 seconds
function log_rotate_daemon() {
  while true; do
    rotate_log_if_needed
    sleep 60
  done
}

# Login sync daemon settings
LAST_ROLE_FILE="${ROOT_DIR}/.last_known_role"
LOGIN_SYNC_INTERVAL=60            # check interval in seconds
FULL_RECONCILE_EVERY=5            # full reconciliation every N iterations (~5 min)
AGENT_JOB_SYNC_EVERY=30           # agent job sync every N iterations (~30 min)

# Full login reconciliation: push all logins from this primary to every secondary
function reconcile_logins_as_primary() {
  local help_revlogin_sql="${TMP_DIR}/help_revlogin_reconcile.sql"

  conn_local "EXEC sp_help_revlogin" > "${help_revlogin_sql}" 2>/dev/null
  if [ ! -s "${help_revlogin_sql}" ]; then
    log "[reconcile] Failed to generate login script from sp_help_revlogin"
    rm -f "${help_revlogin_sql}"
    return 1
  fi

  # Get all replica endpoints from AG metadata
  local replicas_sql="SET NOCOUNT ON;
    SELECT endpoint_url FROM sys.availability_replicas
    WHERE replica_server_name <> @@SERVERNAME"
  local endpoints
  endpoints=$(conn_local "$replicas_sql" 2>/dev/null | grep -i 'tcp://')

  while IFS= read -r endpoint_url; do
    [ -z "$endpoint_url" ] && continue
    # Extract FQDN from tcp://fqdn:port
    local fqdn
    fqdn=$(echo "$endpoint_url" | sed -e 's|^[[:space:]]*[Tt][Cc][Pp]://||' -e 's|:[0-9]*[[:space:]]*$||')
    [ -z "$fqdn" ] && continue

    log "[reconcile] Pushing logins to replica: $fqdn"
    if ! script_remote "${fqdn},${MSSQL_SERVER_PORT}" "${help_revlogin_sql}" 2>/dev/null; then
      log "[reconcile] WARNING: Failed to push logins to $fqdn"
    fi
  done <<< "$endpoints"

  rm -f "${help_revlogin_sql}"
}

# Fix orphaned database users on all replicas
function reconcile_orphaned_users() {
  log "[orphan_fix] Running orphaned user detection and repair"
  conn_local "EXEC master.dbo.sp_ape_fix_orphaned_users" 2>/dev/null

  # Also run on each secondary
  local replicas_sql="SET NOCOUNT ON;
    SELECT endpoint_url FROM sys.availability_replicas
    WHERE replica_server_name <> @@SERVERNAME"
  local endpoints
  endpoints=$(conn_local "$replicas_sql" 2>/dev/null | grep -i 'tcp://')

  while IFS= read -r endpoint_url; do
    [ -z "$endpoint_url" ] && continue
    local fqdn
    fqdn=$(echo "$endpoint_url" | sed -e 's|^[[:space:]]*[Tt][Cc][Pp]://||' -e 's|:[0-9]*[[:space:]]*$||')
    [ -z "$fqdn" ] && continue
    conn_remote "$fqdn" "EXEC master.dbo.sp_ape_fix_orphaned_users" 2>/dev/null || \
      log "[orphan_fix] WARNING: Failed to fix orphaned users on $fqdn"
  done <<< "$endpoints"
}

# Sync SQL Agent Jobs from primary to all secondaries
function sync_agent_jobs_to_replicas() {
  local job_export_sql="${TMP_DIR}/agent_jobs_export.sql"

  conn_local "EXEC master.dbo.sp_ape_export_agent_jobs" > "${job_export_sql}" 2>/dev/null
  if [ ! -s "${job_export_sql}" ]; then
    rm -f "${job_export_sql}"
    return 0
  fi

  local replicas_sql="SET NOCOUNT ON;
    SELECT endpoint_url FROM sys.availability_replicas
    WHERE replica_server_name <> @@SERVERNAME"
  local endpoints
  endpoints=$(conn_local "$replicas_sql" 2>/dev/null | grep -i 'tcp://')

  while IFS= read -r endpoint_url; do
    [ -z "$endpoint_url" ] && continue
    local fqdn
    fqdn=$(echo "$endpoint_url" | sed -e 's|^[[:space:]]*[Tt][Cc][Pp]://||' -e 's|:[0-9]*[[:space:]]*$||')
    [ -z "$fqdn" ] && continue

    log "[agent_job_sync] Pushing agent jobs to: $fqdn"
    script_remote "${fqdn},${MSSQL_SERVER_PORT}" "${job_export_sql}" 2>/dev/null || \
      log "[agent_job_sync] WARNING: Failed to push agent jobs to $fqdn"
  done <<< "$endpoints"

  rm -f "${job_export_sql}"
}

# Login sync daemon: detects failover and runs periodic reconciliation
function login_sync_daemon() {
  local iteration=0
  local last_role=""

  # Wait for SQL Server and AG to be ready
  sleep 120

  # Load last known role if file exists
  if [ -f "$LAST_ROLE_FILE" ]; then
    last_role=$(cat "$LAST_ROLE_FILE")
  fi

  while true; do
    sleep $LOGIN_SYNC_INTERVAL
    iteration=$((iteration + 1))

    # Get current role
    get_my_role  # sets $my_role

    if [ -z "$my_role" ]; then
      # AG not yet available or role indeterminate, skip this cycle
      continue
    fi

    # Detect role transition: secondary -> primary (failover)
    if [ "$my_role" = "primary" ] && [ "$last_role" = "secondary" ]; then
      log "[login_sync_daemon] Failover detected: was secondary, now primary. Running immediate full reconciliation."
      reconcile_logins_as_primary
      reconcile_orphaned_users
    fi

    # Periodic full reconciliation when primary
    if [ "$my_role" = "primary" ] && [ $((iteration % FULL_RECONCILE_EVERY)) -eq 0 ]; then
      log "[login_sync_daemon] Periodic full reconciliation (iteration $iteration)"
      reconcile_logins_as_primary
      reconcile_orphaned_users
    fi

    # Periodic agent job sync (less frequent)
    if [ "$my_role" = "primary" ] && [ $((iteration % AGENT_JOB_SYNC_EVERY)) -eq 0 ]; then
      log "[login_sync_daemon] Periodic agent job sync (iteration $iteration)"
      sync_agent_jobs_to_replicas
    fi

    # Persist current role
    echo "$my_role" > "$LAST_ROLE_FILE"
    last_role="$my_role"
  done
}

# create sync login procedure in sql server instance
function create_ape_sp() {
  $SQLCMD -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P $MSSQL_SA_PASSWORD -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -i $SQL_DIR/create_sp_help_revlogin.sql
  if [ $? -ne 0 ]; then
    log "Failed to create sp_ape_help_revlogin procedure"
  fi

  /scripts/create_sp_ape_sync_login.sh
  if [ $? -ne 0 ]; then
    log "Failed to init sp_ape_sync_login.sql file"
  fi

  $SQLCMD -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P $MSSQL_SA_PASSWORD -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -i $TMP_DIR/create_sp_ape_sync_login.sql
  if [ $? -ne 0 ]; then
    log "Failed to create sp_ape_sync_login procedure"
  fi

  $SQLCMD -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P $MSSQL_SA_PASSWORD -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -i $SQL_DIR/create_sp_ape_sync_db_to_ag.sql
  if [ $? -ne 0 ]; then
    log "Failed to create sp_ape_sync_db_to_ag procedure"
  fi

}

function script_remote {
  $SQLCMD -S "$1" -U "${MSSQL_SA_USER:-sa}" -P "$MSSQL_SA_PASSWORD" -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -i $2
  if [ $? -ne 0 ]; then
    echo "conn_remote $1 do script failed"
    return 1
  fi
}

function script_local {
    $SQLCMD -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "${MSSQL_SA_USER:-sa}" -P "$MSSQL_SA_PASSWORD" -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -i $1
  if [ $? -ne 0 ]; then
    echo "conn local do script $2 failed"
    return 1
  fi
}

function create_certificate {
  # 创建 master key
  log "create masterkey"
  local master_key_password_sql
  master_key_password_sql=$(quote_tsql_literal "$MMSQL_MASTER_KEY_PASSWORD")
  create_masterkey_sql=$(cat <<EOF
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = $master_key_password_sql;
END
EOF
)
  conn_local "$create_masterkey_sql"
  log "create masterkey finish"

  if conn_local "SET NOCOUNT ON; SELECT 1 FROM sys.certificates WHERE name = 'dbm_certificate'" | grep -q "1"; then
    log "certificate dbm_certificate already exists"
    return 0
  fi

  log "create certificate"
  # Priority: backup certificates > mounted certificates
  local backup_cert_path="${BACKUP_DIR}/INIT_BACKUPS/certificates"
  if [ -d "$backup_cert_path" ] && ls ${backup_cert_path}/dbm_certificate.* >/dev/null 2>&1; then
    log "using certificates from backup"
    cp ${backup_cert_path}/dbm_certificate.* $ROOT_DIR/data/
    if [ -f "${backup_cert_path}/dbm_certificate.password" ]; then
      MSSQL_PRIVATE_ENCRYPTION_PASSWORD=$(cat "${backup_cert_path}/dbm_certificate.password")
      log "using backup certificate password"
    fi
  else
    log "using certificates from mounted volume"
    cp /certificates/dbm_certificate.* $ROOT_DIR/data/
  fi
  chown -R root:mssql $ROOT_DIR/data/dbm_certificate.*
  # Detect SQL Server major version for certificate format compatibility
  # SQL Server 2022 (major=16) supports PFX format; 2019 (major=15) requires PVK/CER
  local mssql_major_version
  mssql_major_version=$($SQLCMD -S "127.0.0.1,${MSSQL_SERVER_PORT}" \
    -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -C \
    -l "$MSSQL_LOGIN_TIMEOUT" -t "$MSSQL_QUERY_TIMEOUT" \
    -h -1 -W -Q "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS INT)" \
    2>/dev/null | tr -d '[:space:]')
  log "SQL Server major version: ${mssql_major_version}"

  # 判断是否是helm生成的pem格式证书
  local pem_certificate
  local pem_private_key
  local pfx_certificate
  pem_private_key="$ROOT_DIR/data/dbm_certificate.key"
  pem_certificate="$ROOT_DIR/data/dbm_certificate.crt"
  pfx_certificate="$ROOT_DIR/data/dbm_certificate.pfx"
  if [ -f "$pem_certificate" ] && [ -f "$pem_private_key" ] && [ ! -f "$pfx_certificate" ]; then
    if [ "${mssql_major_version:-16}" -ge 16 ]; then
      # SQL Server 2022+: convert PEM to PFX format
      log "found pem format certificate, convert to pfx format (SQL Server 2022+)"
      openssl pkcs12 -export -out "${ROOT_DIR}/data/dbm_certificate.pfx" -inkey "${ROOT_DIR}/data/dbm_certificate.key" -in "${ROOT_DIR}/data/dbm_certificate.crt" -passout "pass:${MSSQL_PRIVATE_ENCRYPTION_PASSWORD}"
      if [ $? -ne 0 ]; then
        log "Failed to convert pem format certificate to pfx format"
        exit 1
      fi
      log "convert pem format certificate to pfx format finish"
    else
      # SQL Server 2019 and earlier: convert PEM to PVK/CER format (PFX not supported in T-SQL)
      log "found pem format certificate, convert to pvk/cer format (SQL Server 2019)"
      openssl x509 -in "${ROOT_DIR}/data/dbm_certificate.crt" -outform DER -out "${ROOT_DIR}/data/dbm_certificate.cer"
      if [ $? -ne 0 ]; then
        log "Failed to convert pem certificate to cer format"
        exit 1
      fi
      openssl rsa -in "${ROOT_DIR}/data/dbm_certificate.key" -outform PVK -pvk-strong \
        -out "${ROOT_DIR}/data/dbm_certificate.pvk" -passout "pass:${MSSQL_PRIVATE_ENCRYPTION_PASSWORD}"
      if [ $? -ne 0 ]; then
        log "Failed to convert pem private key to pvk format"
        exit 1
      fi
      chown root:mssql "${ROOT_DIR}/data/dbm_certificate.cer" "${ROOT_DIR}/data/dbm_certificate.pvk"
      log "convert pem format certificate to pvk/cer format finish"
    fi
  fi

  # 判断是否有pfx格式证书
  pfx_certificate="$ROOT_DIR/data/dbm_certificate.pfx"
  if [ -f "$pfx_certificate" ]; then
    if [ "${mssql_major_version:-16}" -ge 16 ]; then
      # SQL Server 2022+: use PFX format directly
      local pfx_certificate_sql private_key_password_sql
      pfx_certificate_sql=$(quote_tsql_literal "$pfx_certificate")
      private_key_password_sql=$(quote_tsql_literal "$MSSQL_PRIVATE_ENCRYPTION_PASSWORD")
      create_certificate_sql=$(cat <<EOF
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = 'dbm_certificate')
BEGIN
    CREATE CERTIFICATE dbm_certificate
        FROM FILE = $pfx_certificate_sql
        WITH
        FORMAT = 'PFX',
        PRIVATE KEY (
        DECRYPTION BY PASSWORD = $private_key_password_sql
	  );
END
EOF
)
      conn_local "$create_certificate_sql"
      if [ $? -ne 0 ]; then
        log "Failed to create certificate in pfx format"
        exit 1
      fi
      log "create certificate finish"
      return 0
    else
      # SQL Server 2019: PFX not supported in T-SQL, convert to PVK/CER and fall through
      log "SQL Server 2019 detected, converting pfx to pvk/cer format"
      openssl pkcs12 -in "$pfx_certificate" -clcerts -nokeys \
        -passin "pass:${MSSQL_PRIVATE_ENCRYPTION_PASSWORD}" \
        -out "${ROOT_DIR}/data/dbm_certificate.pem.crt" 2>/dev/null
      openssl x509 -in "${ROOT_DIR}/data/dbm_certificate.pem.crt" -outform DER \
        -out "${ROOT_DIR}/data/dbm_certificate.cer"
      if [ $? -ne 0 ]; then
        log "Failed to convert pfx certificate to cer format"
        exit 1
      fi
      openssl pkcs12 -in "$pfx_certificate" -nocerts \
        -passin "pass:${MSSQL_PRIVATE_ENCRYPTION_PASSWORD}" \
        -passout "pass:${MSSQL_PRIVATE_ENCRYPTION_PASSWORD}" \
        -out "${ROOT_DIR}/data/dbm_certificate.pem.key" 2>/dev/null
      openssl rsa -in "${ROOT_DIR}/data/dbm_certificate.pem.key" -outform PVK -pvk-strong \
        -passin "pass:${MSSQL_PRIVATE_ENCRYPTION_PASSWORD}" \
        -passout "pass:${MSSQL_PRIVATE_ENCRYPTION_PASSWORD}" \
        -out "${ROOT_DIR}/data/dbm_certificate.pvk"
      if [ $? -ne 0 ]; then
        log "Failed to convert pfx private key to pvk format"
        exit 1
      fi
      chown root:mssql "${ROOT_DIR}/data/dbm_certificate.cer" "${ROOT_DIR}/data/dbm_certificate.pvk"
      rm -f "${ROOT_DIR}/data/dbm_certificate.pem.crt" "${ROOT_DIR}/data/dbm_certificate.pem.key"
      log "convert pfx to pvk/cer format finish, falling through to pvk/cer path"
      # Fall through to PVK/CER CREATE CERTIFICATE path below
    fi
  fi

  local pvk_private_key
  local pvk_certificate
  pvk_private_key="$ROOT_DIR/data/dbm_certificate.pvk"
  pvk_certificate="$ROOT_DIR/data/dbm_certificate.cer"
  if [ -f "$pvk_private_key" ] && [ -f "$pvk_certificate" ]; then
      local pvk_private_key_sql pvk_certificate_sql private_key_password_sql
      pvk_private_key_sql=$(quote_tsql_literal "$pvk_private_key")
      pvk_certificate_sql=$(quote_tsql_literal "$pvk_certificate")
      private_key_password_sql=$(quote_tsql_literal "$MSSQL_PRIVATE_ENCRYPTION_PASSWORD")
      create_certificate_sql=$(cat <<EOF
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = 'dbm_certificate')
BEGIN
    CREATE CERTIFICATE dbm_certificate
        FROM FILE = $pvk_certificate_sql
        WITH PRIVATE KEY (
            FILE = $pvk_private_key_sql,
            DECRYPTION BY PASSWORD = $private_key_password_sql
        );
END
EOF
  )
    conn_local "$create_certificate_sql"
    if [ $? -ne 0 ]; then
      log "Failed to create certificate "
      exit 1
    fi
    log "create certificate finish"
    return 0
  fi

  log "Failed to create certificate"
  exit 1
}

function create_mirroring_endpoint {
  create_mirroring_endpoint_sql=$(cat <<EOF
IF NOT EXISTS (SELECT * FROM sys.endpoints WHERE name = 'Hadr_endpoint')
BEGIN
    CREATE ENDPOINT [Hadr_endpoint]
        AS TCP (LISTENER_PORT = $MSSQL_HADR_ENDPOINT_PORT)
        FOR DATABASE_MIRRORING (
            ROLE = ALL,
            AUTHENTICATION = CERTIFICATE dbm_certificate,
            ENCRYPTION = REQUIRED ALGORITHM AES
        );
END
ALTER ENDPOINT [Hadr_endpoint] STATE = STARTED;
EOF
  )
  conn_local "$create_mirroring_endpoint_sql"
}

function build_create_ag_sql {
  create_ag_sql=$(cat <<EOF
CREATE AVAILABILITY GROUP [$DEFAULT_AG_NAME]
      WITH (DB_FAILOVER = ON, CLUSTER_TYPE = EXTERNAL)
      FOR REPLICA ON
EOF
  )

  IFS=' ' read -r -a pod_fqdns <<< "$(get_pod_fqdns)"
  IFS=' ' read -r -a pods <<< "$(get_pod_list_by_fqdns "${pod_fqdns[@]}")"

  for i in "${!pod_fqdns[@]}"; do
    pod_dns="${pod_fqdns[$i]}"
    replica_name=$(get_replica_name "$pod_dns" "${pods[$i]}")
    if [ -z "$replica_name" ]; then
      log "Failed to get replica name for $pod_dns"
      exit 1
    fi
    conf=$(cat <<EOF
         N'$replica_name'
         WITH (
              ENDPOINT_URL = N'tcp://$pod_dns:$MSSQL_HADR_ENDPOINT_PORT',
              PRIMARY_ROLE ( ALLOW_CONNECTIONS = READ_WRITE ),
              SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY ),
              AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
              FAILOVER_MODE = EXTERNAL,
              SEEDING_MODE = AUTOMATIC
              )
EOF
    )
    create_ag_sql="$create_ag_sql $conf"
    if [[ $i -eq $((${#pods[@]} - 1)) ]]; then
      create_ag_sql="$create_ag_sql;"
    else
      create_ag_sql="$create_ag_sql,"
    fi
  done
  create_ag_sql="$create_ag_sql ALTER AVAILABILITY GROUP [$DEFAULT_AG_NAME] GRANT CREATE ANY DATABASE;"
}

function configure_tls {
  if [ "${KB_TLS_ENABLED}" = "true" ] && [ -n "${KB_TLS_CERT_PATH}" ]; then
    log "found KB_TLS_FILE_PATH: ${KB_TLS_CERT_PATH}"
    mkdir -p "${ROOT_DIR}/secrets"
    if ! cp "${KB_TLS_CERT_PATH}"/* "${ROOT_DIR}/secrets/"; then
      log "Failed to copy TLS certificates"
      return 1
    fi
    for tls_file in ca.crt tls.crt tls.key; do
      if [ ! -f "${ROOT_DIR}/secrets/${tls_file}" ]; then
        log "Missing TLS file: ${ROOT_DIR}/secrets/${tls_file}"
        return 1
      fi
    done
    chmod 600 "${ROOT_DIR}/secrets/tls.crt"
    chmod 600 "${ROOT_DIR}/secrets/tls.key"
    /opt/mssql/bin/mssql-conf set network.tlsprotocols 1.2
    /opt/mssql/bin/mssql-conf set network.tlscert "${ROOT_DIR}/secrets/tls.crt"
    /opt/mssql/bin/mssql-conf set network.tlskey "${ROOT_DIR}/secrets/tls.key"
    log "set tls config finish"

    cp "${ROOT_DIR}/secrets/ca.crt" /usr/local/share/ca-certificates/
    update-ca-certificates
    log "update local client ca-certificates finish"
  fi
}

function wait_for_local_sqlserver_ready {
  local timeout=${1:-0}  # Default timeout is 0 (no timeout)
  local start_time=$(date +%s)
  local elapsed=0

  log "wait for local sqlserver ready (timeout: ${timeout}s)"
  local probe_output
  while true; do
    # Capture probe output so login failures surface the full client error
    # ("Msg 18456, Level 14, State N ... Login failed for user 'sa'") in the
    # log. Without this, readiness failures are observable only as a generic
    # timeout and the 18456 State needed for triage is lost.
    if probe_output=$(conn_remote_readonly "127.0.0.1" "select 1" 2>&1); then
      log "local sqlserver is ready"
      break
    fi
    log "sqlserver readiness probe failed: $(echo "$probe_output" | tr '\n' ' ' | cut -c1-400)"

    # Check timeout if specified
    if [ "$timeout" -gt 0 ]; then
      elapsed=$(($(date +%s) - start_time))
      if [ "$elapsed" -ge "$timeout" ]; then
        log "ERROR: Timeout waiting for local sqlserver to be ready after ${elapsed}s"
        exit 1
      fi
      log "sqlserver is not ready, waiting 5 seconds (${elapsed}/${timeout}s elapsed)"
    else
      log "sqlserver is not ready, waiting 5 seconds"
    fi
    sleep 5
  done
}

function wait_for_all_replicas_ready {
  # wait for local sqlserver ready
  wait_for_local_sqlserver_ready 120
  # then wait for other replicas ready
  log "wait for sqlserver all replicas ready"
  IFS=' ' read -r -a pod_fqdns <<< "$(get_pod_fqdns)"
  for pod_dns in "${pod_fqdns[@]}"; do
    while true; do
      conn_remote_readonly "$pod_dns" "select 1"
      if [ $? -eq 0 ]; then
        log "replica $pod_dns is ready"
        break
      fi
      log "replica $pod_dns is not ready, waiting 5 seconds"
      sleep 5
    done
  done
}

function configure_ag {
  build_create_ag_sql
  log "create ag sql: $create_ag_sql"

  # Check if AG already exists
  check_ag_sql="SELECT name FROM sys.availability_groups WHERE name = '$DEFAULT_AG_NAME'"
  existing_ag=$(conn_local "$check_ag_sql" 2>/dev/null | awk 'NR==3 {print}' | tr -d '\n' | awk '{gsub(/^ *| *$/, ""); print}')

  if [ "$existing_ag" = "$DEFAULT_AG_NAME" ]; then
    log "AG '$DEFAULT_AG_NAME' already exists, skipping creation"
    return 0
  fi

  # Use the generic retry function to create AG with increasing delay
  if conn_local_with_retry "$create_ag_sql" 2 5 "create AG '$DEFAULT_AG_NAME'" false; then
    # Verify AG was created after successful execution
    sleep 2
    verify_ag=$(conn_local "$check_ag_sql" 2>/dev/null | awk 'NR==3 {print}' | tr -d '\n' | awk '{gsub(/^ *| *$/, ""); print}')
    if [ "$verify_ag" = "$DEFAULT_AG_NAME" ]; then
      log "AG creation verified successfully"
      return 0
    else
      log "AG creation verification failed"
      exit 1
    fi
  else
    log "Failed to create AG after all retry attempts"
    exit 1
  fi
}

function join_ag {
  local join_ag_sql="ALTER AVAILABILITY GROUP [$DEFAULT_AG_NAME] JOIN WITH (CLUSTER_TYPE = EXTERNAL); ALTER AVAILABILITY GROUP [$DEFAULT_AG_NAME] GRANT CREATE ANY DATABASE;"

  # Use the generic retry function to join AG with fixed delay (no increase)
  if conn_local_with_retry "$join_ag_sql" 3 5 "join AG '$DEFAULT_AG_NAME' with CLUSTER_TYPE = EXTERNAL" false; then
    log "Successfully joined AG with CLUSTER_TYPE = EXTERNAL"
    return 0
  else
    log "Failed to join AG after all retry attempts"
    exit 1
  fi
}

function add_member_to_remote_primary {
  local response=$(conn_local "SELECT @@SERVERNAME")
  local_servername=$(echo "$response" | awk 'NR==3 {print}' | tr -d '\n' | awk '{gsub(/^ *| *$/, ""); print}')

  local_endpoint="${KB_POD_NAME}.${KB_CLUSTER_COMP_NAME}-headless"
  suffix=$(get_fqdn_suffix)
  if [ -n "$suffix" ]; then
    local_endpoint="${local_endpoint}.$suffix"
  fi
  if [ "${HOST_NETWORK}" == "true" ]; then
    local_endpoint=$(get_pod_ip_and_wait_scheduled ${local_endpoint})
  fi

  add_member_to_remote_primary_sql=$(cat <<EOF
ALTER AVAILABILITY GROUP [${PRIMARY_AG_NAME:-ag1}]
ADD REPLICA ON N'$local_servername'
WITH (
    ENDPOINT_URL = N'TCP://$local_endpoint:$MSSQL_HADR_ENDPOINT_PORT',
    PRIMARY_ROLE ( ALLOW_CONNECTIONS = READ_WRITE ),
    SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY ),
    AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
    FAILOVER_MODE = EXTERNAL,
    SEEDING_MODE = AUTOMATIC,
    SESSION_TIMEOUT = ${REMOTE_SESSION_TIMEOUT_SECONDS:-30}
);
EOF
)
  log "add member to remote primary sql: $add_member_to_remote_primary_sql"
  conn_remote_primary "$add_member_to_remote_primary_sql"
}

function create_kbadmin_login {
  local kbadmin_user kbadmin_password kbadmin_user_identifier kbadmin_password_literal create_login_sql
  kbadmin_user=$MSSQL_ADMIN_USER
  kbadmin_password=$MSSQL_ADMIN_PASSWORD
  kbadmin_user_identifier=$(quote_tsql_identifier "$kbadmin_user")
  kbadmin_password_literal=$(quote_tsql_literal "$kbadmin_password")
  create_login_sql=$(cat <<EOF
USE [master]
GO
CREATE LOGIN $kbadmin_user_identifier with PASSWORD= $kbadmin_password_literal;

ALTER SERVER ROLE [sysadmin] ADD MEMBER $kbadmin_user_identifier;
EOF
  )

  # Use retry function for creating admin login with fixed delay
  if ! conn_local_with_retry "$create_login_sql" 2 5 "create kbadmin login '$kbadmin_user'" false; then
    log "Failed to create kbadmin login after all retry attempts"
    exit 1
  fi
}

function wait_for_all_services_ready {
  log "wait for all services ready"
  local pod_fqdns=($(get_pod_fqdns))
  while true; do
    pass=1
    for i in "${!pod_fqdns[@]}"; do
      if ! getent hosts "${pod_fqdns[$i]}" >/dev/null 2>&1; then
        pass=0
      fi
    done
    if [ $pass -eq 1 ]; then
      break
    fi
    sleep 5
  done
}

function grant_permissions {
  log "grant permissions"
  local kbadmin_user kbadmin_user_identifier ag_identifier grant_permissions_sql
  kbadmin_user=$MSSQL_ADMIN_USER
  kbadmin_user_identifier=$(quote_tsql_identifier "$kbadmin_user")
  ag_identifier=$(quote_tsql_identifier "$DEFAULT_AG_NAME")
  grant_permissions_sql=$(cat <<EOF
  GRANT ALTER, CONTROL, VIEW DEFINITION ON AVAILABILITY GROUP::$ag_identifier TO $kbadmin_user_identifier;
  GRANT VIEW SERVER STATE TO $kbadmin_user_identifier;
EOF
  )
  log "$grant_permissions_sql"

  # Use retry function for granting permissions with fixed delay
  if ! conn_local_with_retry "$grant_permissions_sql" 2 5 "grant permissions to $kbadmin_user" false; then
    log "Failed to grant permissions after all retry attempts"
    exit 1
  fi
}

function create_default_db {
  log "create default db $DEFAULT_DB_NAME"
  local database_sql database_literal backup_path_literal
  database_sql=$(quote_tsql_identifier "$DEFAULT_DB_NAME")
  database_literal=$(quote_tsql_literal "$DEFAULT_DB_NAME")
  backup_path_literal=$(quote_tsql_literal "$ROOT_DIR/data/$DEFAULT_DB_NAME.bak")
  create_db_sql=$(cat <<EOF
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = $database_literal)
BEGIN
  CREATE DATABASE $database_sql;

  ALTER DATABASE $database_sql
  SET RECOVERY FULL;

  BACKUP DATABASE $database_sql
  TO DISK = $backup_path_literal;
END
EOF
)
  log "$create_db_sql"
  conn_local "$create_db_sql"
}

function quote_tsql_identifier {
  local value=${1:?'T-SQL identifier is required'}
  printf '[%s]' "${value//]/]]}"
}

function quote_tsql_literal {
  local value=${1-}
  printf "N'"
  printf '%s' "$value" | sed "s/'/''/g"
  printf "'"
}

function restore_database {
  local database=${1:?"Database name is required"}
  local backup_file=${2:?"Backup file is required"}
  local database_sql backup_path_sql
  database_sql=$(quote_tsql_identifier "$database")
  backup_path_sql=$(quote_tsql_literal "$ROOT_DIR/backup/INIT_BACKUPS/${backup_file}")
  restore_sql=$(cat <<EOF
RESTORE DATABASE $database_sql
FROM DISK = $backup_path_sql
WITH RECOVERY;
EOF
)
  log "${restore_sql}"
  conn_local "$restore_sql"
}

function restore_database_with_no_recovery {
  local database=${1:?"Database name is required"}
  local backup_file=${2:?"Backup file is required"}
  local database_sql backup_path_sql
  database_sql=$(quote_tsql_identifier "$database")
  backup_path_sql=$(quote_tsql_literal "$ROOT_DIR/backup/INIT_BACKUPS/${backup_file}")
  restore_sql=$(cat <<EOF
RESTORE DATABASE $database_sql
FROM DISK = $backup_path_sql
WITH NORECOVERY;
EOF
)
  log "${restore_sql}"
  conn_local "$restore_sql"
}

function join_secondary_database_to_ag {
  local database=${1:?"Database name is required"}
  local database_sql ag_sql
  database_sql=$(quote_tsql_identifier "$database")
  ag_sql=$(quote_tsql_identifier "$DEFAULT_AG_NAME")
  join_secondary_db_sql=$(cat <<EOF
ALTER DATABASE $database_sql SET HADR AVAILABILITY GROUP = $ag_sql;
EOF
)
  log "$join_secondary_db_sql"
  conn_local "$join_secondary_db_sql"
}

function add_db_to_ag {
  local database=${1:?"Database name is required"}
  local database_sql database_literal ag_sql
  database_sql=$(quote_tsql_identifier "$database")
  database_literal=$(quote_tsql_literal "$database")
  ag_sql=$(quote_tsql_identifier "$DEFAULT_AG_NAME")
  add_db_to_ag_sql=$(cat <<EOF
USE [master]
IF NOT EXISTS (SELECT * FROM sys.availability_databases_cluster WHERE database_name = $database_literal)
BEGIN
  ALTER AVAILABILITY GROUP $ag_sql
  ADD DATABASE $database_sql;
END
EOF
)
  log "$add_db_to_ag_sql"
  conn_local "$add_db_to_ag_sql"
}

# https://learn.microsoft.com/zh-cn/sql/relational-databases/backup-restore/restore-a-sql-server-database-to-a-point-in-time-full-recovery-model?view=sql-server-ver17
function restore_from_archive_backup() {
  local database_name=${1:?"Database name is required"}
  local no_recovery=${2:-flase}
  local chain_file="${BACKUP_DIR}/INIT_ARCHIVE_BACKUPS/${database_name}.chain"
  local restore_time database_sql restore_time_sql
  restore_time=$(cat "${BACKUP_DIR}/.restore_archive")
  database_sql=$(quote_tsql_identifier "$database_name")
  restore_time_sql=$(quote_tsql_literal "$restore_time")
  read_chain_entries "$chain_file"
  for database_file in "${CHAIN_ENTRIES[@]}"; do
      local sql=""
      local backup_path_sql
      backup_path_sql=$(quote_tsql_literal "${BACKUP_DIR}/INIT_ARCHIVE_BACKUPS/${database_file}")
      if [[ "${database_file}" == "${database_name}.basefull.bak" ]]; then
        sql="RESTORE DATABASE ${database_sql} FROM DISK = ${backup_path_sql} WITH NORECOVERY"
      else
        sql="RESTORE LOG ${database_sql} FROM DISK = ${backup_path_sql} WITH NORECOVERY, STOPAT = ${restore_time_sql}"
      fi
      log "${sql}"
      conn_local "${sql}"
  done


  sql="RESTORE DATABASE ${database_sql} WITH RECOVERY"
  log "${sql}"
  conn_local "${sql}"
}

function check_auditlog() {
  log "check audit log directory: ${AUDIT_LOG_DIRECTORY}"
  if [ ! -d "${AUDIT_LOG_DIRECTORY}" ]; then
    mkdir -p "${AUDIT_LOG_DIRECTORY}"
    chown -R mssql:mssql "${AUDIT_LOG_DIRECTORY}"
  fi

  local audit_server_name_literal
  audit_server_name_literal=$(quote_tsql_literal "$AUDIT_SERVER_NAME")
  audit_server_id_sql=$(cat <<EOF
SELECT audit_id
FROM sys.server_audits
WHERE name = $audit_server_name_literal;
EOF
  )
  local server_id=$(conn_local "${audit_server_id_sql}" |awk 'NR==3 {print}' | tr -d '\n' | awk '{gsub(/^ *| *$/, ""); print}')
  if [ -n "$server_id" ]; then
    return 0
  fi
  return 1
}

function config_auditlog_primary() {
  log "config server audit log primary"
  if check_auditlog; then
    log "kb audit server is exist: ${AUDIT_SERVER_NAME}"
    return 0
  fi

  local audit_server_create_sql audit_server_identifier audit_directory_literal
  audit_server_identifier=$(quote_tsql_identifier "$AUDIT_SERVER_NAME")
  audit_directory_literal=$(quote_tsql_literal "$AUDIT_LOG_DIRECTORY")
  audit_server_create_sql=$(cat <<EOF
CREATE SERVER AUDIT $audit_server_identifier
TO FILE ( FILEPATH = $audit_directory_literal, MAXSIZE = 100MB, MAX_ROLLOVER_FILES = 5 );

ALTER SERVER AUDIT $audit_server_identifier
WITH (STATE = ON);
EOF
  )

  log "create audit server sql: ${audit_server_create_sql}"
  conn_local "${audit_server_create_sql}"
  if [ $? -ne 0 ]; then
    log "create audit server failed"
  fi
  # 配置默认数据库审计日志
  if [ -n "$DEFAULT_DB_NAME" ]; then
    config_db_auditlog "$DEFAULT_DB_NAME"
  fi
}

function config_auditlog_secondary() {
  log "config server audit log in secondary"
  if check_auditlog; then
    log "kb audit server is exist: ${AUDIT_SERVER_NAME}"
    return 0
  fi
  # 到主节点查询SERVER AUDIT GUID
  local primary_host=$(get_primary_pod_host)
  local audit_guid=""
  local audit_server_create_sql=""
  if [ -z "$primary_host" ]; then
    log "fail to get primary host when create server audit"
    return 1
  fi
  local audit_server_name_literal
  audit_server_name_literal=$(quote_tsql_literal "$AUDIT_SERVER_NAME")
  local retry_count=0
  local max_retries=12 # 2mins
  while [ $retry_count -lt $max_retries ]; do
    audit_guid=$(conn_remote "$primary_host" "select audit_guid from sys.server_audits where name = $audit_server_name_literal" | head -n 1 | tr -d ' ')
    if [ $? -eq 0 ] && [ -n "$audit_guid" ]; then
      log "successfully got audit_guid from primary host after $retry_count retries: ${audit_guid}"
      break
    fi
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      log "failed to get audit_guid from primary host, retry $retry_count of $max_retries"
      sleep 10
    else
      log "failed to get audit_guid from primary host after $max_retries attempts"
      return 1
    fi
  done
  local audit_server_identifier audit_directory_literal audit_guid_literal
  audit_server_identifier=$(quote_tsql_identifier "$AUDIT_SERVER_NAME")
  audit_directory_literal=$(quote_tsql_literal "$AUDIT_LOG_DIRECTORY")
  audit_guid_literal=$(quote_tsql_literal "$audit_guid")
  audit_server_create_sql=$(cat <<EOF
CREATE SERVER AUDIT $audit_server_identifier
TO FILE ( FILEPATH = $audit_directory_literal, MAXSIZE = 100MB, MAX_ROLLOVER_FILES = 5 )
WITH (AUDIT_GUID = $audit_guid_literal);
ALTER SERVER AUDIT $audit_server_identifier
WITH (STATE = ON);
EOF
  )
  log "create audit server sql: ${audit_server_create_sql}"
  conn_local "${audit_server_create_sql}"
  if [ $? -ne 0 ]; then
    log "create audit server failed"
  fi
}


function config_db_auditlog() {
  local dbname=$1
  log "add db:$dbname audit log to audit server: ${AUDIT_SERVER_NAME}"
  local audit_spec_name audit_spec_literal
  audit_spec_name="${dbname}DatabaseAudit"
  audit_spec_literal=$(quote_tsql_literal "$audit_spec_name")
  local check_db_audit_sql
  check_db_audit_sql=$(cat <<EOF
SELECT database_specification_id
FROM sys.database_audit_specifications
WHERE name = $audit_spec_literal;
EOF
  )
  local check_db_audit_result
  if ! check_db_audit_result=$(conn_local_with_database_retry "${dbname}" "${check_db_audit_sql}" 12 5 "check database audit ${dbname}"); then
    log "check database audit failed: ${dbname}DatabaseAudit"
    return 1
  fi

  local database_id
  database_id=$(echo "${check_db_audit_result}" | awk 'NR==3 {print}' | tr -d '\n' | awk '{gsub(/^ *| *$/, ""); print}')
  if [ -n "$database_id" ]; then
    log "database audit is already exist: ${dbname}DatabaseAudit"
    return 0
  fi

  log "database audit is not exist and creating: ${dbname}DatabaseAudit"
  local db_audit_sql audit_spec_identifier audit_server_identifier database_identifier
  audit_spec_identifier=$(quote_tsql_identifier "$audit_spec_name")
  audit_server_identifier=$(quote_tsql_identifier "$AUDIT_SERVER_NAME")
  database_identifier=$(quote_tsql_identifier "$dbname")
  db_audit_sql=$(cat <<EOF
CREATE DATABASE AUDIT SPECIFICATION $audit_spec_identifier
FOR SERVER AUDIT $audit_server_identifier
ADD (SELECT, INSERT, UPDATE, DELETE ON DATABASE::$database_identifier BY PUBLIC)
WITH (STATE = ON);
EOF
  )
  log "create database audit sql: ${db_audit_sql}"
  if ! conn_local_with_database_retry "${dbname}" "${db_audit_sql}" 12 5 "create database audit ${dbname}"; then
    log "create database audit failed"
    return 1
  fi
  log "add db:$dbname audit log to audit server: ${AUDIT_SERVER_NAME} success"
}

function restore_login_names() {
   log "start to restore the server login names"
   if [ -f ${BACKUP_DIR}/INIT_ARCHIVE_BACKUPS/server_login_names.sql ]; then
      $SQLCMD -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P $MSSQL_SA_PASSWORD -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -i ${BACKUP_DIR}/INIT_ARCHIVE_BACKUPS/server_login_names.sql
   elif [ -f ${BACKUP_DIR}/INIT_BACKUPS/server_login_names.sql ]; then
     $SQLCMD -S "127.0.0.1,${MSSQL_SERVER_PORT}" -U "$MSSQL_SA_USER" -P $MSSQL_SA_PASSWORD -C -l $MSSQL_LOGIN_TIMEOUT -t $MSSQL_QUERY_TIMEOUT -i ${BACKUP_DIR}/INIT_BACKUPS/server_login_names.sql
   fi
   if [ $? -ne 0 ]; then
     log "Failed to restore login names"
   fi
}

function finish_backup() {
  if [[ -f ${BACKUP_DIR}/.restore ]]; then
    rm "$BACKUP_DIR/.restore"
  fi
  if [[ -f ${BACKUP_DIR}/.restore_archive ]]; then
    rm "$BACKUP_DIR/.restore_archive"
    rm -rf ${BACKUP_DIR}/INIT_ARCHIVE_BACKUPS
  fi
  if [[ -f ${BACKUP_DIR}/.rebuild ]]; then
    rm "$BACKUP_DIR/.rebuild"
  fi
  if [[ -d $BACKUP_DIR/INIT_BACKUPS ]]; then
    rm -rf $BACKUP_DIR/INIT_BACKUPS
  fi
}

# Read a backup chain manifest into the global array CHAIN_ENTRIES, one entry
# per non-empty line. Robust to a missing trailing newline on the last line and
# to blank lines. Counting entries by array length (rather than `wc -l`, which
# counts newline characters) keeps the "is this the last backup?" test
# consistent with the iteration, so the final backup is always the one restored
# WITH RECOVERY. With `wc -l`, a chain file whose last line lacked a trailing
# newline reported one fewer entry than the loop iterated, applying RECOVERY to
# the second-to-last backup and leaving the last one — and thus the database —
# stuck in RESTORING.
function read_chain_entries() {
  local chain_file="$1"
  CHAIN_ENTRIES=()
  local line encoded escaped decoded index
  if perl -0777 -ne 'exit(index($_, "\0") < 0)' "$chain_file"; then
    while IFS= read -r -d '' line; do
      CHAIN_ENTRIES+=("$line")
    done < "$chain_file"
  else
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      decoded=$line
      if [[ "$line" == v2$'\t'* ]]; then
        encoded=${line#v2$'\t'}
        if [[ ! "$encoded" =~ ^[0-9A-Fa-f]+$ ]] || (( ${#encoded} % 2 != 0 )); then
          CHAIN_ENTRIES=()
          return 1
        fi
        for ((index=0; index<${#encoded}; index+=2)); do
          if [ "${encoded:index:2}" = 00 ]; then
            CHAIN_ENTRIES=()
            return 1
          fi
        done
        escaped=$(printf '%s' "$encoded" | sed 's/../\\x&/g') || {
          CHAIN_ENTRIES=()
          return 1
        }
        decoded=$(printf '%b_' "$escaped") || {
          CHAIN_ENTRIES=()
          return 1
        }
        decoded=${decoded%_}
        if [ -z "$decoded" ]; then
          CHAIN_ENTRIES=()
          return 1
        fi
      fi
      CHAIN_ENTRIES+=("$decoded")
    done < "$chain_file"
  fi
}

function snapshot_restore_chain_files() {
  local source_dir="$1"
  local manifest_file="$2"

  if [[ ! -d "$source_dir" ]] || [[ ! -r "$source_dir" ]]; then
    log "restore chain directory is missing or unreadable: ${source_dir}"
    return 1
  fi
  if ! find "$source_dir" \
    -maxdepth 1 -type f -name '*.chain' -print0 > "$manifest_file"; then
    log "failed to enumerate restore chain files from ${source_dir}"
    return 1
  fi
}

function restore_databases() {
  local no_recovery=${1:-false}
  local chain_manifest restore_rc

  if [[ -f ${BACKUP_DIR}/.restore_archive ]]; then
    restore_archive_backups "${no_recovery}"
    return
  fi

  chain_manifest=$(mktemp "${TMPDIR:-/tmp}/mssql-restore-chains.XXXXXX") || {
    log "failed to allocate restore chain manifest"
    return 1
  }
  if ! snapshot_restore_chain_files \
    "${BACKUP_DIR}/INIT_BACKUPS" "$chain_manifest"; then
    rm -f "$chain_manifest"
    return 1
  fi

  # restore full backup and increment backup
  while IFS= read -r -d '' chain_file; do
    chain_file_name=$(basename "$chain_file")
    database_name=${chain_file_name%.chain}
    # 不能直接恢复master，因为会恢复原来集群的所有元信息，包括复制关系。
    if [ "$database_name" == "master" ]; then
       continue
    fi
    read_chain_entries "${chain_file}"
    local backup_count=${#CHAIN_ENTRIES[@]}
    local index=1
    log "start to restore database ${database_name} from backup chain file ${chain_file}"
    for database_file in "${CHAIN_ENTRIES[@]}"; do
      if [[ $index -eq $backup_count ]] && [[ "${no_recovery}" == "false" ]] ; then
         restore_database "$database_name" "${database_file}"
      else
         restore_database_with_no_recovery "$database_name" "${database_file}"
      fi
      index=$((index + 1))
    done

    if [[ "${no_recovery}" == "false" ]]; then
        add_db_to_ag "$database_name"
    else
        join_secondary_database_to_ag "$database_name"
    fi
  done < "$chain_manifest"
  restore_rc=$?
  rm -f "$chain_manifest"
  return "$restore_rc"
}

function restore_archive_backups() {
  local no_recovery=${1:-false}
  local chain_manifest restore_rc
  log "start to restore archive backups"

  chain_manifest=$(mktemp "${TMPDIR:-/tmp}/mssql-restore-chains.XXXXXX") || {
    log "failed to allocate restore chain manifest"
    return 1
  }
  if ! snapshot_restore_chain_files \
    "${BACKUP_DIR}/INIT_ARCHIVE_BACKUPS" "$chain_manifest"; then
    rm -f "$chain_manifest"
    return 1
  fi

  # restore archive backup
  while IFS= read -r -d '' chain_file; do
    chain_file_name=$(basename "$chain_file")
    database_name=${chain_file_name%.chain}
    if [ "$database_name" == "master" ]; then
       continue
    fi

    restore_from_archive_backup "$database_name" "${no_recovery}"

    if [[ "${no_recovery}" == "false" ]]; then
        add_db_to_ag "$database_name"
    else
        join_secondary_database_to_ag "$database_name"
    fi
  done < "$chain_manifest"
  restore_rc=$?
  rm -f "$chain_manifest"
  return "$restore_rc"
}


function re_add_replicas_for_rebuild() {
   log "do member leave for pod ${KB_POD_NAME}"
   bash /scripts/member_leave.sh "${KB_POD_NAME}"
   if [ $? -ne 0 ]; then
     log "Failed to do member leave for pod ${KB_POD_NAME}"
     kill -9 $$
     exit 1
   fi
   primary_host=$(get_primary_pod_host)
   if [ -z ${primary_host} ]; then
     log "cannot get primary pod host, please check the cluster status."
     kill -9 $$
     exit 1
   fi
   primary_add_replica_to_ag "${KB_POD_NAME}" "${primary_host}"
}

function configure_primary {
  wait_for_all_replicas_ready
  if [ -f "$REMOTE_STANDBY_FLAG" ]; then
    rm "$REMOTE_STANDBY_FLAG"
  fi
  create_kbadmin_login
  create_certificate
  create_mirroring_endpoint
  # restore database from backup
  if [ -f "$BACKUP_DIR/.restore" ] || [ -f "$BACKUP_DIR/.rebuild" ]; then
    if [ -f "$BACKUP_DIR/.rebuild" ] && [ $KB_COMP_REPLICAS -gt 1 ]; then
      re_add_replicas_for_rebuild
      join_ag
    else
      log "start to restore databases from backup"
      configure_ag
      restore_databases "false"
    fi
    grant_permissions
    restore_login_names
    finish_backup
  else
    # here is the progress should not be action in restore or rebuild pods
    configure_ag
    grant_permissions
    create_default_db
    add_db_to_ag "$DEFAULT_DB_NAME"
  fi
  config_auditlog_primary
  create_ape_sp
}

function configure_secondary {
  wait_for_all_replicas_ready
  create_kbadmin_login
  create_certificate
  create_mirroring_endpoint
  if [ -f "$BACKUP_DIR/.rebuild" ]; then
     if [ $KB_COMP_REPLICAS -eq 1 ]; then
        log "start to rebuild databases from backup"
        configure_ag
        restore_databases "false"
     else
        re_add_replicas_for_rebuild
        join_ag
     fi
  else
     join_ag
  fi
  grant_permissions
  restore_login_names
  finish_backup
  create_ape_sp
  config_auditlog_secondary
  sync_all_logins_from_primary
}

function configure_remote_secondary {
  wait_for_all_replicas_ready
  create_kbadmin_login
  # TODO: Depends on fixed certificate logic, if certificates are dynamically issued, this logic needs to be adjusted
  create_certificate
  create_mirroring_endpoint
  add_member_to_remote_primary
  if [ -f "$BACKUP_DIR/.rebuild" ]; then
     re_add_replicas_for_rebuild
  fi
  join_ag
  grant_permissions
  restore_login_names
  finish_backup
  create_ape_sp
  if [ ! -f "$REMOTE_STANDBY_FLAG" ]; then
    touch "$REMOTE_STANDBY_FLAG"
  fi
  sync_all_logins_from_remote_primary
}

# --- D06 restart DB detection ------------------------------------------------
# After a container restart, a business database on a SECONDARY replica can be
# stuck in RESTORING: the syncer re-joins the replica to the AG at the
# membership level, but automatic seeding cannot rebuild the database because a
# stale local copy already exists (error 223 "Database ... already exists") and
# its log chain is broken (error 1412). Nothing at the AG-membership level drops
# the stale copy, so it never re-seeds and DMV health never converges.
#
# This block DETECTS that state and emits a structured evidence signature; it
# deliberately performs NO repair. Rationale (PR #1710 review): an implicit
# `DROP DATABASE` in the ordinary initialized-restart path turns Pod restart
# into a destructive local rebuild, and strict-shell failure propagation can
# crash-loop the container and interrupt long automatic seeding. Automatic
# rebuild belongs in an explicit Day-2 repair operation with operator intent
# (tracked in issue #1711); the signature below tells the operator exactly when
# to run it.
#
# Contract: detection is advisory and MUST NOT gate startup -- every path,
# including query/role failures, returns 0. Detection is local-only: remote
# replica scans can consume the production sqlcmd login timeout and delay an
# ordinary restart. Each verdict logs a "D06_RESTART_DB_DETECT" prefix WITH its
# raw local decision inputs (role/state/sync), so operators and tests see the
# reasoning, not just the verdict. The explicit repair path must validate its
# own primary source before taking action.
D06_DETECT_TAG="D06_RESTART_DB_DETECT"
D06_DETECT_SQL_TIMEOUT=5
D06_DETECT_MAX_ATTEMPTS=7
D06_DETECT_RETRY_INTERVAL=10

# Scalar query against the LOCAL instance. Echoes the trimmed value (row 3 of
# conn_local output: header, dashes, value) or empty when there is no row.
# rc=1 only when sqlcmd itself failed. Internally set -e safe: the conn_local
# call is in an `if !` context so a query failure classifies here instead of
# aborting the caller under production `set -eo pipefail`.
d06_local_scalar() {
  local out
  if ! out=$(MSSQL_LOGIN_TIMEOUT="$D06_DETECT_SQL_TIMEOUT" \
             MSSQL_QUERY_TIMEOUT="$D06_DETECT_SQL_TIMEOUT" \
             conn_local "SET NOCOUNT ON; $1"); then
    return 1
  fi
  printf '%s' "$out" | awk 'NR==3 {gsub(/^[[:space:]]+|[[:space:]]+$/,""); print; exit}'
  return 0
}

# Read local db state + local HADR sync into D06_LAST_STATE / D06_LAST_SYNC.
# rc=0 both read; rc=1 could not query. set -e safe (each read guarded by `if !`).
d06_read_local_db() {
  local db="$1" state sync
  if ! state=$(d06_local_scalar "SELECT state_desc FROM sys.databases WHERE name = N'${db}';"); then
    return 1
  fi
  if ! sync=$(d06_local_scalar "SELECT TOP 1 drs.synchronization_state_desc FROM sys.dm_hadr_database_replica_states drs JOIN sys.databases d ON d.database_id = drs.database_id WHERE drs.is_local = 1 AND d.name = N'${db}';"); then
    return 1
  fi
  D06_LAST_STATE="$state"
  D06_LAST_SYNC="$sync"
  return 0
}

# Predicates over the last-read D06_LAST_STATE / D06_LAST_SYNC (call
# d06_read_local_db first). rc=0 = true.
d06_local_db_is_healthy() { [ "$D06_LAST_STATE" = "ONLINE" ] && [ "$D06_LAST_SYNC" = "SYNCHRONIZED" ]; }
# The exact stuck state D06 targets: locally RESTORING with a missing or
# non-SYNCHRONIZED HADR row. ONLINE-but-lagging is NOT flagged.
d06_local_db_is_stuck() { [ "$D06_LAST_STATE" = "RESTORING" ] && [ "$D06_LAST_SYNC" != "SYNCHRONIZED" ]; }

# Detect-only entry point called from configure_initialized. ALWAYS returns 0:
# a diagnostic must never gate or crash-loop startup (see contract above).
d06_restart_db_detect() {
  local db="${DEFAULT_DB_NAME}"    # whitelist: the addon-managed business db only
  local attempt=1 consecutive_stuck=0 reason=""
  local sample_window_seconds stuck_window_seconds upper_bound_seconds
  sample_window_seconds=$(( (D06_DETECT_MAX_ATTEMPTS - 1) * D06_DETECT_RETRY_INTERVAL ))
  # Each attempt can issue at most role + state + sync queries.
  upper_bound_seconds=$(( sample_window_seconds + D06_DETECT_MAX_ATTEMPTS * 3 * D06_DETECT_SQL_TIMEOUT ))

  if [ -z "$db" ]; then
    return 0
  fi

  # SQL role and database state converge asynchronously during restart. Observe
  # the local state through a declared 60s window instead of classifying one
  # startup snapshot. configure_initialized already runs in the entrypoint's
  # background configure process, so these bounded retries do not delay
  # sqlservr startup. Every individual query still has the short 5s budget.
  while [ "$attempt" -le "$D06_DETECT_MAX_ATTEMPTS" ]; do
    my_role=""
    D06_LAST_STATE=""
    D06_LAST_SYNC=""

    if ! MSSQL_LOGIN_TIMEOUT="$D06_DETECT_SQL_TIMEOUT" \
         MSSQL_QUERY_TIMEOUT="$D06_DETECT_SQL_TIMEOUT" \
         get_my_role; then
      my_role=""
    fi

    case "$my_role" in
      primary)
        return 0
        ;;
      secondary)
        if ! d06_read_local_db "$db"; then
          consecutive_stuck=0
          reason="local-db-query-failed"
        elif d06_local_db_is_healthy; then
          log "${D06_DETECT_TAG} HEALTHY db=${db} state=${D06_LAST_STATE} sync=${D06_LAST_SYNC} attempt=${attempt}/${D06_DETECT_MAX_ATTEMPTS}"
          return 0
        elif d06_local_db_is_stuck; then
          consecutive_stuck=$((consecutive_stuck + 1))
          reason="stuck-shape-observed"
        else
          consecutive_stuck=0
          reason="not-the-D06-stuck-shape"
        fi
        ;;
      *)
        consecutive_stuck=0
        reason="role-not-converged-or-unreadable"
        ;;
    esac

    if [ "$attempt" -ge "$D06_DETECT_MAX_ATTEMPTS" ]; then
      break
    fi

    log "${D06_DETECT_TAG} RETRY db=${db} role='${my_role:-<empty>}' state=${D06_LAST_STATE:-<none>} sync=${D06_LAST_SYNC:-<none>} reason=${reason} attempt=${attempt}/${D06_DETECT_MAX_ATTEMPTS} next_in_seconds=${D06_DETECT_RETRY_INTERVAL}"
    sleep "$D06_DETECT_RETRY_INTERVAL"
    attempt=$((attempt + 1))
  done

  if [ "$consecutive_stuck" -gt 0 ]; then
    stuck_window_seconds=$(( (consecutive_stuck - 1) * D06_DETECT_RETRY_INTERVAL ))
  else
    stuck_window_seconds=0
  fi

  # A persistent-stuck verdict requires the stuck shape at every sample across
  # the full observation window. A late streak reports its actual shorter
  # duration as INCONCLUSIVE; it must not borrow earlier resolving time and
  # claim a 60s stuck window. Query/role failures and other non-healthy states
  # also reset the streak.
  if [ "$consecutive_stuck" -eq "$D06_DETECT_MAX_ATTEMPTS" ]; then
    log "${D06_DETECT_TAG} STUCK_DETECTED db=${db} role=secondary local_state=${D06_LAST_STATE} local_sync=${D06_LAST_SYNC} confirmations=${consecutive_stuck} stuck_window_seconds=${stuck_window_seconds} attempts=${D06_DETECT_MAX_ATTEMPTS} sample_window_seconds=${sample_window_seconds} upper_bound_seconds=${upper_bound_seconds} primary=not-queried action=run-explicit-Day2-repair-see-issue-1711; startup continues"
  else
    log "${D06_DETECT_TAG} INCONCLUSIVE db=${db} role='${my_role:-<empty>}' state=${D06_LAST_STATE:-<none>} sync=${D06_LAST_SYNC:-<none>} confirmations=${consecutive_stuck} stuck_window_seconds=${stuck_window_seconds} attempts=${D06_DETECT_MAX_ATTEMPTS} sample_window_seconds=${sample_window_seconds} upper_bound_seconds=${upper_bound_seconds} reason=${reason}; startup continues"
  fi
  return 0
}
# --- end D06 restart DB detection ----------------------------------------------

function configure_initialized {
  wait_for_local_sqlserver_ready 180
  create_certificate
  wait_for_all_services_ready
  # Re-create stored procedures to ensure DDL triggers and Service Broker
  # infrastructure are present after container restart
  create_ape_sp
  # Detect (and only detect) a business database left stuck in RESTORING after
  # restart -- see the D06_RESTART_DB_DETECT contract above. Advisory: never
  # destructive, never gates startup. "|| true" is belt-and-suspenders so a
  # future contract regression cannot crash-loop the entrypoint.
  d06_restart_db_detect || true
}

function mark_as_initialized() {
  touch $init_flag
}

# Run a configure_* function for the background init job and report its real exit code.
# - "$fn" runs in a subshell with errexit explicitly re-armed, so any failing step inside
#   it aborts the whole configure immediately. Invoking it as part of an && list (as the
#   old call sites did) disables errexit in its entire call tree and swallows failures.
# - Raw output is tee'd to /log/ag.log (log() writes to stderr, so putting tee after the
#   while-read loop used to leave ag.log empty) and still echoed to stderr via log().
# - The exit code is taken from PIPESTATUS[0], so a failure is not masked by the trailing
#   tee/while pipeline elements succeeding.
function run_configure_step() {
  local fn="$1" rc
  # temporarily disable errexit so we can capture and log the configure status here;
  # errexit stays live inside the subshell running "$fn"
  set +e
  ( set -e; "$fn" ) 2>&1 | tee -a /log/ag.log | while read -r line; do log "$line"; done
  rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" -ne 0 ]; then
    log "ERROR: $fn failed with exit code $rc, not marking as initialized"
    return "$rc"
  fi
}

function get_my_role {
  sql=$(cat <<EOF
SELECT
    ars.role_desc
FROM
    sys.availability_replicas ar
INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE
    replica_server_name = @@SERVERNAME;
EOF
  )
  res=$(conn_local "$sql" | awk 'NR==3 {print}')
  res=$(echo "$res" | tr '[:upper:]' '[:lower:]' | tr -d '\n')
  res=$(echo "$res" | awk '{gsub(/^ *| *$/, ""); print}')
  my_role=$(echo "$res" | tr -d '\n')
}

function get_diff_pods {
  # Create temporary files to store the arrays
  temp_file1=$(mktemp)
  temp_file2=$(mktemp)

  # Write the arrays to the temporary files
  printf "%s\n" "${array1[@]}" | sort > "$temp_file1"
  printf "%s\n" "${array2[@]}" | sort > "$temp_file2"

  # Use comm to find items in array2 that do not exist in array1
  diff_pods=( $(comm -13 "$temp_file1" "$temp_file2") )

  # Clean up temporary files
  rm "$temp_file1" "$temp_file2"
}

# sync all logins from primary in secondary
function sync_all_logins_from_primary  {
  local primary_host
  primary_host=$(get_primary_pod_host)
  if [ -z "$primary_host" ]; then
    log "Cannot determine primary host for login sync"
    return 1
  fi
  local help_revlogin_sql="${TMP_DIR}/help_revlogin.sql"
  # the sp_help_revlogin may not be created in primary, so we need wait and retry
  local retry_count=0
  local max_retries=3
  local login_script_ready=false
  while [ "$retry_count" -lt "$max_retries" ]; do
    : > "${help_revlogin_sql}"
    if conn_remote "$primary_host" "EXEC sp_help_revlogin" > "${help_revlogin_sql}" &&
       [ -s "${help_revlogin_sql}" ]; then
      login_script_ready=true
      break
    fi
    retry_count=$((retry_count + 1))
    if [ "$retry_count" -lt "$max_retries" ]; then
      log "Attempt $retry_count of $max_retries: Failed to exec sp_help_revlogin in primary, wait 30 seconds and retry..."
      sleep 30
    fi
  done

  if [ "$login_script_ready" != true ]; then
    log "Failed to exec sp_help_revlogin in primary, the procedure is not created in primary, please check the primary pod logs."
    return 1
  fi

  local sync_login_sql
  sync_login_sql=$(cat "$help_revlogin_sql")
  log "do sync login: ${sync_login_sql}"
  if ! script_local "${help_revlogin_sql}"; then
    log "Failed to sync logins to pod ${KB_POD_NAME}"
    return 1
  fi
}

# sync_all_logins_from_remote_primary used by DR cluster
function sync_all_logins_from_remote_primary  {
  local help_revlogin_sql="${TMP_DIR}/help_revlogin.sql"
  conn_remote_primary "EXEC sp_help_revlogin" > "${help_revlogin_sql}"
  if [ ! -s "${help_revlogin_sql}" ]; then
    log "Failed to generate login script or script is empty"
    return 1
  fi
  local sync_login_sql=$(cat $help_revlogin_sql)
  log "do sync login: ${sync_login_sql}"
  if ! script_local "${help_revlogin_sql}"; then
    log "Failed to sync logins to pod ${KB_POD_NAME}"
    return 1
  fi
}

########################################################
# Child process lifecycle
########################################################

# BEGIN child process lifecycle helpers
ENTRYPOINT_SCRIPT="${BASH_SOURCE[0]}"
SETSID_BIN="$(command -v setsid || true)"
ENTRYPOINT_TERM_GRACE_SECONDS="${ENTRYPOINT_TERM_GRACE_SECONDS:-10}"
ENTRYPOINT_KILL_CONFIRM_SECONDS="${ENTRYPOINT_KILL_CONFIRM_SECONDS:-5}"
ENTRYPOINT_POLL_INTERVAL_SECONDS="${ENTRYPOINT_POLL_INTERVAL_SECONDS:-0.2}"

configure_pgid="${configure_pgid:-}"
log_rotate_pgid="${log_rotate_pgid:-}"
login_sync_pgid="${login_sync_pgid:-}"
sqlservr_pgid="${sqlservr_pgid:-}"
cleanup_done="${cleanup_done:-false}"

function entrypoint_own_pgid() {
  ps -o pgid= -p "$$" | tr -d '[:space:]'
}

function require_process_group_support() {
  if [ -z "${SETSID_BIN:-}" ] || [ ! -x "$SETSID_BIN" ]; then
    log "ERROR: setsid is required to supervise entrypoint child processes"
    return 1
  fi
}

function is_safe_process_group() {
  local pgid="$1" own_pgid
  own_pgid=$(entrypoint_own_pgid)
  [[ "$pgid" =~ ^[0-9]+$ ]] &&
    [ "$pgid" -gt 1 ] &&
    [ "$pgid" -ne "$$" ] &&
    [ -n "$own_pgid" ] &&
    [ "$pgid" -ne "$own_pgid" ]
}

function process_group_alive() {
  local pgid="$1"
  is_safe_process_group "$pgid" || return 1
  ps -eo pgid=,stat= 2>/dev/null | awk -v pgid="$pgid" \
    '$1 == pgid && $2 !~ /^Z/ { found=1; exit } END { exit !found }'
}

function start_process_group() {
  local output_var="$1" pid metadata observed_pgid observed_sid attempt
  shift
  require_process_group_support || return 1
  set +m

  "$SETSID_BIN" "$@" &
  pid=$!

  attempt=0
  while [ "$attempt" -lt 50 ]; do
    metadata=$(ps -o pgid=,sid= -p "$pid" 2>/dev/null | awk 'NF == 2 { print $1, $2 }')
    if [ -n "$metadata" ]; then
      read -r observed_pgid observed_sid <<< "$metadata"
      if [ "$observed_pgid" = "$pid" ] && [ "$observed_sid" = "$pid" ] &&
         is_safe_process_group "$pid"; then
        printf -v "$output_var" '%s' "$pid"
        return 0
      fi
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || return $?
      return 1
    fi
    sleep 0.02
    attempt=$((attempt + 1))
  done

  log "ERROR: child $pid did not become an independently owned process group"
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 1
}

function tracked_process_groups() {
  local pgid
  for pgid in "${configure_pgid:-}" "${log_rotate_pgid:-}" \
    "${login_sync_pgid:-}" "${sqlservr_pgid:-}"; do
    [ -n "$pgid" ] && printf '%s\n' "$pgid"
  done
}

function signal_tracked_process_groups() {
  local signal="$1" pgid
  while IFS= read -r pgid; do
    if process_group_alive "$pgid"; then
      kill -s "$signal" -- "-$pgid" 2>/dev/null || true
    fi
  done < <(tracked_process_groups)
}

function wait_for_tracked_process_groups() {
  local timeout_seconds="$1" deadline pgid any_alive
  deadline=$((SECONDS + timeout_seconds))
  while true; do
    any_alive=false
    while IFS= read -r pgid; do
      if process_group_alive "$pgid"; then
        any_alive=true
        break
      fi
    done < <(tracked_process_groups)
    [ "$any_alive" = false ] && return 0
    [ "$SECONDS" -ge "$deadline" ] && return 1
    sleep "$ENTRYPOINT_POLL_INTERVAL_SECONDS"
  done
}

function reap_stopped_group_leaders() {
  local pgid
  while IFS= read -r pgid; do
    if ! process_group_alive "$pgid"; then
      wait "$pgid" 2>/dev/null || true
    fi
  done < <(tracked_process_groups)
}

function cleanup_children() {
  local first_signal="${1:-TERM}" pgid
  [ "$cleanup_done" = true ] && return 0
  cleanup_done=true
  trap '' TERM INT QUIT

  signal_tracked_process_groups "$first_signal"
  if ! wait_for_tracked_process_groups "$ENTRYPOINT_TERM_GRACE_SECONDS"; then
    signal_tracked_process_groups KILL
    wait_for_tracked_process_groups "$ENTRYPOINT_KILL_CONFIRM_SECONDS" || true
  fi

  reap_stopped_group_leaders
  while IFS= read -r pgid; do
    if process_group_alive "$pgid"; then
      log "ERROR: process group $pgid remains after bounded cleanup"
    fi
  done < <(tracked_process_groups)
  return 0
}

function entrypoint_exit_trap() {
  local rc=$?
  trap - EXIT TERM INT QUIT
  cleanup_children TERM
  exit "$rc"
}

function entrypoint_signal_trap() {
  local signal="$1" rc="$2"
  trap - EXIT TERM INT QUIT
  cleanup_children "$signal"
  exit "$rc"
}

function wait_for_configure_process() {
  local rc
  if wait "$configure_pgid"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    log "sqlserver init failed, exit code: $rc"
    cleanup_children TERM
    return "$rc"
  fi
  if process_group_alive "$configure_pgid"; then
    log "ERROR: configure process group remains after its leader exited"
    cleanup_children TERM
    return 1
  fi
  configure_pgid=""
  log "sqlserver init finished, exit code: 0"
}

function wait_for_sqlservr_process() {
  local rc
  if wait "$sqlservr_pgid"; then
    rc=0
  else
    rc=$?
  fi
  cleanup_children TERM
  return "$rc"
}
# END child process lifecycle helpers

function run_login_sync_internal() {
  function log() {
    local line
    line="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    printf '%s\n' "$line" >&2
    printf '%s\n' "$line" >> /log/ag.log
  }
  login_sync_daemon
}

function run_internal_mode() {
  local mode="${1:-}" configure_function="${2:-}"
  case "$mode" in
    --internal-configure)
      case "$configure_function" in
        configure_initialized|configure_primary|configure_remote_secondary|configure_secondary) ;;
        *) return 2 ;;
      esac
      init_flag="$ROOT_DIR/.initialized"
      run_configure_step "$configure_function"
      mark_as_initialized
      ;;
    --internal-log-rotate)
      log_rotate_daemon
      ;;
    --internal-login-sync)
      run_login_sync_internal
      ;;
    *)
      return 2
      ;;
  esac
}

########################################################
# Main
########################################################

if [ "$ut_mode" = "true" ] && [ -n "${__SOURCED__:-}" ]; then
  return 0
fi

if [[ "${1:-}" == --internal-* ]]; then
  run_internal_mode "$@"
  exit $?
fi

# Convert string output to array using read
IFS=' ' read -r -a pods <<< "$(get_pod_list true)"

cp /config/mssql.conf /var/opt/mssql/mssql.conf

/opt/mssql/bin/mssql-conf set hadr.hadrenabled 1
configure_tls
init_flag="$ROOT_DIR/.initialized"

if [ "$IS_REMOTE_STANDBY" = "false" ] && [ -f $REMOTE_STANDBY_FLAG ]; then
  # when remote standby instance promote to new primary, remove the init flag, do primary configuration
  rm $init_flag
fi

configure_function=""
if [ -f "$init_flag" ]; then
  log "configure initialized"
  configure_function=configure_initialized
else
  IFS=' ' read -r -a pods <<< "$(get_pod_list true)"
  if [ "${pods[0]}" = "$KB_POD_NAME" ] && [ "$IS_REMOTE_STANDBY" != "true" ]; then
    # choose the first pod to create ag
    log "configure primary"
    configure_function=configure_primary
  elif [ "${pods[0]}" = "$KB_POD_NAME" ] && [ "$IS_REMOTE_STANDBY" = "true" ]; then
    # join the ag as remote secondary
    log "configure remote secondary"
    configure_function=configure_remote_secondary
  else
    # the others join the ag
    log "configure secondary"
    configure_function=configure_secondary
  fi
fi

require_process_group_support
trap 'entrypoint_exit_trap' EXIT
trap 'entrypoint_signal_trap TERM 143' TERM
trap 'entrypoint_signal_trap INT 130' INT
trap 'entrypoint_signal_trap QUIT 131' QUIT

start_process_group configure_pgid /bin/bash "$ENTRYPOINT_SCRIPT" \
  --internal-configure "$configure_function"
start_process_group log_rotate_pgid /bin/bash "$ENTRYPOINT_SCRIPT" --internal-log-rotate
start_process_group login_sync_pgid /bin/bash "$ENTRYPOINT_SCRIPT" --internal-login-sync
start_process_group sqlservr_pgid /bin/bash -c \
  'exec /opt/mssql/bin/sqlservr 1>/log/sqlserver.log 2>&1'

if wait_for_configure_process; then
  :
else
  configure_rc=$?
  exit "$configure_rc"
fi

if wait_for_sqlservr_process; then
  sqlservr_rc=0
else
  sqlservr_rc=$?
fi
trap - EXIT
exit "$sqlservr_rc"
