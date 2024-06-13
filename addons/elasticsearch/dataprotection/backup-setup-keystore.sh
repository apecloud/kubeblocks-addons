#!/usr/bin/env bash

set -x
set -exo pipefail

export PATH=$PATH:/usr/share/elasticsearch/bin
cat /etc/datasafed/datasafed.conf
toolConfig=/etc/datasafed/datasafed.conf

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
    cat $toolConfig | grep "$var" | awk '{print $NF}'
}

s3_access_key_id=$(getToolConfigValue access_key_id)
s3_secret_access_key=$(getToolConfigValue secret_access_key)

# Currently, all secure settings are node-specific settings that must have the same value on every node.
# Therefore you must run this command on every node.
# When the keystore is password-protected, you must supply the password each time Elasticsearch starts.
# Modifications to the keystore are not automatically applied to the running Elasticsearch node.
# Any changes to the keystore will take effect when you restart Elasticsearch. Some secure settings can be explicitly reloaded without restart.
echo "${s3_access_key_id}" | elasticsearch-keystore add s3.client.default.access_key -f
echo "${s3_secret_access_key}" | elasticsearch-keystore add s3.client.default.secret_key -f
mv /usr/share/elasticsearch/config/elasticsearch.keystore /usr/share/elasticsearch/data/elasticsearch.keystore

