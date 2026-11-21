# shellcheck shell=bash

echo "Starting InfluxDB cluster restore (import)..."

mkdir -p "${work_dir}/downloads"
file_list=()
file_policies=()
file_databases=()

# In a multi-pod cluster backup, KubeBlocks places each pod's backup under:
#   <parent_base_path>/<pod-name>/...
# When running restore on ANY single pod, we discover and restore archives across all pods.
if [[ -n ${DP_BACKUP_ROOT_PATH:-} && -n ${DP_BACKUP_NAME:-} ]]; then
  parent_base_path="${DP_BACKUP_ROOT_PATH}/${DP_BACKUP_NAME}"
else
  parent_base_path="$(dirname "${DP_BACKUP_BASE_PATH}")"
fi

pod_dir="${DP_TARGET_RELATIVE_PATH:-$(basename "${DP_BACKUP_BASE_PATH}")}"
parent_entries=$(DATASAFED_BACKEND_BASE_PATH="${parent_base_path}" datasafed list -r / 2>/dev/null || true)

if [[ "$parent_base_path" != "$DP_BACKUP_BASE_PATH" ]] && echo "$parent_entries" | grep -qE "^/?${pod_dir}/(selected/|export.*\.lp\.gz)"; then
  echo "Detected multi-pod cluster backup layout. Scanning all pod directories under ${parent_base_path}..."
  export DATASAFED_BACKEND_BASE_PATH="${parent_base_path}"
  all_entries="$parent_entries"
else
  all_entries=$(datasafed list -r / 2>/dev/null || true)
fi

if [[ "${INFLUX_BACKUP_MODE:-}" == dbrp-selective ]]; then
  rp_path='(^|.*/)selected/([^/]+)/rp/([^/]+)/data\.lp\.gz$'
  db_path='(^|.*/)selected/([^/]+)/db\.lp\.gz$'

  if [[ -n ${selection:-} ]]; then
    parse_selection "$selection" 1 || { echo "Invalid InfluxDB DB/RP restore selection" >&2; exit 1; }
    selection_matched=()
    while IFS= read -r relpath; do
      [ -n "$relpath" ] || continue
      relpath=${relpath#/}
      if [[ "$relpath" =~ $rp_path ]]; then
        encoded_db=${BASH_REMATCH[2]}
        encoded_rp=${BASH_REMATCH[3]}
        decode_archive_name "$encoded_db"
        entry_db="$decoded_name"
        decode_archive_name "$encoded_rp"
        entry_rp="$decoded_name"

        for idx in "${!parents[@]}"; do
          req_db="${parents[idx]}"
          req_rp="${children[idx]}"
          if [[ "$req_db" == "$entry_db" && ( -z "$req_rp" || "$req_rp" == "$entry_rp" ) ]]; then
            selection_matched[idx]=1
            file_list+=("$relpath")
            file_databases+=("$entry_db")
            file_policies+=("$entry_rp")
            break
          fi
        done
      elif [[ "$relpath" =~ $db_path ]]; then
        encoded_db=${BASH_REMATCH[2]}
        decode_archive_name "$encoded_db"
        entry_db="$decoded_name"

        for idx in "${!parents[@]}"; do
          req_db="${parents[idx]}"
          req_rp="${children[idx]}"
          if [[ "$req_db" == "$entry_db" && -z "$req_rp" ]]; then
            selection_matched[idx]=1
            file_list+=("$relpath")
            file_databases+=("")
            file_policies+=("")
            break
          fi
        done
      fi
    done <<< "$all_entries"

    for idx in "${!parents[@]}"; do
      if [[ -z ${selection_matched[idx]:-} ]]; then
        if [[ -n "${children[idx]}" ]]; then
          printf 'Cannot read backup for database %q, retention policy %q\n' "${parents[idx]}" "${children[idx]}" >&2
        else
          printf 'Cannot read backup for database %q\n' "${parents[idx]}" >&2
        fi
        exit 1
      fi
    done
  else
    while IFS= read -r relpath; do
      [ -n "$relpath" ] || continue
      relpath=${relpath#/}
      if [[ "$relpath" =~ $rp_path ]]; then
        encoded_db=${BASH_REMATCH[2]}
        encoded_rp=${BASH_REMATCH[3]}
        decode_archive_name "$encoded_db"
        file_databases+=("$decoded_name")
        decode_archive_name "$encoded_rp"
        file_policies+=("$decoded_name")
        file_list+=("$relpath")
      elif [[ "$relpath" =~ $db_path ]]; then
        file_databases+=("")
        file_policies+=("")
        file_list+=("$relpath")
      fi
    done <<< "$all_entries"
  fi
else
  # Discover legacy exports across all pods or in this pod's backup path
  legacy_path='(^|.*/)export.*\.lp\.gz$'
  while IFS= read -r relpath; do
    [ -n "$relpath" ] || continue
    relpath=${relpath#/}
    if [[ "$relpath" =~ $legacy_path ]]; then
      file_list+=("$relpath")
    fi
  done <<< "$all_entries"
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

if [ ${#file_list[@]} -eq 0 ]; then
  echo "ERROR: No matching backup export files found to restore." >&2
  exit 1
fi

files_to_import=()
dbrp_created=","
for i in "${!file_list[@]}"; do
  relpath=${file_list[i]}
  target_file="${work_dir}/downloads/${i}.lp.gz"
  clean_file="${work_dir}/downloads/clean_${i}.lp.gz"
  database=${file_databases[i]:-}
  retention=${file_policies[i]:-}
  # Quote InfluxQL identifiers used when restoring individual retention policies.
  quoted_db="\"${database//\\/\\\\}\""
  quoted_rp="\"${retention//\\/\\\\}\""

  # Emit CREATE RETENTION POLICY only once per (database, retention) pair to avoid duplicate errors.
  emit_rp=0
  if [[ -n "$database" && -n "$retention" && "$retention" != "autogen" ]]; then
    dbrp_key="${database}/${retention}"
    if [[ "$dbrp_created" != *",${dbrp_key},"* ]]; then
      dbrp_created="${dbrp_created}${dbrp_key},"
      emit_rp=1
    fi
  fi

  echo "Pulling ${relpath}..."
  if ! datasafed pull "/${relpath#/}" "$target_file"; then
    if [[ "${INFLUX_BACKUP_MODE:-}" == dbrp-selective && -n ${selection:-} ]]; then
      printf 'Cannot read backup for database %q, retention policy %q\n' "$database" "$retention" >&2
    fi
    exit 1
  fi
  # Prepare every archive before importing any data. Keep monitoring data out of the target.
  gzip -dc "$target_file" | DATABASE="$quoted_db" RETENTION="$quoted_rp" EMIT_RP="$emit_rp" awk '
    /^CREATE DATABASE ("_internal"|_internal)([[:space:];]|$)/ { next }
    /^# CONTEXT-DATABASE:_internal$/ { skip=1; next }
    /^# CONTEXT-DATABASE:/ { skip=0 }
    /^CREATE DATABASE / && ENVIRON["RETENTION"] != "\"\"" {
      # A filtered export uses WITH NAME, which tries to set the default RP.
      # Create the database and each selected RP independently instead.
      print "CREATE DATABASE " ENVIRON["DATABASE"]
      if (ENVIRON["EMIT_RP"] == "1") {
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
