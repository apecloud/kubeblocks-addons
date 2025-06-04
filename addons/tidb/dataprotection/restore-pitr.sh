#!/bin/bash

setStorageVar

restore_ts=$(date -d "$DP_RESTORE_TIME" -u '+%Y-%m-%d %H:%M:%S %z')
# shellcheck disable=SC2086
/br restore point --restored-ts "$restore_ts" --pd "$PD_ADDRESS" --storage "s3://$BUCKET$DP_BACKUP_ROOT_PATH/$DP_BACKUP_NAME?access-key=$ACCESS_KEY_ID&secret-access-key=$SECRET_ACCESS_KEY" --full-backup-storage "s3://$BUCKET$DP_BACKUP_ROOT_PATH/$DP_BASE_BACKUP_NAME?access-key=$ACCESS_KEY_ID&secret-access-key=$SECRET_ACCESS_KEY" --s3.endpoint "$ENDPOINT" $BR_EXTRA_ARGS
