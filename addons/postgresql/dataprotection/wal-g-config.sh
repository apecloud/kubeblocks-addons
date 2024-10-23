# shellcheck disable=SC2148
set -e

postgres_log_dir="${VOLUME_DATA_DIR}/logs"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
setup_logging WALG_CONFIG "${postgres_scripts_log_file}"

if [[ ! -f /etc/datasafed/datasafed.conf ]]; then
    echo "ERROR: backupRepo should use Tool accessMode"
    exit 1
fi

function config_wal_g() {
    walg_dir="${VOLUME_DATA_DIR}/wal-g"
    walg_env="${walg_dir}/env"
    mkdir -p "${walg_env}"
    cp /etc/datasafed/datasafed.conf "${walg_dir}/datasafed.conf"
    cp /usr/bin/wal-g "${walg_dir}/wal-g"
    datasafed_base_path=${1:?missing datasafed_base_path}
    # config wal-g env
    # config WALG_PG_WAL_SIZE with wal_segment_size which fetched by psql
    # echo "" > ${walg_env}/WALG_PG_WAL_SIZE
    echo "${walg_dir}/datasafed.conf" > "${walg_env}/WALG_DATASAFED_CONFIG"
    echo "${datasafed_base_path}" > "${walg_env}/DATASAFED_BACKEND_BASE_PATH"
    echo "true" > "${walg_env}/PG_READY_RENAME"
    echo "zstd" > "${walg_env}/WALG_COMPRESSION_METHOD"
}

echo "Configure WAL-G : BEGIN"
config_wal_g "$(dirname "${DP_BACKUP_BASE_PATH}")/wal-g"
echo "Configure WAL-G : DONE"

echo "{}" >"${DP_BACKUP_INFO_FILE}"
sync
