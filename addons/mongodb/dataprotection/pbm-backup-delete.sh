#!/bin/bash
# shellcheck disable=SC2086
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export DP_BACKUP_JSON="kubeblocks-backup.json"

echo "INFO: Starting PBM backup delete script..."
if [ "$PBM_BACKUP_TYPE" = "continuous" ]; then
    if [ "$RETAIN_PITR_FILES" = "true" ]; then
        echo "INFO: Retain PBM pitr files, skip deleting."
    else
        backup_path=$(dirname "$DP_BACKUP_BASE_PATH")
        export DATASAFED_BACKEND_BASE_PATH="${backup_path#/}/$PBM_BACKUP_DIR_NAME"
        pbm_dir_name="pbmPitr"
        if [ -n "$(datasafed list "$pbm_dir_name")" ]; then
            datasafed rm "$pbm_dir_name" -r
            echo "INFO: PBM pitr files deleted."
        fi
    fi
else
    metadata_listing=$(datasafed list "$DP_BACKUP_JSON")
    if [ "$metadata_listing" = "$DP_BACKUP_JSON" ]; then
        backup_json=$(datasafed pull "/${DP_BACKUP_JSON}" -)
    else
        echo "INFO: Backup has been deleted."
        exit 0
    fi

    if metadata_validation=$(printf '%s\n' "$backup_json" | jq -e -s '
        length == 1
        and (.[0] | type == "object")
        and (.[0].status | type == "string")
        and (
            (.[0].extras[0]?) as $extra
            | $extra == null
              or (
                  ($extra | type == "object")
                  and (
                      ($extra | has("backup_name") | not)
                      or $extra.backup_name == null
                      or ($extra.backup_name | type == "string")
                  )
              )
        )
    ' 2>&1); then
        :
    else
        metadata_status=$?
        echo "ERROR: Invalid backup metadata: $metadata_validation" >&2
        exit "$metadata_status"
    fi

    backup_status=$(printf '%s\n' "$backup_json" | jq -r -s '.[0].status')
    echo "INFO: Backup status: $backup_status"

    if backup_name=$(printf '%s\n' "$backup_json" | jq -e -r -s '
        (.[0].extras[0]?) as $extra
        | (
            if (
                $extra == null
                or ($extra | has("backup_name") | not)
                or $extra.backup_name == null
            )
            then ""
            else $extra.backup_name
            end
        ) as $backup_name
        | if $backup_name == ""
          then $backup_name
          elif (
              ($backup_name | test("\\A[A-Za-z0-9._:+-]+\\z"))
              and ($backup_name | startswith("-") | not)
              and $backup_name != "."
              and $backup_name != ".."
          )
          then $backup_name
          else error("unsafe PBM backup name")
          end
    ' 2>&1); then
        :
    else
        backup_name_status=$?
        echo "ERROR: Invalid PBM backup name: $backup_name" >&2
        exit "$backup_name_status"
    fi
    echo "INFO: Backup name: $backup_name"

    if [ -z "$backup_name" ]; then
        echo "INFO: Backup name is empty, the backup  reis not completed and skip handling."
        exit 0
    fi

    backup_path=$(dirname "$DP_BACKUP_BASE_PATH")
    export DATASAFED_BACKEND_BASE_PATH="${backup_path#/}/$PBM_BACKUP_DIR_NAME"
    echo "INFO: Backup path: $DATASAFED_BACKEND_BASE_PATH"
    if [ -n "$(datasafed list "$backup_name")" ]; then
        datasafed rm "$backup_name" -r
        echo "INFO: Backup directory $backup_name deleted."
    fi

    backup_pbm_json="${backup_name}.pbm.json"
    if [ "$(datasafed list "$backup_pbm_json")" = "$backup_pbm_json" ]; then
        datasafed rm "$backup_pbm_json"
        echo "INFO: PBM config file $backup_pbm_json deleted."
    fi
fi

# delete pbm initial config file
pbm_init=".pbm.init"
if [ "$(datasafed list "/" | wc -l)" = "1" ] && [ "$(datasafed list "$pbm_init")" = "$pbm_init" ]; then
    datasafed rm "$pbm_init"
    export DATASAFED_BACKEND_BASE_PATH="${backup_path#/}"
    datasafed rmdir "backups"
    echo "INFO: PBM initial config file $pbm_init deleted."
fi
echo "INFO: PBM backup delete script completed successfully."
