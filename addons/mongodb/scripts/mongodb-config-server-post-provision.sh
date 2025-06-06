#!/bin/bash

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

PBM_MONGODB_URI="mongodb://$MONGODB_USER:$MONGODB_PASSWORD@$cfg_server_endpoints/?authSource=admin&replSetName=$CFG_SERVER_REPLICA_SET_NAME"
pbm_output=$(pbm config --mongodb-uri "$PBM_MONGODB_URI" | grep "storage" ) || {
    if [[ -z "$pbm_output" ]]; then
        echo "INFO: PBM storage not configured."
    else
        echo "INFO: PBM storage already configured, skip."
        exit 0
    fi
}

# hack to make sure the backup agent can run, backup storage will be changed by backup or restore workloads later.
cat <<EOF | pbm config --mongodb-uri "$PBM_MONGODB_URI" --file /dev/stdin
storage:
  type: filesystem
  filesystem:
    path: /tmp/mongodb/backups
EOF

echo "INFO: PBM configuration completed."