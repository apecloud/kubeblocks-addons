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
backup_name=$(basename "${DP_BACKUP_BASE_PATH}")
base_path=$(dirname "${DP_BACKUP_BASE_PATH}")
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

enable_indexing_and_geoip true

switch_ilm start

switch_ml_upgrading false

enable_monitoring_collections true

switch_watcher start

if [[ "${idx_template_management}" == *"true"* ]]; then
    enable_universal_profiling true
fi

enable_destructive_requires_name null
