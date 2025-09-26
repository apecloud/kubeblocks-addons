#!/usr/bin/env bash

set -x
set -o errexit

cat /etc/datasafed/datasafed.conf
toolConfig=/etc/datasafed/datasafed.conf
ES_ENDPOINT=http://${DP_DB_HOST}.${KB_NAMESPACE}.svc.cluster.local:9200
REPOSITORY=kb-restore

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT

function getToolConfigValue() {
    local var=$1
    cat $toolConfig | grep "$var[[:space:]]*=" | awk '{print $NF}'
}

s3_endpoint=$(getToolConfigValue endpoint)
s3_bucket=$(getToolConfigValue root)
s3_access_key_id=$(getToolConfigValue access_key_id)
s3_secret_access_key=$(getToolConfigValue secret_access_key)
backup_name=$(basename "${DP_BACKUP_BASE_PATH}")
base_path=$(dirname "${DP_BACKUP_BASE_PATH}")
base_path=$(dirname "${base_path}")
base_path=${base_path%/}
base_path=${base_path#*/}

# Get cluster nodes information and set keystore for restore
echo "INFO: Getting cluster nodes information for restore"
if [ -n "${ELASTIC_USER_PASSWORD}" ]; then
    BASIC_AUTH="-u elastic:${ELASTIC_USER_PASSWORD}"
    AGENT_AUTH="--user elastic:${ELASTIC_USER_PASSWORD}"
else
    BASIC_AUTH=""
    AGENT_AUTH=""
fi

# Get cluster node list
nodes_response=$(curl -s ${BASIC_AUTH} -X GET "${ES_ENDPOINT}/_nodes")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to get cluster nodes information"
    exit 1
fi

# Parse node IP addresses
node_ips=$(echo "$nodes_response" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4 | sort -u)
if [ -z "$node_ips" ]; then
    echo "ERROR: No nodes found in cluster"
    exit 1
fi

echo "INFO: Found nodes for restore: $node_ips"

# Set keystore for each node
for node_ip in $node_ips; do
    echo "INFO: Setting keystore for node $node_ip (restore)"
    
    keystore_request=$(cat <<EOF
{
  "access_key_id": "${s3_access_key_id}",
  "secret_access_key": "${s3_secret_access_key}"
}
EOF
)
    
    response=$(curl -s -w "\n%{http_code}" ${AGENT_AUTH} \
        -X POST "http://${node_ip}:8080/keystore" \
        -H "Content-Type: application/json" \
        -d "${keystore_request}")
    
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" != "200" ]; then
        echo "ERROR: Failed to set keystore for node $node_ip, status: $http_code"
        echo "ERROR: Response: $response_body"
        exit 1
    fi
    
    echo "INFO: Successfully set keystore for node $node_ip (restore)"
done

echo "INFO: All nodes keystore configured for restore, reloading secure settings"
curl -X POST "${ES_ENDPOINT}/_nodes/reload_secure_settings"

# Check Elasticsearch version for S3 repository configuration
es_version=$(curl -s ${BASIC_AUTH} -X GET "${ES_ENDPOINT}" | grep -o '"version"[^}]*' | grep -o '"number"[^"]*"[0-9]*\.[0-9]*' | grep -o '[0-9]*\.[0-9]*')
es_major_version=$(echo $es_version | cut -d. -f1)

# For Elasticsearch 6.x, since it doesn't support path_style_access, we use a workaround:
# ES 6.x automatically prepends bucket name to endpoint domain, so we split the endpoint
# at the first dot and use the first part as fake bucket, second part as endpoint,
# then put the real bucket in base_path
if [ "$es_major_version" = "6" ]; then
    # Extract hostname from endpoint URL (remove http:// prefix)
    s3_hostname=$(echo "$s3_endpoint" | sed 's|http://||')
    # Split hostname at first dot
    fake_bucket=$(echo "$s3_hostname" | cut -d. -f1)
    real_endpoint=$(echo "$s3_hostname" | cut -d. -f2-)
    # Combine real bucket with existing base_path
    real_base_path="${s3_bucket}/${base_path}"

    cat > /tmp/repository.json<< EOF
{
  "type": "s3",
  "settings": {
    "protocol": "http",
    "endpoint": "${real_endpoint}",
    "bucket": "${fake_bucket}",
    "base_path": "${real_base_path}",
    "client": "default",
    "readonly": true
  }
}
EOF
else
    cat > /tmp/repository.json<< EOF
{
  "type": "s3",
  "settings": {
    "protocol": "http",
    "endpoint": "${s3_endpoint}",
    "bucket": "${s3_bucket}",
    "base_path": "${base_path}",
    "client": "default",
    "path_style_access": true,
    "readonly": true
  }
}
EOF
fi

curl -f -s -X PUT "${ES_ENDPOINT}/_snapshot/${REPOSITORY}?pretty" -H 'Content-Type: application/json' -d "@/tmp/repository.json"

function enable_indexing_and_geoip() {
    switch=$1
    case $switch in
    true|false)
        ;;
    *)
        echo "Invalid argument: $switch"
        exit 1
        ;;
    esac
    curl -f -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
    {
      "persistent": {
        "ingest.geoip.downloader.enabled": '$switch',
        "indices.lifecycle.history_index_enabled": '$switch'
      }
    }
    '
}

