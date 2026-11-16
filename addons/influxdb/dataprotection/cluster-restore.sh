# shellcheck shell=bash

echo "Starting InfluxDB cluster restore (import)..."

mkdir -p "${work_dir}/downloads"
files_to_import=()

# Search for export.lp.gz in current DP_BACKUP_BASE_PATH (covering both root and per-pod subdirectories)
for entry in $(datasafed list / 2>/dev/null || true); do
  subpath="${entry%/}"
  if [ -n "$subpath" ] && datasafed stat "/${subpath}/export.lp.gz" >/dev/null 2>&1; then
    mkdir -p "${work_dir}/downloads/${subpath}"
    target_file="${work_dir}/downloads/${subpath}/export.lp.gz"
    echo "Found export file at /${subpath}/export.lp.gz, pulling..."
    datasafed pull "/${subpath}/export.lp.gz" "${target_file}"
    files_to_import+=("${target_file}")
  fi
done

# Check if export.lp.gz exists directly at root of DP_BACKUP_BASE_PATH
if datasafed stat "/export.lp.gz" >/dev/null 2>&1; then
  target_file="${work_dir}/downloads/export_root.lp.gz"
  echo "Found export file at /export.lp.gz, pulling..."
  datasafed pull "/export.lp.gz" "${target_file}"
  files_to_import+=("${target_file}")
fi

# Fallback: check parent directory if needed
if [ ${#files_to_import[@]} -eq 0 ]; then
  parent_base_path="$(dirname "${DP_BACKUP_BASE_PATH}")"
  echo "Checking parent path: ${parent_base_path}..."
  export DATASAFED_BACKEND_BASE_PATH="${parent_base_path}"
  for entry in $(datasafed list / 2>/dev/null || true); do
    subpath="${entry%/}"
    if [ -n "$subpath" ] && datasafed stat "/${subpath}/export.lp.gz" >/dev/null 2>&1; then
      mkdir -p "${work_dir}/downloads/${subpath}"
      target_file="${work_dir}/downloads/${subpath}/export.lp.gz"
      echo "Found export file at /${subpath}/export.lp.gz, pulling..."
      datasafed pull "/${subpath}/export.lp.gz" "${target_file}"
      files_to_import+=("${target_file}")
    fi
  done
fi

if [ ${#files_to_import[@]} -eq 0 ]; then
  echo "ERROR: No backup export files found to restore." >&2
  exit 1
fi

echo "Found ${#files_to_import[@]} export file(s) to import."

# Wait for InfluxDB cluster service to be accessible
echo "Connecting to InfluxDB at ${INFLUX_HOST}:${INFLUX_PORT}..."
until influx -host "${INFLUX_HOST}" -port "${INFLUX_PORT}" -username "${INFLUX_USER}" -password "${INFLUX_PASSWORD}" -execute "SHOW DATABASES" >/dev/null 2>&1; do
  echo "Waiting for InfluxDB to be ready..."
  sleep 3
done

# Filter out _internal monitor database commands and import files into cluster
for f in "${files_to_import[@]}"; do
  echo "Importing ${f} into InfluxDB cluster..."
  clean_file="${work_dir}/clean_$(basename "$(dirname "${f}")")_$(basename "${f}")"
  # Filter out _internal database DDL and DML to avoid polluting new cluster monitor stats
  zcat "${f}" | awk '
    /^CREATE DATABASE _internal/ { next }
    /^# CONTEXT-DATABASE:_internal/ { skip=1; next }
    /^# CONTEXT-DATABASE:/ { skip=0 }
    !skip { print }
  ' | gzip > "${clean_file}"

  influx \
    -host "${INFLUX_HOST}" \
    -port "${INFLUX_PORT}" \
    -username "${INFLUX_USER}" \
    -password "${INFLUX_PASSWORD}" \
    -import \
    -compressed \
    -path="${clean_file}"

  rm -f "${clean_file}"
done

echo "InfluxDB cluster import completed successfully."
