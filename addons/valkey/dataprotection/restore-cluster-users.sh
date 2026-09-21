#!/bin/bash
set -e
set -o pipefail

# restore-cluster-users.sh — prepareData command of the
# valkey-for-rebuild-instance ActionSet (byte-compatible port of the redis
# addon's restore-cluster-users.sh).
#
# The rebuilt pod starts with an EMPTY data dir; replication from the primary
# brings the dataset back, so the only thing to restore here is users.acl.
# When REBUILD_CLUSTER_INSTANCE=true a rebuild.flag placeholder is left behind
# (same contract as the redis addon).

if [ -n "${DP_DATASAFED_BIN_PATH}" ]; then
  export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
fi
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
mkdir -p ${DATA_DIR}
res=`find ${DATA_DIR} -type f`
data_protection_file=${DATA_DIR}/.kb-data-protection
if [ ! -z "${res}" ] && [ ! -f ${data_protection_file} ]; then
  echo "${DATA_DIR} is not empty! Please make sure that the directory is empty before restoring the backup."
  exit 1
fi
# touch placeholder file
touch ${data_protection_file}
cd ${DATA_DIR}
datasafed pull "users.acl" "users.acl"
if [ "${REBUILD_CLUSTER_INSTANCE}" == "true" ]; then
  touch rebuild.flag
fi
rm -rf ${data_protection_file} && sync
