#!/bin/bash

MYDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

load_logging_library() {
    local logging_library_file
    logging_library_file="${MYDIR}/lib-logging.sh"
    # shellcheck disable=SC1090
    source "${logging_library_file}"
}

do_wal_archive() {
    local local_wal_path
    local_wal_path=$1
    walg_dir="/home/postgres/pgdata/wal-g"
    envdir "${walg_dir}/env" "${walg_dir}/wal-g" wal-push "${local_wal_path}"
}

load_logging_library

postgres_log_dir="/home/postgres/pgdata/logs/"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
setup_logging WALG_WAL_PUSH "${postgres_scripts_log_file}"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 local_wal_path" >&2
    exit 1
fi
local_wal_path=$1

echo "Archiving WAL segment file '${local_wal_path}': BEGIN"
set -e
do_wal_archive "${local_wal_path}"
echo "Archiving WAL segment file '${local_wal_path}': DONE"
