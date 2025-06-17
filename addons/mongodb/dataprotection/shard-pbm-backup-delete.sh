#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export DP_BACKUP_JSON="kubeblocks-backup.json"

echo "INFO: Starting shard backup delete script..."
if [ "$PBM_BACKUP_TYPE" = "continuous" ]; then
    if [ "$RETAIN_PITR_FILES" = "true" ]; then
        echo "INFO: Retain PBM pitr files, skip deleting."
    else
        backup_path=$(dirname "$DP_BACKUP_BASE_PATH")
        export DATASAFED_BACKEND_BASE_PATH="${backup_path#/}/$PBM_BACKUP_DIR_NAME"
        pbm_dir_name="pbmPitr"
        if [ -n "$(datasafed list $pbm_dir_name)" ]; then
            datasafed rm $pbm_dir_name -r
            echo "INFO: PBM pitr files deleted."
        fi
    fi
else
    if [ "$(datasafed list ${DP_BACKUP_JSON})" == "${DP_BACKUP_JSON}" ]; then
        backup_status=$(datasafed pull "/${DP_BACKUP_JSON}" - | jq -r '.status')
    else
        echo "INFO: Backup has been deleted."
        exit 0
    fi
    echo "INFO: Backup status: $backup_status"
    backup_name=$(echo "$backup_status" | jq -r '.extras[0].backup_name')
    echo "INFO: Backup name: $backup_name"

    if [ -z "$backup_name" ] || [ "$backup_name" = "null" ]; then
        echo "INFO: Backup name is empty, the backup is not completed and skip handling."
        exit 0
    fi

    backup_path=$(dirname "$DP_BACKUP_BASE_PATH")
    export DATASAFED_BACKEND_BASE_PATH="${backup_path#/}/$PBM_BACKUP_DIR_NAME"
    echo "INFO: Backup path: $DATASAFED_BACKEND_BASE_PATH"
    if [ -n "$(datasafed list $backup_name)" ]; then
        datasafed rm $backup_name -r
        echo "INFO: Backup directory $backup_name deleted."
    fi

    backup_pbm_json="${backup_name}.pbm.json"
    if [ "$(datasafed list $backup_pbm_json)" == "$backup_pbm_json" ]; then
        datasafed rm $backup_pbm_json
        echo "INFO: PBM config file $backup_pbm_json deleted."
    fi
fi

# delete pbm initial config file
pbm_init=".pbm.init"
if [ "$(datasafed list / | wc -l)" = "1" ] && [ "$(datasafed list $pbm_init)" = "$pbm_init" ]; then
    datasafed rm $pbm_init
    export DATASAFED_BACKEND_BASE_PATH="${backup_path#/}"
    datasafed rmdir backups
    echo "INFO: PBM initial config file $pbm_init deleted."
fi
echo "INFO: Shard backup delete script completed successfully."