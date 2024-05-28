#!/bin/bash

set -e

sed "s/MINIO_ACCESS_KEY/${MINIO_ACCESS_KEY}/g; s/MINIO_SECRET_KEY/${MINIO_SECRET_KEY}/g" /milvus/configs/user.yaml.raw > /milvus/configs/user.yaml

exec $@