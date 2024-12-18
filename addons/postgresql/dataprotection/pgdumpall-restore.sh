# shellcheck disable=SC2148
# use psql to restore databses from a script files created by pg_dumpall
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}
function remote_file_exists() {
    local out=$(datasafed list $1)
    if [ "${out}" == "$1" ]; then
        echo "true"
        return
    fi
    echo "false"
}

if [ $(remote_file_exists "${DP_BACKUP_NAME}.sql.zst") == "true" ]; then
  datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.sql.zst" - | psql -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT}
  echo "restore complete!";
  exit 0
fi