function switch_ilm() {
    switch=$1
    case $switch in
    start|stop)
        ;;
    *)
        echo "Invalid argument: $1"
        exit 1
        ;;
    esac
    curl -f -s -X POST "${ES_ENDPOINT}/_ilm/${switch}?pretty"
}

function switch_ml_upgrading() {
    switch=$1
    case $switch in
    true|false)
        ;;
    *)
        echo "Invalid argument: $1"
        exit 1
        ;;
    esac
    roles=$(curl -f -s -X GET "${ES_ENDPOINT}/_nodes/*?filter_path=nodes.*.roles&pretty")
    if [[ $roles != *"\"ml\""* ]]; then
        echo "No ml role found, skip switch ml upgrading"
        return
    fi
    curl -f -s -X POST "${ES_ENDPOINT}/_ml/set_upgrade_mode?enabled=${switch}&pretty"
}

function enable_monitoring_collections() {
    switch=$1
    case $switch in
    true|false)
        ;;
    *)
        echo "Invalid argument: $1"
        exit 1
        ;;
    esac
    curl -f -s -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
    {
      "persistent": {
        "xpack.monitoring.collection.enabled": '$switch'
      }
    }
    '
}

function switch_watcher() {
    switch=$1
    case $switch in
    start|stop)
        ;;
    *)
        echo "Invalid argument: $1"
        exit 1
        ;;
    esac
    curl -f -s -X POST "${ES_ENDPOINT}/_watcher/_${switch}?pretty"
}

function enable_universal_profiling() {
    switch=$1
    case $switch in
    true|false)
        ;;
    *)
        echo "Invalid argument: $1"
        exit 1
        ;;
    esac
    curl -f -s -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
    {
      "persistent": {
        "xpack.profiling.templates.enabled": '$switch'
      }
    }
   '
}

function enable_destructive_requires_name() {
    switch=$1
    case $switch in
    true|false|null)
        ;;
    *)
        echo "Invalid argument: $1"
        exit 1
        ;;
    esac
    curl -f -s -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
    {
      "persistent": {
        "action.destructive_requires_name": '$switch'
      }
    }
    '
}

# Temporarily stop indexing and turn off the following features:
# GeoIP database downloader and ILM history store
enable_indexing_and_geoip false

# ILM
switch_ilm stop

# Machine Learning
switch_ml_upgrading true

# Monitoring
enable_monitoring_collections false

# Watcher
switch_watcher stop

# Universal Profiling
# if Universal Profiling index template management is enabled, we should also disable Universal Profiling index template management.
idx_template_management=$(curl -X GET "${ES_ENDPOINT}/_cluster/settings?filter_path=**.xpack.profiling.templates.enabled&include_defaults=true&pretty")
if [[ "${idx_template_management}" == *"true"* ]]; then
    enable_universal_profiling false
fi

# Disable destructive_requires_name
enable_destructive_requires_name false

# Delete all existing data streams on the cluster.
curl -f -s -X DELETE "${ES_ENDPOINT}/_data_stream/*?expand_wildcards=all&pretty"

# Delete all existing indices on the cluster.
curl -f -s -X DELETE "${ES_ENDPOINT}/*?expand_wildcards=all&pretty"

# Restore the entire snapshot.
curl -f -s -X POST "${ES_ENDPOINT}/_snapshot/${REPOSITORY}/${backup_name}/_restore?pretty" -H 'Content-Type: application/json' -d'
{
  "indices": "*",
  "include_global_state": true
}
'

# Wait for the cluster health to become green after restore
wait_interval=10      # Check every 10 seconds

while true; do
  # Query cluster health status
  health_status=$(curl -s "${ES_ENDPOINT}/_cluster/health" | grep -o '"status":"[^\"]*"' | awk -F: '{print $2}' | tr -d '"')
  echo "Current cluster health status: $health_status"
  if [[ "$health_status" == "green" ]]; then
    echo "Cluster health is green, restore is complete."
    break
  fi
  sleep $wait_interval
done

enable_indexing_and_geoip true

switch_ilm start

switch_ml_upgrading false

enable_monitoring_collections true

switch_watcher start

if [[ "${idx_template_management}" == *"true"* ]]; then
    enable_universal_profiling true
fi

enable_destructive_requires_name null
