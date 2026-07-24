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
  # psql exits 0 even when individual statements fail (so set -e/pipefail
  # never fire), and a restore that silently skipped databases or roles was
  # reported Succeeded. Plain ON_ERROR_STOP=1 is not usable either: a
  # pg_dumpall script legitimately conflicts with pre-provisioned objects
  # (e.g. `role "postgres" already exists`). Capture stderr and fail on any
  # SQL error that is not a benign already-exists conflict.
  errlog="$(mktemp)"
  if ! datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.sql.zst" - \
      | psql -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} 2>"${errlog}"; then
    cat "${errlog}" >&2
    echo "ERROR: pgdumpall restore pipeline failed" >&2
    exit 1
  fi
  cat "${errlog}" >&2
  if grep "^ERROR:" "${errlog}" | grep -vE "already exists" | grep -q .; then
    echo "ERROR: pgdumpall restore hit non-conflict SQL errors (see above); data may be partially restored" >&2
    exit 1
  fi
  echo "restore complete!";
  exit 0
fi