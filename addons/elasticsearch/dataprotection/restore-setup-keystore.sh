#!/usr/bin/env bash

set -x
set -exo pipefail

export PATH=$PATH:/usr/share/elasticsearch/bin
cat /etc/datasafed/datasafed.conf
toolConfig=/etc/datasafed/datasafed.conf

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

