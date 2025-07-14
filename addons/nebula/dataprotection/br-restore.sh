#!/bin/bash
set -eo pipefail

toolConfig=/etc/datasafed/datasafed.conf

function getToolConfigValue() {
    local var=$1
    cat $toolConfig | grep "$var[[:space:]]*=" | awk '{print $NF}'
}

access_key_id=$(getToolConfigValue access_key_id)
secret_access_key=$(getToolConfigValue secret_access_key)
endpoint=$(getToolConfigValue endpoint)
bucket=$(getToolConfigValue root)
region=$(getToolConfigValue region)
region_flag=""
if [ -n "$region" ]; then
   region_flag="--s3.region=$region"
fi

if [ "${IS_METAD}" != "true" ]; then
  echo "No need to restore when the pod is not a metad."
  exit 0
fi

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}
backup_name=$(datasafed list -d / | sort -Vr | head -n 1)
backup_name=$(basename $backup_name)

br restore full --meta ${DP_DB_HOST}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}:9559 --s3.endpoint "${endpoint}" \
  --storage="s3://${bucket}/${DP_BACKUP_BASE_PATH}" --s3.access_key="${access_key_id}" \
  --s3.secret_key="${secret_access_key}" --name ${backup_name} ${region_flag}
