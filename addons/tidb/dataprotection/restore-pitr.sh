#!/bin/bash

setStorageVar

restore_ts=$(date -d "$DP_RESTORE_TIME" -u '+%Y-%m-%d %H:%M:%S %z')
# shellcheck disable=SC2086
/br restore point --restored-ts "$restore_ts" --pd "$DP_DB_HOST:2379" --storage "s3://$BUCKET$DP_BACKUP_BASE_PATH?access-key=$ACCESS_KEY_ID&secret-access-key=$SECRET_ACCESS_KEY" --s3.endpoint "$ENDPOINT" $BR_EXTRA_ARGS
