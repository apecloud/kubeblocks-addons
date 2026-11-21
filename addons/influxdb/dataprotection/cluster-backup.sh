# shellcheck shell=bash

: "${DP_BACKUP_INFO_FILE:?}"
data_dir="${DATA_DIR:-/var/lib/influxdb}"
export_dir="${work_dir}/exports"
parallel_jobs="${BACKUP_CONCURRENCY:-${DP_BACKUP_PARALLELISM:-4}}"
dedup_enabled=false
assigned_shards_file="${work_dir}/assigned_shards.txt"

mkdir -p "${export_dir}"

cleanup_stage_dirs() {
  rm -rf "${data_dir}"/.stage_export_* 2>/dev/null || true
  cleanup
}
trap cleanup_stage_dirs EXIT

influx_query() {
  influx -host "$INFLUX_HOST" -port "$INFLUX_PORT" -username "$INFLUX_USER" -password "$INFLUX_PASSWORD" "$@"
}

echo "Starting InfluxDB cluster data export on $(hostname)..."
echo "Export concurrency: ${parallel_jobs}"

# ---------------------------------------------------------
# Deduplication Scheme 1: Min Owner ID Shard Arbitration
# ---------------------------------------------------------
if [[ "${INFLUX_EXPORT_DEDUP:-true}" != "false" ]]; then
  echo "Checking cluster shard distribution for replica deduplication..."
  shards_csv=$(influx_query -format csv -execute "SHOW SHARDS" 2>/dev/null || true)
  if [[ "$shards_csv" =~ (^|[[:space:]])shards([,[:space:]]|$) ]]; then
    my_node_id=""

    # 1. Try to find node ID from SHOW DIAGNOSTICS
    diag_out=$(influx_query -execute "SHOW DIAGNOSTICS" 2>/dev/null || true)
    my_node_id=$(echo "$diag_out" | awk -F': ' '/node_id|nodeID/ {print $2; exit}' | tr -d ' \r\n')

    # 2. Try to find node ID from /debug/vars
    if [[ -z "$my_node_id" || ! "$my_node_id" =~ ^[0-9]+$ ]]; then
      vars_out=$(curl -s -m 3 "http://${INFLUX_HOST}:${INFLUX_PORT}/debug/vars" 2>/dev/null || true)
      my_node_id=$(echo "$vars_out" | grep -oE '"nodeID":\s*"?([0-9]+)"?' | grep -oE '[0-9]+' | head -n 1 || true)
    fi

    # 3. Try to match pod name in SHOW SHARDS owners field
    pod_name="${DP_TARGET_RELATIVE_PATH:-${CURRENT_POD_NAME:-$(hostname)}}"
    if [[ -z "$my_node_id" || ! "$my_node_id" =~ ^[0-9]+$ ]]; then
      my_node_id=$(echo "$shards_csv" | awk -F',' -v p="$pod_name" '
        NR > 1 && $1 == "shards" && $9 ~ p {
          gsub(/["\[\]{}]/, "", $9)
          gsub(/,/, " ", $9)
          n = split($9, tokens, " ")
          for (i = 1; i <= n; i++) {
            if (tokens[i] ~ p) {
              if (match(tokens[i], /^[0-9]+/)) {
                print substr(tokens[i], RSTART, RLENGTH)
                exit
              } else if (i > 1 && match(tokens[i-1], /^[0-9]+/)) {
                print substr(tokens[i-1], RSTART, RLENGTH)
                exit
              }
            }
          }
        }
      ')
    fi

    # 4. Fallback: map pod ordinal to sorted unique node IDs
    if [[ -z "$my_node_id" || ! "$my_node_id" =~ ^[0-9]+$ ]]; then
      if [[ "$pod_name" =~ -([0-9]+)$ ]]; then
        ordinal="${BASH_REMATCH[1]}"
        unique_ids=($(echo "$shards_csv" | awk -F',' '
          NR > 1 && $1 == "shards" {
            owners_field = $9
            gsub(/["\[\]{}]/, "", owners_field)
            gsub(/,/, " ", owners_field)
            n = split(owners_field, raw_tokens, " ")
            for (i = 1; i <= n; i++) {
              if (match(raw_tokens[i], /^[0-9]+/)) {
                ids[substr(raw_tokens[i], RSTART, RLENGTH) + 0] = 1
              }
            }
          }
          END {
            for (id in ids) print id
          }
        ' | sort -n))

        if (( ordinal < ${#unique_ids[@]} )); then
          my_node_id="${unique_ids[ordinal]}"
        fi
      fi
    fi

    if [[ -n "$my_node_id" && "$my_node_id" =~ ^[0-9]+$ ]]; then
      echo "$shards_csv" | awk -F',' -v my_id="$my_node_id" '
        NR > 1 && $1 == "shards" {
          s_id = $2
          db = $3
          rp = $4
          owners_field = $9
          gsub(/["\[\]{}]/, "", owners_field)
          gsub(/,/, " ", owners_field)
          n = split(owners_field, raw_tokens, " ")
          min_id = ""
          for (i = 1; i <= n; i++) {
            token = raw_tokens[i]
            if (match(token, /^[0-9]+/)) {
              id = substr(token, RSTART, RLENGTH) + 0
              if (min_id == "" || id < min_id) {
                min_id = id
              }
            }
          }
          if (min_id != "" && min_id == my_id) {
            print db "/" rp "/" s_id
          }
        }
      ' > "$assigned_shards_file"

      assigned_count=$(wc -l < "$assigned_shards_file" | tr -d ' ')
      echo "Deduplication active (Node ID: ${my_node_id}). Primary shards assigned to this node: ${assigned_count}"
      dedup_enabled=true
    else
      echo "WARNING: Could not determine current node ID. Exporting all local shards without deduplication."
    fi
  else
    echo "WARNING: SHOW SHARDS unavailable. Exporting all local shards without deduplication."
  fi
fi

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
    data_dir="$1"
    assigned_file="$2"
    dedup_enabled="$3"
    database="$4"
    retention="${5#rp:}"
    out_file="$6"

    source_data_dir="${data_dir}/data"
    source_wal_dir="${data_dir}/wal"
    stage_dir=""

    if [[ "$dedup_enabled" == "true" && -f "$assigned_file" ]]; then
      stage_dir=$(mktemp -d -p "${data_dir}" ".stage_export_XXXXXX")
      mkdir -p "${stage_dir}/data/${database}"
      mkdir -p "${stage_dir}/wal/${database}"

      if [[ -n "$retention" ]]; then
        if [[ -d "${data_dir}/data/${database}/${retention}" ]]; then
          for s_dir in "${data_dir}/data/${database}/${retention}"/*; do
            [[ -d "$s_dir" ]] || continue
            s_id=$(basename "$s_dir")
            if grep -qFx "${database}/${retention}/${s_id}" "$assigned_file"; then
              mkdir -p "${stage_dir}/data/${database}/${retention}"
              cp -al "${s_dir}" "${stage_dir}/data/${database}/${retention}/"
              if [[ -d "${data_dir}/wal/${database}/${retention}/${s_id}" ]]; then
                mkdir -p "${stage_dir}/wal/${database}/${retention}"
                cp -al "${data_dir}/wal/${database}/${retention}/${s_id}" "${stage_dir}/wal/${database}/${retention}/"
              fi
            fi
          done
        fi
      else
        if [[ -d "${data_dir}/data/${database}" ]]; then
          for rp_dir in "${data_dir}/data/${database}"/*; do
            [[ -d "$rp_dir" ]] || continue
            rp=$(basename "$rp_dir")
            for s_dir in "${rp_dir}"/*; do
              [[ -d "$s_dir" ]] || continue
              s_id=$(basename "$s_dir")
              if grep -qFx "${database}/${rp}/${s_id}" "$assigned_file"; then
                mkdir -p "${stage_dir}/data/${database}/${rp}"
                cp -al "${s_dir}" "${stage_dir}/data/${database}/${rp}/"
                if [[ -d "${data_dir}/wal/${database}/${rp}/${s_id}" ]]; then
                  mkdir -p "${stage_dir}/wal/${database}/${rp}"
                  cp -al "${data_dir}/wal/${database}/${rp}/${s_id}" "${stage_dir}/wal/${database}/${rp}/"
                fi
              fi
            done
          done
        fi
      fi

      source_data_dir="${stage_dir}/data"
      source_wal_dir="${stage_dir}/wal"
    fi

    args=(-compress -datadir "$source_data_dir" -waldir "$source_wal_dir" -database "$database" -out "$out_file")
    if [[ -n "$retention" ]]; then
      args+=(-retention "$retention")
    fi

    influx_inspect export "${args[@]}"
    status=$?

    if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
      rm -rf "$stage_dir"
    fi

    exit $status
  ' _ "$data_dir" "$assigned_shards_file" "$dedup_enabled"
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
