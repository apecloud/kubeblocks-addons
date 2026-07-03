#!/bin/bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/dolt}"
STAGING_ROOT="${DOLT_RESTORE_STAGING_DIR:-${DATA_DIR}/.kb-doltdb-restore}"
WORK_DIR="${STAGING_ROOT}/current"
MANIFEST="${WORK_DIR}/manifest.tsv"

if [[ "$DATA_DIR" != /* || "$DATA_DIR" == "/" ]]; then
  echo "invalid DATA_DIR: ${DATA_DIR}" >&2
  exit 1
fi
if [[ "$STAGING_ROOT" != "$DATA_DIR"/* ]]; then
  echo "invalid DOLT_RESTORE_STAGING_DIR: ${STAGING_ROOT}" >&2
  exit 1
fi
if [ ! -f "$MANIFEST" ]; then
  echo "restore staging manifest not found: ${MANIFEST}" >&2
  exit 1
fi

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
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

is_replication_primary_database() {
  local db_name="$1"
  local query result

  query="SELECT role FROM dolt_cluster.dolt_cluster_status WHERE \`database\` = '$(sql_quote "$db_name")';"
  result="$(run_dolt_sql "$db_name" "$query" 2>/dev/null || true)"
  echo "$result" | awk 'NR > 1 && $0 == "primary" {found = 1} END {exit !found}'
}

trigger_replication_after_restore() {
  local db_name="$1"

  if ! is_replication_primary_database "$db_name"; then
    return
  fi

  echo "creating empty Dolt commit for ${db_name} to trigger post-restore replication"
  run_dolt_sql "$db_name" "CALL DOLT_COMMIT('--allow-empty', '-m', 'kb restore replication trigger');"
}

restored=0
while IFS=$'\t' read -r db_name repo_rel; do
  [ -n "$db_name" ] || continue
  case "$db_name" in
    */*|.*|*..*)
      echo "invalid database name in backup manifest: ${db_name}" >&2
      exit 1
      ;;
  esac
  case "$repo_rel" in
    repos/*) ;;
    *)
      echo "invalid repository path in backup manifest: ${repo_rel}" >&2
      exit 1
      ;;
  esac

  repo="${WORK_DIR}/${repo_rel}"
  if [ ! -d "$repo" ]; then
    echo "repository path from backup manifest does not exist: ${repo_rel}" >&2
    exit 1
  fi

  echo "restoring Dolt database ${db_name} through dolt_backup()"
  run_dolt_sql "" "CALL dolt_backup('restore', '$(sql_quote "file://$repo")', '$(sql_quote "$db_name")', '--force');"
  trigger_replication_after_restore "$db_name"
  restored=1
done <"$MANIFEST"

if [ "$restored" -eq 0 ]; then
  echo "backup archive did not contain Dolt databases"
fi

rm -rf "$STAGING_ROOT"
