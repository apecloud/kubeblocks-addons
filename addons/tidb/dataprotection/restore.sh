#!/bin/bash

setStorageVar

# shellcheck disable=SC2086
/br restore full --pd "$PD_ADDRESS" --storage "s3://$BUCKET$DP_BACKUP_BASE_PATH?access-key=$ACCESS_KEY_ID&secret-access-key=$SECRET_ACCESS_KEY" --s3.endpoint "$ENDPOINT" $BR_EXTRA_ARGS --with-sys-table
