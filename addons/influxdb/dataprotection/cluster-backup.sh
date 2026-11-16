# shellcheck shell=bash

: "${DP_BACKUP_INFO_FILE:?}"
data_dir="${DATA_DIR:-/var/lib/influxdb}"

mkdir -p "${work_dir}"
export_file="${work_dir}/export.lp.gz"

echo "Starting InfluxDB cluster data export on $(hostname)..."

# Export local shard data from TSM and WAL into compressed line protocol format
influx_inspect export \
  -compress \
  -datadir "${data_dir}/data" \
  -waldir "${data_dir}/wal" \
  -out "${export_file}"

echo "Export completed. Uploading export file to backup repository..."
datasafed push "${export_file}" "export.lp.gz"

# In strategy: All, each pod writes to its own DP_BACKUP_BASE_PATH subpath.
# Calculate total size of this pod's export
total_size=$(datasafed stat export.lp.gz | awk '$1 == "TotalSize:" {print $2}')
if [[ -z "$total_size" || ! "$total_size" =~ ^[0-9]+$ ]]; then
  total_size=$(datasafed stat / | awk '$1 == "TotalSize:" {print $2}')
fi
[[ "$total_size" =~ ^[0-9]+$ ]] || { echo "Invalid backup size" >&2; exit 1; }
printf '{"totalSize":"%s"}' "$total_size" > "${DP_BACKUP_INFO_FILE}"
echo "Backup export finished. Total size: ${total_size} bytes."
