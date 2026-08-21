#!/bin/bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/dolt}"
STAGING_ROOT="${DOLT_BACKUP_STAGING_DIR:-${DATA_DIR}/.kb-doltdb-backup}"
WORK_DIR="${STAGING_ROOT}/work"
MANIFEST="${WORK_DIR}/manifest.tsv"
SERVER_METADATA_DIR="${WORK_DIR}/server-metadata"
DATABASE_METADATA_DIR="${WORK_DIR}/database-metadata"

if [[ "$DATA_DIR" != /* || "$DATA_DIR" == "/" ]]; then
  echo "invalid DATA_DIR: ${DATA_DIR}" >&2
  exit 1
fi

sql_quote() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}

copy_if_exists() {
  local src="$1"
  local dst="$2"

  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
}

run_dolt_sql() {
  local db_name="$1"
  local query="$2"
  local host="${DOLT_SQL_HOST:-${DP_DB_HOST:-127.0.0.1}}"
  local port="${DOLT_SQL_PORT:-${DP_DB_PORT:-3306}}"
  local user="${DOLT_SQL_USER:-${DP_DB_USER:-root}}"
  local password="${DOLT_SQL_PASSWORD:-${DP_DB_PASSWORD:-${DOLT_ROOT_PASSWORD:-}}}"

  if [ -z "$password" ]; then
    echo "DOLT_SQL_PASSWORD, DP_DB_PASSWORD, or DOLT_ROOT_PASSWORD is required" >&2
    exit 1
  fi

  local args=(
    "--host=${host}"
    "--port=${port}"
    "--user=${user}"
    "--password=${password}"
  )

  if [ "${TLS_ENABLED:-false}" != "true" ]; then
    args+=(--no-tls)
  fi

  if [ -n "$db_name" ]; then
    args+=("--use-db=${db_name}")
  fi

  dolt "${args[@]}" sql "--query=${query}" --result-format=csv
}

list_databases() {
  run_dolt_sql "" "SHOW DATABASES;" | awk 'NR > 1 && length($0) > 0 {gsub(/\r$/, ""); print}'
}

capture_metadata() {
  mkdir -p "$SERVER_METADATA_DIR" "$DATABASE_METADATA_DIR"

  cat >"${SERVER_METADATA_DIR}/README.txt" <<'EOF'
This directory contains best-effort Dolt SQL server metadata captured alongside
the per-database dolt backup repositories.

The restore script does not automatically apply these files, because KubeBlocks
owns the rendered server config and account provisioning for this addon.
Review and restore them manually if the backup is used for full server migration.
EOF

  copy_if_exists "/etc/dolt/servercfg.d" "${SERVER_METADATA_DIR}/servercfg.d"
  copy_if_exists "/etc/dolt/doltcfg.d" "${SERVER_METADATA_DIR}/doltcfg.d"
  copy_if_exists "${DATA_DIR}/.doltcfg" "${SERVER_METADATA_DIR}/data-dir-dot-doltcfg"
}

rm -rf "$STAGING_ROOT"
mkdir -p "$WORK_DIR/repos"
touch "$MANIFEST"
capture_metadata

DATABASE_LIST="${WORK_DIR}/databases.txt"
if ! list_databases >"$DATABASE_LIST"; then
  echo "failed to list Dolt databases; refusing to create a successful empty backup" >&2
  exit 1
fi

found=0
while IFS= read -r db_name; do
  [ -n "$db_name" ] || continue
  case "$db_name" in
    */*|.*|*..*)
      echo "invalid database directory name: ${db_name}" >&2
      exit 1
      ;;
  esac

  dbdir="${DATA_DIR}/${db_name}"
  if [ "$dbdir" = "$STAGING_ROOT" ]; then
    continue
  fi
  if [ ! -d "$dbdir/.dolt" ]; then
    echo "skipping non-Dolt database ${db_name}"
    continue
  fi

  copy_if_exists "$dbdir/.dolt/config.json" "${DATABASE_METADATA_DIR}/${db_name}/.dolt/config.json"
  copy_if_exists "$dbdir/.dolt/repo_state.json" "${DATABASE_METADATA_DIR}/${db_name}/.dolt/repo_state.json"

  echo "syncing Dolt database ${db_name} through dolt_backup()"
  mkdir -p "$WORK_DIR/repos/$db_name"
  backup_url="file://$WORK_DIR/repos/$db_name"
  run_dolt_sql "$db_name" "CALL dolt_backup('sync-url', '$(sql_quote "$backup_url")');"
  printf '%s\t%s\n' "$db_name" "repos/$db_name" >>"$MANIFEST"
  found=1
done <"$DATABASE_LIST"

if [ "$found" -eq 0 ]; then
  echo "no Dolt databases found under ${DATA_DIR}; creating an empty backup archive"
fi
