#!/usr/bin/env bash

# This script must be running on the target pod node as the elasticsearch.keystore need to be shared with the backup pod

set -x
set -exo pipefail

export PATH=$PATH:/usr/share/elasticsearch/bin
cat /etc/datasafed/datasafed.conf
toolConfig=/etc/datasafed/datasafed.conf
REPOSITORY=kb-backup
ES_ENDPOINT=http://${DP_DB_HOST}:9200

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
    cat $toolConfig | grep "$var" | awk '{print $NF}'
}

s3_access_key_id=$(getToolConfigValue access_key_id)
s3_secret_access_key=$(getToolConfigValue secret_access_key)
s3_endpoint=$(getToolConfigValue endpoint)
s3_bucket=$(getToolConfigValue root)

# Currently, all secure settings are node-specific settings that must have the same value on every node.
# Therefore you must run this command on every node.
# When the keystore is password-protected, you must supply the password each time Elasticsearch starts.
# Modifications to the keystore are not automatically applied to the running Elasticsearch node.
# Any changes to the keystore will take effect when you restart Elasticsearch. Some secure settings can be explicitly reloaded without restart.
echo "${s3_access_key_id}" | elasticsearch-keystore add s3.client.default.access_key -f
echo "${s3_secret_access_key}" | elasticsearch-keystore add s3.client.default.secret_key -f
mv /usr/share/elasticsearch/config/elasticsearch.keystore /usr/share/elasticsearch/data/elasticsearch.keystore

curl -X POST "${ES_ENDPOINT}/_nodes/reload_secure_settings"
base_path=$(dirname "$DP_BACKUP_BASE_PATH")
base_path=${base_path%/}
base_path=${base_path#*/}

function wait_for_snapshot_completion() {
    while true; do
        state=$(curl -s -X GET "${ES_ENDPOINT}:9200/_snapshot/${REPOSITORY}/${DP_BACKUP_NAME}?sort=name&pretty" | grep -w state | awk '{print $NF}' | tr -d ',')
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

curl -X PUT "${ES_ENDPOINT}/_snapshot/${REPOSITORY}?pretty" -H 'Content-Type: application/json' -d "@/tmp/repository.json"

snapshot_result=$(curl -s -X PUT "${ES_ENDPOINT}/_snapshot/${REPOSITORY}/${DP_BACKUP_NAME}?wait_for_completion=false")
echo "INFO: create snapshot ${DP_BACKUP_NAME}, result: ${snapshot_result}"
sleep 10000000

echo "${snapshot_result}" | grep 'snapshot with the same name already exists' > /dev/null 2>&1
if [ $? == 0 ]; then
    echo "INFO: snapshot with the same name ${DP_BACKUP_NAME} already exists"
    exit 0
fi


echo "${snapshot_result}" | grep '{"accepted":true}' > /dev/null 2>&1
if [ $? == 0 ]; then
    wait_for_snapshot_completion
else
    echo "ERROR: create snapshot failed"
    exit 1
fi
