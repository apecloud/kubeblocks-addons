# shellcheck shell=bash

mkdir "${work_dir}/backup"
datasafed pull influxdb-full.tar - | tar -C "${work_dir}/backup" -xf -
# Full restore replaces BoltDB, SQLite and all shards. KubeBlocks restores the
# source admin account secret when creating the destination cluster.
case "${INFLUX_BACKUP_MODE:-full}" in
  full) influx restore --full "${work_dir}/backup" ;;
  selective)
    backup_dir="${work_dir}/backup"
    if [[ -n ${selection:-} ]]; then
      parse_selection "$selection" || { echo "Invalid InfluxDB bucket selection" >&2; exit 1; }
    elif [[ -d "$backup_dir/selected" ]]; then
      parents=()
      children=()
      for archive_dir in "$backup_dir"/selected/*/*; do
        [[ -d "$archive_dir" ]] || continue
        org_dir=${archive_dir%/*}
        decode_archive_name "${org_dir##*/}"
        parents+=("$decoded_name")
        decode_archive_name "${archive_dir##*/}"
        children+=("$decoded_name")
      done
    else
      echo "A flat archive requires an explicit bucket selection" >&2
      exit 1
    fi
    if [[ -z ${parents[0]:-} ]]; then
      echo "No bucket archives found" >&2
      exit 1
    fi
    if (( ${#parents[@]} != 1 )) && [[ ! -d "$backup_dir/selected" || -n ${new_bucket:-} ]]; then
      echo "A flat archive or new_bucket requires exactly one selected bucket" >&2
      exit 1
    fi

    destinations=","
    restore_dirs=()
    for i in "${!parents[@]}"; do
      restore_dir="$backup_dir"
      if [[ -d "$backup_dir/selected" ]]; then
        org_path=$(encode_archive_name "${parents[i]}")
        bucket_path=$(encode_archive_name "${children[i]}")
        restore_dir="$backup_dir/selected/$org_path/$bucket_path"
        [[ -d "$restore_dir" ]] || { printf 'Bucket %q in organization %q is missing from the backup\n' "${children[i]}" "${parents[i]}" >&2; exit 1; }
      fi
      restore_dirs+=("$restore_dir")
      org_path=$(encode_archive_name "${new_org:-${parents[i]}}")
      bucket_path=$(encode_archive_name "${new_bucket:-${children[i]}}")
      key="$org_path/$bucket_path"
      if [[ "$destinations" == *",${key},"* ]]; then
        echo "Multiple selected buckets resolve to the same destination" >&2
        exit 1
      fi
      destinations="${destinations}${key},"
    done
    for i in "${!parents[@]}"; do
      args=(--org "${parents[i]}" --bucket "${children[i]}")
      if [[ -n ${new_bucket:-} ]]; then args+=(--new-bucket "$new_bucket"); fi
      if [[ -n ${new_org:-} ]]; then args+=(--new-org "$new_org"); fi
      influx restore "${args[@]}" "${restore_dirs[i]}"
    done
    ;;
  *) echo "Unknown backup mode" >&2; exit 1 ;;
esac
