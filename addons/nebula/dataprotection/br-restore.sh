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

if [ "${IS_STORAGED}" != "true" ]; then
  echo "No need to restore when the pod is not a storaged."
  exit 0
fi

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}
backup_name=$(datasafed list -d / | sort -Vr | head -n 1)
backup_name=$(basename $backup_name)

meta_ep=$(echo $NEBULA_METAD_SVC | cut -d',' -f1)
br restore full --meta ${meta_ep} --s3.endpoint "${endpoint}" \
  --storage="s3://${bucket}/${DP_BACKUP_BASE_PATH}" --s3.access_key="${access_key_id}" \
  --s3.secret_key="${secret_access_key}" --name ${backup_name} ${region_flag}
  
function deleteSignal() {
  while true; do
    echo "$(date): Deleting signal file on ${1}..."
    res=$(curl -L http://${1}:8999/deleteSignal)
    echo $res
    if [ "$res" == "signal file deleted successfully" ]; then
        break
    fi
    sleep 3
  done
}  

sleep 10
# delete signal file for graphd,metad, storaged pods
for fqdn in $(echo $NEBULA_METAD_SVC | tr ',' '\n'); do
  meta_ep=$(echo $fqdn | cut -d':' -f1)
  deleteSignal "$meta_ep"
done

sleep 5
for fqdn in $(echo $GRAPHD_POD_FQDNS | tr ',' '\n'); do
  deleteSignal "$fqdn"
done

for fqdn in $(echo $STORAGED_POD_FQDNS | tr ',' '\n'); do
  deleteSignal "$fqdn"
done

