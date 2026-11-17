# shellcheck shell=bash

echo "Starting InfluxDB cluster restore (import)..."

mkdir -p "${work_dir}/downloads"
files_to_import=()

# Discover all export*.lp.gz files in current DP_BACKUP_BASE_PATH
file_list=()
while IFS= read -r relpath; do
  [ -n "$relpath" ] && file_list+=("$relpath")
done < <(datasafed list -r / 2>/dev/null | grep -E '(^|/)export.*\.lp\.gz$' || true)

# Fallback: check parent directory if needed
if [ ${#file_list[@]} -eq 0 ]; then
  parent_base_path="$(dirname "${DP_BACKUP_BASE_PATH}")"
  echo "Checking parent path: ${parent_base_path}..."
  export DATASAFED_BACKEND_BASE_PATH="${parent_base_path}"
  while IFS= read -r relpath; do
    [ -n "$relpath" ] && file_list+=("$relpath")
  done < <(datasafed list -r / 2>/dev/null | grep -E '(^|/)export.*\.lp\.gz$' || true)
fi

if [ ${#file_list[@]} -eq 0 ]; then
  echo "ERROR: No backup export files found to restore." >&2
  exit 1
fi

echo "Found ${#file_list[@]} export file(s) to pull."

for relpath in "${file_list[@]}"; do
  remote_path="/${relpath#/}"
  local_name="$(echo "${relpath}" | tr '/' '_')"
  target_file="${work_dir}/downloads/${local_name}"
  echo "Pulling ${remote_path} to ${target_file}..."
  datasafed pull "${remote_path}" "${target_file}"
  files_to_import+=("${target_file}")
done

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
  clean_file="${work_dir}/clean_$(basename "${f}")"
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
