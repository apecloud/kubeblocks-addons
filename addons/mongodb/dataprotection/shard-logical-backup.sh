set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

# Wait for the restore process
RESTOREFILE=$DATA_DIR/mongodb.restore
while [ -f "$RESTOREFILE" ]; do
    echo "INFO: Restore process is running, waiting..."
    sleep 5
done

# config backup agent
generate_endpoints() {
    local fqdns=$1
    local port=$2

    if [ -z "$fqdns" ]; then
        echo "ERROR: No FQDNs provided for config server endpoints." >&2
        exit 1
    fi

    IFS=',' read -ra fqdn_array <<< "$fqdns"
    local endpoints=()

    for fqdn in "${fqdn_array[@]}"; do
        trimmed_fqdn=$(echo "$fqdn" | xargs)
        if [[ -n "$trimmed_fqdn" ]]; then
            endpoints+=("${trimmed_fqdn}:${port}")
        fi
    done

    IFS=','; echo "${endpoints[*]}"
}

cfg_server_endpoints="$(generate_endpoints "$CFG_SERVER_POD_FQDN_LIST" "$CFG_SERVER_INTERNAL_PORT")"

export PBM_MONGODB_URI="mongodb://$MONGODB_USER:$MONGODB_PASSWORD@$cfg_server_endpoints/?authSource=admin&replSetName=$CFG_SERVER_REPLICA_SET_NAME"

pbm_output=$(pbm config --mongodb-uri "$PBM_MONGODB_URI" | grep "storage" ) || {
    if [[ -z "$pbm_output" ]]; then
        echo "INFO: PBM storage not configured."
    else
        echo "INFO: PBM storage already configured, skip."
        exit 0
    fi
}

set_backup_config_env
ech <
cat <<EOF | pbm config --mongodb-uri "$PBM_MONGODB_URI" --file /dev/stdin
storage:
  type: s3
  s3:
    region: ${S3_REGION}
    bucket: ${S3_BUCKET}
    prefix: ${S3_PREFIX}
    endpointUrl: ${S3_ENDPOINT}
    credentials:
      access-key-id: ${S3_ACCESS_KEY}
      secret-access-key: ${S3_SECRET_KEY}
EOF

echo "INFO: PBM storage configuration completed."
pbm backup --type=logical --mongodb-uri "$PBM_MONGODB_URI" 

sleep 10

START_TIME=$(get_current_time)
stat_and_save_backup_info "$START_TIME"