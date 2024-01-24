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

mkdir -p ${DATA_DIR};

if [ $(remote_file_exists "${DP_BACKUP_NAME}.tar.gz") == "true" ]; then
  datasafed pull "${DP_BACKUP_NAME}.tar.gz" - | gunzip > ${DP_BACKUP_NAME}.tar
  gs_tar -F ${DP_BACKUP_NAME}.tar -D "${DATA_DIR}/"
  echo "done!";
  exit 0
fi


# NOTE: restore from an old version backup, will be removed in 0.8
if [ $(remote_file_exists "base.tar.gz") == "true" ]; then
  datasafed pull "base.tar.gz" - | tar -xzvf - -C "${DATA_DIR}/"
elif [ $(remote_file_exists "base.tar") == "true" ]; then
  datasafed pull "base.tar" - | tar -xvf - -C "${DATA_DIR}/"
fi

echo "done!";