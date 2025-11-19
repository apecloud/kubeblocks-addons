#!/bin/bash

setStorageConfig

./milvus-backup restore -n "$DP_BACKUP_NAME"

sleep 180
