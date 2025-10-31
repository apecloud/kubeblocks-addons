#!/bin/bash
set -x
meta_dir=/hadoop/dfs/metadata
mkdir -p ${meta_dir}
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
datasafed pull -d zstd-fastest "fsImage.tar.zst" - | tar -xvf - -C ${meta_dir}
touch ${meta_dir}/current/.hdfs-k8s-zkfc-formatted
chown -R hadoop:hadoop ${meta_dir}
