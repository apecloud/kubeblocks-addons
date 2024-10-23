#!/bin/bash

MYDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

load_logging_library() {
    local logging_library_file
    logging_library_file="${MYDIR}/lib-logging.sh"
    # shellcheck disable=SC1090
    source "${logging_library_file}"
}

do_wal_restore() {
    local remote_wal_file
    local local_wal_file

    remote_wal_file=$1
    local_wal_file=$2
    walg_dir="/home/postgres/pgdata/wal-g"
    envdir "${walg_dir}/restore-env" "${walg_dir}/wal-g" wal-fetch "${remote_wal_file}" "${local_wal_file}"
}

load_logging_library

postgres_log_dir="/home/postgres/pgdata/logs/"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
setup_logging WALG_WAL_FETCH "${postgres_scripts_log_file}"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 remote_wal_file local_wal_file" >&2
    exit 1
fi
remote_wal_file=$1
local_wal_file=$2

echo "Retrieving WAL segment file from remote '${remote_wal_file}' into local '${local_wal_file}': BEGIN"
set -e
do_wal_restore "${remote_wal_file}" "${local_wal_file}"
echo "Retrieving WAL segment file from remote '${remote_wal_file}' into local '${local_wal_file}': DONE"
