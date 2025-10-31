#!/bin/bash
set -x
meta_dir=/hadoop/dfs/journal
mkdir -p ${meta_dir}
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
datasafed pull -d zstd-fastest "journal.tar.zst" - | tar -xvf - -C ${meta_dir}
chown -R hadoop:hadoop ${meta_dir}
