# shellcheck shell=bash

: "${DP_BACKUP_INFO_FILE:?}"
data_dir="${DATA_DIR:-/var/lib/influxdb}"
export_dir="${work_dir}/exports"
parallel_jobs="${BACKUP_CONCURRENCY:-${DP_BACKUP_PARALLELISM:-4}}"

mkdir -p "${export_dir}"

influx_query() {
  influx -host "$INFLUX_HOST" -port "$INFLUX_PORT" -username "$INFLUX_USER" -password "$INFLUX_PASSWORD" "$@"
}

echo "Starting InfluxDB cluster data export on $(hostname)..."
echo "Export concurrency: ${parallel_jobs}"

jobs=()
if [[ "${INFLUX_BACKUP_MODE:-}" == dbrp-selective ]]; then
  parse_selection "${selection:-}" 1 || { echo "Invalid or empty InfluxDB DB/RP selection" >&2; exit 1; }
  declare -A whole_databases policies_by_database exported
  for i in "${!parents[@]}"; do
    if [[ -z "${children[i]}" ]]; then
      database_key=$(encode_archive_name "${parents[i]}")
      whole_databases[$database_key]=1
    fi
  done
  for i in "${!parents[@]}"; do
    database=${parents[i]}
    retention=${children[i]}
    if [[ "$database" == _internal ]]; then
      echo "Cannot select the _internal database" >&2
      exit 1
    fi
    database_key=$(encode_archive_name "$database")
    if [[ -n "$retention" && -n ${whole_databases[$database_key]:-} ]]; then
      continue
    fi
    key=$(cluster_archive_path "$database" "$retention")
    if [[ -n ${exported[$key]:-} ]]; then
      continue
    fi
    # Check the metadata once per DB. An existing RP can have no local shards.
    if [[ ! ${policies_by_database[$database_key]+found} ]]; then
      policies_by_database[$database_key]=$(influx_query -database "$database" -format csv -execute 'SHOW RETENTION POLICIES')
    fi
    if [[ -n "$retention" ]]; then
      policies=${policies_by_database[$database_key]}
      # The RP name is the first CSV field, quoted when it contains a comma or newline.
      if [[ "$policies" != *$'\n'"\"$retention\","* ]] &&
        [[ "$retention" == *[,$'\r\n']* || "$policies" != *$'\n'"$retention,"* ]]; then
        printf 'Cannot find retention policy %q in database %q\n' "$retention" "$database" >&2
        exit 1
      fi
    fi
    exported[$key]=1
    mkdir -p "$export_dir/${key%/*}"
    jobs+=("$database" "rp:$retention" "$export_dir/$key")
  done
else
  # Keep the existing database-only parameters and archive names for the legacy actions.
  until influx_query -execute 'SHOW DATABASES' >/dev/null 2>&1; do
    echo "Waiting for InfluxDB to be ready..."
    sleep 3
  done
  if [[ -n ${databases:-} ]]; then
    db_source=$(printf '%s\n' "$databases" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  else
    db_source=$(influx_query -execute 'SHOW DATABASES' | tail -n +4)
  fi
  while IFS= read -r database; do
    if [[ -n "$database" && "$database" != _internal ]]; then
      jobs+=("$database" "rp:" "$export_dir/export_$database.lp.gz")
    fi
  done <<< "$db_source"
fi

if (( ${#jobs[@]} )); then
  # Keep all three xargs fields nonempty, even for a whole-database export.
  printf '%s\0' "${jobs[@]}" | xargs -0 -r -n 3 -P "$parallel_jobs" bash -c '
    args=(-compress -datadir "$0/data" -waldir "$0/wal" -database "$1" -out "$3")
    retention=${2#rp:}
    if [[ -n "$retention" ]]; then
      args+=(-retention "$retention")
    fi
    exec influx_inspect export "${args[@]}"
  ' "$data_dir"
fi

echo "Export completed. Uploading export file(s) to backup repository..."
exported_count=0
files=("$export_dir"/*.lp.gz "$export_dir"/selected/*/db.lp.gz "$export_dir"/selected/*/rp/*/data.lp.gz)
for f in "${files[@]}"; do
  [ -f "${f}" ] || continue
  file_name=${f#"$export_dir/"}
  echo "Uploading ${file_name}..."
  datasafed push "${f}" "${file_name}"
  exported_count=$((exported_count + 1))
done

if [ ${exported_count} -eq 0 ]; then
  echo "No business databases found to export. Uploading empty marker."
  empty_file="${export_dir}/export_empty.lp.gz"
  echo "" | gzip > "${empty_file}"
  datasafed push "${empty_file}" "export_empty.lp.gz"
  files+=("$empty_file")
fi

# Calculate total size across all uploaded files for this pod
total_size=$(datasafed stat / | awk '$1 == "TotalSize:" {print $2}')
if [[ -z "$total_size" || ! "$total_size" =~ ^[0-9]+$ ]]; then
  total_size=0
  for f in "${files[@]}"; do
    [ -f "${f}" ] || continue
    sz=$(stat -c%s "${f}" 2>/dev/null || stat -f%z "${f}" 2>/dev/null || wc -c < "${f}")
    total_size=$((total_size + sz))
  done
fi

[[ "$total_size" =~ ^[0-9]+$ ]] || { echo "Invalid backup size" >&2; exit 1; }
printf '{"totalSize":"%s"}' "$total_size" > "${DP_BACKUP_INFO_FILE}"
echo "Backup export finished. Total size: ${total_size} bytes across ${exported_count} export(s)."
