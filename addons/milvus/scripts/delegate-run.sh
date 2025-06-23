#!/bin/bash

set -e

sed "s|MINIO_ACCESS_KEY|${MINIO_ACCESS_KEY}|g; s|MINIO_SECRET_KEY|${MINIO_SECRET_KEY}|g; s|MINIO_HOST|${MINIO_HOST}|g; s|MINIO_PORT|${MINIO_PORT}|g; s|MINIO_BUCKETNAME|${MINIO_BUCKETNAME}|g" /milvus/configs/user.yaml.raw > /milvus/configs/user.yaml

exec $@