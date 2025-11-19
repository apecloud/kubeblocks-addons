#!/bin/bash

setStorageConfig

./milvus-backup restore -n "$BACKUP_NAME"

sleep 180
