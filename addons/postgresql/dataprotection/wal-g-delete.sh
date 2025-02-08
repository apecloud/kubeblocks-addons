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
if [[ -z ${backupName} ]]; then
   echo "INFO: delete unsuccessfully backup files and outdated WAL archive."
   export DATASAFED_BACKEND_BASE_PATH=${backupRepoPath}
   wal-g delete garbage --confirm
   exit 0
fi

# 3. cleanup outdated wal logs, only effective when existing at least one full backup
export DATASAFED_BACKEND_BASE_PATH=${backupRepoPath}
wal-g delete garbage ARCHIVES

# 4. delete wal-g
dpBackupFilesCount=$(datasafed list --name "${backupName}_dp_*" /basebackups_005 | wc -l)
if [[ ${dpBackupFilesCount} -le 1 ]]; then
  # if this base backup only belongs to a backup CR, delete it.
  echo "INFO: delete ${backupName}, backupRepo: ${backupRepo}"
  wal-g delete target ${backupName} --confirm  && wal-g delete garbage ARCHIVES --confirm
fi
datasafed rm "/basebackups_005/${backupName}_dp_${DP_BACKUP_NAME}"


