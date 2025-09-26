#!/usr/bin/env bash

# This script must be running on the target pod node as the elasticsearch.keystore need to be shared with the backup pod

set -x
set -o errexit

export PATH=$PATH:/usr/share/elasticsearch/bin
cat /etc/datasafed/datasafed.conf
toolConfig=/etc/datasafed/datasafed.conf
REPOSITORY=kb-backup
ES_ENDPOINT=http://${DP_DB_HOST}.${KB_NAMESPACE}.svc.cluster.local:9200

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  else
    echo "{}" >"${DP_BACKUP_INFO_FILE}"
    exit 0
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

# Get cluster nodes information and set keystore
echo "INFO: Getting cluster nodes information"
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

echo "INFO: Found nodes: $node_ips"

# Set keystore for each node
for node_ip in $node_ips; do
    echo "INFO: Setting keystore for node $node_ip"
    
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
    
    echo "INFO: Successfully set keystore for node $node_ip"
done

echo "INFO: All nodes keystore configured, reloading secure settings"
curl -X POST "${ES_ENDPOINT}/_nodes/reload_secure_settings"

# Wait for secure settings to be reloaded and plugins to be loaded
echo "INFO: Waiting for nodes to be ready after reloading secure settings..."
sleep 10

# Verify that S3 repository plugin is available
echo "INFO: Checking if S3 repository plugin is available..."
if curl -s -f "${ES_ENDPOINT}/_snapshot" | grep -q 's3'; then
    echo "INFO: S3 repository plugin is available"
else
    echo "WARNING: S3 repository plugin may not be available, attempting to create repository anyway"
fi

# DP_BACKUP_BASE_PATH is the path to the backup directory
# if the target policy is All, the path pattern is: /${namespace}/${clusterName}-${clusterUID}/${componentDef}/${backupName}/${podName}
# if the target policy is Any, the path pattern is: /${namespace}/${clusterName}-${clusterUID}/${componentDef}/${backupName}
# example: /kubeblocks-cloud-ns/x-a3c215fd-1e98-4359-be30-7ad17d08b166/es-data/backup-kubeblocks-cloud-ns-x-20240607144802/x-es-data-1
base_path=$(dirname "$DP_BACKUP_BASE_PATH")
base_path=$(dirname "${base_path}")
base_path=${base_path%/}
base_path=${base_path#*/}

function wait_for_snapshot_completion() {
    while true; do
        state=$(curl -s -X GET "${ES_ENDPOINT}/_snapshot/${REPOSITORY}/${DP_BACKUP_NAME}?pretty" | grep -w state | awk '{print $NF}' | tr -d ',"')
        if [ "$state" == "SUCCESS" ]; then
            echo "INFO: backup success"
            break
        elif [ "$state" == "FAILED" ]; then
            echo "INFO: backup failed"
            exit 1
        else
            echo "INFO: backup in progress"
            sleep 10
        fi
    done
}

# Check Elasticsearch version for S3 repository configuration
es_major_version=$(echo $ELASTICSEARCH_VERSION | cut -d. -f1)

# For Elasticsearch 6.x, since it doesn't support path_style_access, we use a workaround:
# ES 6.x automatically prepends bucket name to endpoint domain, so we split the endpoint
# at the first dot and use the first part as fake bucket, second part as endpoint,
# then put the real bucket in base_path
if [ "$es_major_version" = "6" ]; then
    # For ES 6.x, we need to construct the endpoint so that when ES prepends the bucket,
    # it forms the correct URL. Since ES 6.x doesn't support path_style_access,
    # we need to make it use the correct endpoint format.
    #
    # Original: http://idc1-84577f69d7-minio.kb-system.svc.cluster.local:9000
    # We want: http://idc1-84577f69d7-minio.kb-system.svc.cluster.local:9000
    #
    # So we set:
    # - endpoint: kb-system.svc.cluster.local:9000
    # - bucket: idc1-84577f69d7-minio
    # - base_path: kb-backup/...

    # Extract hostname from endpoint URL (remove http:// prefix)
    s3_hostname=$(echo "$s3_endpoint" | sed 's|http://||')
    # Split hostname at first dot to get the part that should be prepended
    fake_bucket=$(echo "$s3_hostname" | cut -d. -f1)
    fake_endpoint=$(echo "$s3_hostname" | cut -d. -f2-)
    # Combine real bucket with existing base_path
    fake_base_path="${s3_bucket}/${base_path}"

    cat > /tmp/repository.json<< EOF
{
  "type": "s3",
  "settings": {
    "endpoint": "${fake_endpoint}",
    "bucket": "${fake_bucket}",
    "base_path": "${fake_base_path}",
    "client": "default"
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
    "path_style_access": true
  }
}
EOF
fi

curl -X PUT "${ES_ENDPOINT}/_snapshot/${REPOSITORY}?pretty" -H 'Content-Type: application/json' -d "@/tmp/repository.json"

snapshot_result=$(curl -s -X PUT "${ES_ENDPOINT}/_snapshot/${REPOSITORY}/${DP_BACKUP_NAME}?wait_for_completion=false")
echo "INFO: create snapshot ${DP_BACKUP_NAME}, result: ${snapshot_result}"

if [[ "${snapshot_result}" == *"snapshot with the same name already exists"* ]]; then
    echo "INFO: snapshot with the same name ${DP_BACKUP_NAME} already exists"
    exit 0
fi

if [[ "${snapshot_result}" == *"snapshot with the same name already in-progress"* ]]; then
    echo "INFO: snapshot with the same name ${DP_BACKUP_NAME} already in-progress"
    exit 0
fi

echo "${snapshot_result}" | grep '{"accepted":true}' > /dev/null 2>&1
if [ $? == 0 ]; then
    wait_for_snapshot_completion
else
    echo "ERROR: create snapshot failed"
    exit 1
fi
