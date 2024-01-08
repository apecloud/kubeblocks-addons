export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function remote_file_exists() {
    local out=$(datasafed list $1)
    if [ "${out}" == "$1" ]; then
        echo "true"
        return
    fi
    echo "false"
}

# 1. get backup repo path of wal-g
backupRepoPathFile="wal-g-backup-repo.path"
if [[ $(remote_file_exists "${backupRepoPathFile}") == "false" ]]; then
   echo "INFO: nothing to delete."
   exit 0
fi
datasafed pull "${backupRepoPathFile}" ${backupRepoPathFile}
backupRepoPath=$(cat ${backupRepoPathFile})

# 2. get backup name of this backup
backupNameFile="wal-g-backup-name"
if [[ $(remote_file_exists "${backupNameFile}")  == "false" ]]; then
   echo "INFO: delete unsuccessfully backup files and outdated WAL archive."
   export DATASAFED_BACKEND_BASE_PATH=${backupRepoPath}
   wal-g delete garbage --confirm
   exit 0
fi


# 3. config backup base path
datasafed pull "${backupNameFile}" ${backupNameFile}
backupName=$(cat ${backupNameFile})
export DATASAFED_BACKEND_BASE_PATH=${backupRepoPath}

# 4. cleanup outdated wal logs, only effective when existing at least one full backup
wal-g delete garbage ARCHIVES

# 5. delete wal-g
dpBackupFilesCount=$(datasafed list --name "${backupName}_dp_*" /basebackups_005 | wc -l)
if [[ ${dpBackupFilesCount} -le 1 ]]; then
  # if this base backup only belongs to a backup CR, delete it.
  echo "INFO: delete ${backupName}, backupRepo: ${backupRepo}"
  wal-g delete target ${backupName} --confirm  && wal-g delete garbage ARCHIVES --confirm
fi
datasafed rm "/basebackups_005/${backupName}_dp_${DP_BACKUP_NAME}"


