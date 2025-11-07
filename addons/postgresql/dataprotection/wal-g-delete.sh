#!/bin/bash
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function getWalGSentinelInfo() {
  local sentinelFile=${1}
  local out=$(datasafed list ${sentinelFile})
  if [ "${out}" == "${sentinelFile}" ]; then
     datasafed pull "${sentinelFile}" ${sentinelFile}
     echo "$(cat ${sentinelFile})"
     return
  fi
}

# 1. get backup repo path of wal-g
backupRepoPath=$(getWalGSentinelInfo "wal-g-backup-repo.path")
if [[ -z ${backupRepoPath} ]]; then
   echo "INFO: nothing to delete."
   exit 0
fi

# 2. get backup name of this backup
backupName=$(getWalGSentinelInfo "wal-g-backup-name")
export DATASAFED_BACKEND_BASE_PATH=${backupRepoPath}
if [[ -z ${backupName} ]]; then
   echo "INFO: delete unsuccessfully backup files."
   wal-g delete garbage BACKUPS --confirm
   exit 0
fi

# 3. delete wal-g
dpBackupFilesCount=$(datasafed list --name "${backupName}_dp_*" /basebackups_005 | wc -l)
if [[ ${dpBackupFilesCount} -le 1 ]]; then
  # if this base backup only belongs to a backup CR, delete it.
  echo "INFO: delete ${backupName}, backupRepo: ${backupRepoPath}"
  wal-g delete target ${backupName} --confirm
fi
datasafed rm "/basebackups_005/${backupName}_dp_${DP_BACKUP_NAME}"

# 4. delete outdated WAL archive when existing other full backups.
base_backup_list=$(datasafed list /basebackups_005 -d)
if [[ ! -z ${base_backup_list} ]]; then
  echo "INFO: delete outdated WAL archive."
  wal-g delete garbage ARCHIVES --confirm
fi


