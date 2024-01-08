export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"

if [[ ${DP_BACKUP_BASE_PATH} != *"basebackups_005"* ]]; then
   echo "INFO: can not found the backup repository."
   exit 0
fi

# 1. config backup base path
backupName=$(basename ${DP_BACKUP_BASE_PATH})
backupDir=$(dirname ${DP_BACKUP_BASE_PATH})

# 2. delete unsuccessfully backup and outdated WAL archive if this backup CR of the wal-g is not completed
if [[ $backupName == "basebackups_005" ]]; then
   echo "INFO: delete unsuccessfully backup files and outdated WAL archive."
   export DATASAFED_BACKEND_BASE_PATH=${backupDir}
   wal-g delete garbage --confirm
   exit 0
fi

backupRepo=$(dirname ${backupDir})
export DATASAFED_BACKEND_BASE_PATH=${backupRepo}

# 3. cleanup outdated wal logs, only effective when existing at least one full backup
wal-g delete garbage ARCHIVES

# 4. delete wal-g
dpBackupFilesCount=$(datasafed list --name "${backupName}_dp_*" /basebackups_005 | wc -l)
if [[ ${dpBackupFilesCount} -le 1 ]]; then
  # if this base backup only belongs to a backup CR, delete it.
  echo "INFO: delete ${backupName}, backupRepo: ${backupRepo}"
  wal-g delete target ${backupName} --confirm && wal-g delete garbage ARCHIVES --confirm
fi
datasafed rm "/basebackups_005/${backupName}_dp_${DP_BACKUP_NAME}"


