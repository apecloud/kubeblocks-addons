# shellcheck shell=bash

echo "Starting InfluxDB cluster restore (import)..."

mkdir -p "${work_dir}/downloads"
file_list=()
file_policies=()
file_databases=()

if [[ "${INFLUX_BACKUP_MODE:-}" == dbrp-selective ]]; then
  if [[ -n ${selection:-} ]]; then
    parse_selection "$selection" 1 || { echo "Invalid InfluxDB DB/RP restore selection" >&2; exit 1; }
    declare -A selected
    for i in "${!parents[@]}"; do
      key=$(cluster_archive_path "${parents[i]}" "${children[i]}")
      if [[ -z ${selected[$key]:-} ]]; then
        selected[$key]=1
        file_list+=("$key")
        file_databases+=("${parents[i]}")
        file_policies+=("${children[i]}")
      fi
    done
  else
    # Restrict discovery to this source pod's backup path.
    entries=$(datasafed list -r /)
    rp_path='^selected/([^/]+)/rp/([^/]+)/data\.lp\.gz$'
    db_path='^selected/[^/]+/db\.lp\.gz$'
    while IFS= read -r relpath; do
      relpath=${relpath#/}
      if [[ "$relpath" =~ $rp_path ]]; then
        encoded_db=${BASH_REMATCH[1]}
        encoded_rp=${BASH_REMATCH[2]}
        decode_archive_name "$encoded_db"
        file_databases+=("$decoded_name")
        decode_archive_name "$encoded_rp"
        file_policies+=("$decoded_name")
      elif [[ "$relpath" =~ $db_path ]]; then
        file_databases+=("")
        file_policies+=("")
      else
        continue
      fi
      file_list+=("$relpath")
    done <<< "$entries"
  fi
else
  # Discover legacy exports in this pod's backup path, then fall back to the parent.
  while IFS= read -r relpath; do
    [ -n "$relpath" ] && file_list+=("$relpath")
  done < <(datasafed list -r / 2>/dev/null | grep -E '(^|/)export.*\.lp\.gz$' || true)

  if [ ${#file_list[@]} -eq 0 ]; then
    parent_base_path="$(dirname "${DP_BACKUP_BASE_PATH}")"
    echo "Checking parent path: ${parent_base_path}..."
    export DATASAFED_BACKEND_BASE_PATH="${parent_base_path}"
    while IFS= read -r relpath; do
      [ -n "$relpath" ] && file_list+=("$relpath")
    done < <(datasafed list -r / 2>/dev/null | grep -E '(^|/)export.*\.lp\.gz$' || true)
  fi
fi

if [ ${#file_list[@]} -eq 0 ]; then
  echo "ERROR: No backup export files found to restore." >&2
  exit 1
fi

# Filter legacy database exports by filename before downloading them.
if [[ "${INFLUX_BACKUP_MODE:-}" != dbrp-selective && -n ${databases:-} ]]; then
  selected_dbs=()
  while IFS= read -r db; do
    [ -n "$db" ] && selected_dbs+=("$db")
  done < <(echo "${databases}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -vE "^(_internal)?$")

  if [ ${#selected_dbs[@]} -gt 0 ]; then
    filtered_files=()
    for f in "${file_list[@]}"; do
      fname=${f##*/}
      for db in "${selected_dbs[@]}"; do
        if [[ "$fname" == "export_${db}.lp.gz" ]]; then
          filtered_files+=("$f")
          break
        fi
      done
    done
    file_list=("${filtered_files[@]}")
    echo "Filtered to ${#file_list[@]} export file(s) for database(s): ${databases}"
  fi
fi

files_to_import=()
for i in "${!file_list[@]}"; do
  relpath=${file_list[i]}
  target_file="${work_dir}/downloads/${i}.lp.gz"
  clean_file="${work_dir}/downloads/clean_${i}.lp.gz"
  database=${file_databases[i]:-}
  retention=${file_policies[i]:-}
  # Quote InfluxQL identifiers used when restoring individual retention policies.
  quoted_db="\"${database//\\/\\\\}\""
  quoted_rp="\"${retention//\\/\\\\}\""
  echo "Pulling ${relpath}..."
  if ! datasafed pull "/${relpath#/}" "$target_file"; then
    if [[ "${INFLUX_BACKUP_MODE:-}" == dbrp-selective && -n ${selection:-} ]]; then
      printf 'Cannot read backup for database %q, retention policy %q\n' "$database" "$retention" >&2
    fi
    exit 1
  fi
  # Prepare every archive before importing any data. Keep monitoring data out of the target.
  gzip -dc "$target_file" | DATABASE="$quoted_db" RETENTION="$quoted_rp" awk '
    /^CREATE DATABASE ("_internal"|_internal)([[:space:];]|$)/ { next }
    /^# CONTEXT-DATABASE:_internal$/ { skip=1; next }
    /^# CONTEXT-DATABASE:/ { skip=0 }
    /^CREATE DATABASE / && ENVIRON["RETENTION"] != "\"\"" {
      # A filtered export uses WITH NAME, which tries to set the default RP.
      # Create the database and each selected RP independently instead.
      print "CREATE DATABASE " ENVIRON["DATABASE"]
      if (ENVIRON["RETENTION"] != "\"autogen\"") {
        print "CREATE RETENTION POLICY " ENVIRON["RETENTION"] " ON " ENVIRON["DATABASE"] " DURATION 0s REPLICATION 1"
      }
      next
    }
    !skip { print }
  ' | gzip > "$clean_file"
  rm -f "$target_file"
  files_to_import+=("$clean_file")
done

# Wait for InfluxDB cluster service to be accessible
echo "Connecting to InfluxDB at ${INFLUX_HOST}:${INFLUX_PORT}..."
until influx -host "${INFLUX_HOST}" -port "${INFLUX_PORT}" -username "${INFLUX_USER}" -password "${INFLUX_PASSWORD}" -execute "SHOW DATABASES" >/dev/null 2>&1; do
  echo "Waiting for InfluxDB to be ready..."
  sleep 3
done

for f in "${files_to_import[@]}"; do
  echo "Importing ${f} into InfluxDB cluster..."
  influx \
    -host "${INFLUX_HOST}" \
    -port "${INFLUX_PORT}" \
    -username "${INFLUX_USER}" \
    -password "${INFLUX_PASSWORD}" \
    -import \
    -compressed \
    -path="${f}"
done

echo "InfluxDB cluster import completed successfully."
