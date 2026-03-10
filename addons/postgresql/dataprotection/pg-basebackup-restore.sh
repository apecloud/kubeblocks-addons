set -e
set -o pipefail
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

function save_backup_end_lsn() {
    local wal_dir="${DATA_DIR}/pg_wal"
    local backup_end_lsn=""
    for wal in $(ls -t "${wal_dir}" 2>/dev/null | grep -E '^[0-9A-F]{24}$'); do
        local wal_path="${wal_dir}/${wal}"
        # pg_waldump may exit non-zero when it hits the end of a partial WAL file,
        # which is normal for the last WAL segment in a backup.
        # so we check whether any valid records were parsed instead of relying on exit code.
        local last_record=$(pg_waldump "${wal_path}" 2>/dev/null | tail -1 || true)
        if [ -n "${last_record}" ]; then
            backup_end_lsn=$(echo "${last_record}" | awk '{print $10}' | tr -d ',')
            echo "found backup_end_lsn: ${backup_end_lsn} in wal file: ${wal_path}" >> "${DATA_DIR}/.backup_log"
            break
        else
            echo "skipping invalid wal file: ${wal_path}" >> "${DATA_DIR}/.backup_log"
        fi
    done
    if [ -n "${backup_end_lsn}" ]; then
        echo "${backup_end_lsn}" > "${DATA_DIR}/.backup_end_lsn"
    else
        echo "warning: could not extract backup_end_lsn from any wal file" >> "${DATA_DIR}/.backup_log"
    fi
}

mkdir -p ${DATA_DIR};

if [ $(remote_file_exists "${DP_BACKUP_NAME}.tar.zst") == "true" ]; then
  datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.tar.zst" - | tar -xvf - -C "${DATA_DIR}/"
  save_backup_end_lsn
  echo "done!";
  exit 0
fi

# for compatibility
if [ $(remote_file_exists "${DP_BACKUP_NAME}.tar.gz") == "true" ]; then
  datasafed pull "${DP_BACKUP_NAME}.tar.gz" - | gunzip | tar -xvf - -C "${DATA_DIR}/"
  save_backup_end_lsn
  echo "done!";
  exit 0
fi

# NOTE: restore from an old version backup, will be removed in 0.8
if [ $(remote_file_exists "base.tar.gz") == "true" ]; then
  datasafed pull "base.tar.gz" - | tar -xzvf - -C "${DATA_DIR}/"
elif [ $(remote_file_exists "base.tar") == "true" ]; then
  datasafed pull "base.tar" - | tar -xvf - -C "${DATA_DIR}/"
fi
if [ $(remote_file_exists "pg_wal.tar.gz") == "true" ]; then
  datasafed pull "pg_wal.tar.gz" - | tar -xzvf - -C "${DATA_DIR}/pg_wal/"
elif [ $(remote_file_exists "pg_wal.tar") == "true" ]; then
  datasafed pull "pg_wal.tar" - | tar -xvf - -C "${DATA_DIR}/pg_wal/"
fi
save_backup_end_lsn
echo "done!";