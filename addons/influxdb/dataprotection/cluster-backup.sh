# shellcheck shell=bash

: "${DP_BACKUP_INFO_FILE:?}"
data_dir="${DATA_DIR:-/var/lib/influxdb}"
export_dir="${work_dir}/exports"
parallel_jobs="${BACKUP_CONCURRENCY:-${DP_BACKUP_PARALLELISM:-4}}"

mkdir -p "${export_dir}"

echo "Starting InfluxDB cluster data export on $(hostname)..."
echo "Export concurrency: ${parallel_jobs}"

# Wait for InfluxDB to be accessible
echo "Connecting to InfluxDB at ${INFLUX_HOST}:${INFLUX_PORT}..."
until influx -host "${INFLUX_HOST}" -port "${INFLUX_PORT}" -username "${INFLUX_USER}" -password "${INFLUX_PASSWORD}" -execute "SHOW DATABASES" >/dev/null 2>&1; do
  echo "Waiting for InfluxDB to be ready..."
  sleep 3
done

# Export databases in parallel using xargs
if [ -n "${databases:-}" ]; then
  echo "Selective backup requested for database(s): ${databases}"
  db_source=$(echo "${databases}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -vE "^(_internal)?$")
else
  echo "Full backup: exporting all non-internal databases..."
  db_source=$(influx -host "${INFLUX_HOST}" -port "${INFLUX_PORT}" -username "${INFLUX_USER}" -password "${INFLUX_PASSWORD}" -execute "SHOW DATABASES" | \
    tail -n +4 | \
    grep -vE "^(_internal)?$")
fi

echo "${db_source}" | xargs -r -P "${parallel_jobs}" -I {} \
  influx_inspect export \
    -compress \
    -datadir "${data_dir}/data" \
    -waldir "${data_dir}/wal" \
    -database "{}" \
    -out "${export_dir}/export_{}.lp.gz"

echo "Export completed. Uploading export file(s) to backup repository..."
exported_count=0
for f in "${export_dir}"/export_*.lp.gz; do
  [ -f "${f}" ] || continue
  file_name=$(basename "${f}")
  echo "Uploading ${file_name}..."
  datasafed push "${f}" "${file_name}"
  exported_count=$((exported_count + 1))
done

if [ ${exported_count} -eq 0 ]; then
  echo "No business databases found to export. Uploading empty marker."
  empty_file="${export_dir}/export_empty.lp.gz"
  echo "" | gzip > "${empty_file}"
  datasafed push "${empty_file}" "export_empty.lp.gz"
fi

# Calculate total size across all uploaded files for this pod
total_size=$(datasafed stat / | awk '$1 == "TotalSize:" {print $2}')
if [[ -z "$total_size" || ! "$total_size" =~ ^[0-9]+$ ]]; then
  total_size=0
  for f in "${export_dir}"/export_*.lp.gz; do
    [ -f "${f}" ] || continue
    sz=$(stat -c%s "${f}" 2>/dev/null || stat -f%z "${f}" 2>/dev/null || wc -c < "${f}")
    total_size=$((total_size + sz))
  done
fi

[[ "$total_size" =~ ^[0-9]+$ ]] || { echo "Invalid backup size" >&2; exit 1; }
printf '{"totalSize":"%s"}' "$total_size" > "${DP_BACKUP_INFO_FILE}"
echo "Backup export finished. Total size: ${total_size} bytes across ${exported_count} database(s)."
