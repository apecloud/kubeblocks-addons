#!/usr/bin/env bash

set -x
set -o errexit

cat /etc/datasafed/datasafed.conf
toolConfig=/etc/datasafed/datasafed.conf
ES_ENDPOINT=http://${DP_DB_HOST}:9200
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
    cat $toolConfig | grep "$var" | awk '{print $NF}'
}

s3_endpoint=$(getToolConfigValue endpoint)
s3_bucket=$(getToolConfigValue root)
backup_name=$(dirname "${DP_BACKUP_BASE_PATH}")
backup_name=$(basename "${backup_name}")
base_path=$(dirname "${DP_BACKUP_BASE_PATH}")
base_path=$(dirname "${base_path}")
base_path=$(dirname "${base_path}")
base_path=${base_path%/}
base_path=${base_path#*/}

curl -X POST "${ES_ENDPOINT}/_nodes/reload_secure_settings"

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


# Temporarily stop indexing and turn off the following features:
# GeoIP database downloader and ILM history store
curl -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "ingest.geoip.downloader.enabled": false,
    "indices.lifecycle.history_index_enabled": false
  }
}
'

# ILM
curl -X POST "${ES_ENDPOINT}/_ilm/stop?pretty"

# Machine Learning
curl -X POST "${ES_ENDPOINT}/_ml/set_upgrade_mode?enabled=true&pretty"

# Monitoring
curl -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "xpack.monitoring.collection.enabled": false
  }
}
'

# Watcher
curl -X POST "${ES_ENDPOINT}/_watcher/_stop?pretty"

# Universal Profiling
# if Universal Profiling index template management is enabled, we should also disable Universal Profiling index template management.
idx_template_management_is_enabled=False
idx_template_management=$(curl -X GET "${ES_ENDPOINT}/_cluster/settings?filter_path=**.xpack.profiling.templates.enabled&include_defaults=true&pretty")
if [[ "${idx_template_management}" == *"true"* ]]; then
    idx_template_management_is_enabled=True
    curl -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
    {
      "persistent": {
        "xpack.profiling.templates.enabled": false
      }
    }
    '
fi

# Disable destructive_requires_name
curl -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "action.destructive_requires_name": false
  }
}
'

# Delete all existing data streams on the cluster.
curl -X DELETE "${ES_ENDPOINT}/_data_stream/*?expand_wildcards=all&pretty"

# Delete all existing indices on the cluster.
curl -X DELETE "${ES_ENDPOINT}/*?expand_wildcards=all&pretty"

# Restore the entire snapshot.
curl -X POST "${ES_ENDPOINT}/_snapshot/${REPOSITORY}/${backup_name}/_restore?pretty" -H 'Content-Type: application/json' -d'
{
  "indices": "*",
  "include_global_state": true
}
'

curl -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "ingest.geoip.downloader.enabled": true,
    "indices.lifecycle.history_index_enabled": true
  }
}
'

curl -X POST "${ES_ENDPOINT}/_ilm/start?pretty"

curl -X POST "${ES_ENDPOINT}/_ml/set_upgrade_mode?enabled=false&pretty"

curl -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "xpack.monitoring.collection.enabled": true
  }
}
'

curl -X POST "${ES_ENDPOINT}/_watcher/_start?pretty"

if [ "${idx_template_management_is_enabled}" = "True" ]; then
    curl -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
    {
      "persistent": {
        "xpack.profiling.templates.enabled": true
      }
    }
    '
fi

curl -X PUT "${ES_ENDPOINT}/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "action.destructive_requires_name": null
  }
}
'
