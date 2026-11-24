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
      parse_selection "$selection" 1 || { echo "Invalid InfluxDB bucket selection" >&2; exit 1; }
    elif [[ -d "$backup_dir/selected" ]]; then
      parents=()
      children=()
      for archive_dir in "$backup_dir"/selected/*/*; do
        [[ -d "$archive_dir" ]] || continue
        org_dir=${archive_dir%/*}
        decode_archive_name "${org_dir##*/}"
        org_name="$decoded_name"
        bucket_part=${archive_dir##*/}
        if [[ "$bucket_part" == "_all" ]]; then
          parents+=("$org_name")
          children+=("")
        else
          decode_archive_name "$bucket_part"
          parents+=("$org_name")
          children+=("$decoded_name")
        fi
      done
    else
      echo "A flat archive requires an explicit bucket selection" >&2
      exit 1
    fi
    if [[ -z ${parents[0]:-} ]]; then
      echo "No bucket archives found" >&2
      exit 1
    fi
    if [[ -n ${new_bucket:-} && ( ${#parents[@]} != 1 || -z ${children[0]:-} ) ]]; then
      echo "A flat archive or new_bucket requires exactly one selected bucket" >&2
      exit 1
    fi
    if [[ ! -d "$backup_dir/selected" && ( ${#parents[@]} != 1 || -z ${children[0]:-} ) ]]; then
      echo "A flat archive or new_bucket requires exactly one selected bucket" >&2
      exit 1
    fi

    # Expand parent-only organization selections if only individual bucket archives exist
    expanded_parents=()
    expanded_children=()
    for i in "${!parents[@]}"; do
      org_path=$(encode_archive_name "${parents[i]}")
      if [[ -z "${children[i]}" && ! -d "$backup_dir/selected/$org_path/_all" && -d "$backup_dir/selected/$org_path" ]]; then
        found_any=0
        for b_dir in "$backup_dir/selected/$org_path"/*; do
          [[ -d "$b_dir" ]] || continue
          decode_archive_name "${b_dir##*/}"
          expanded_parents+=("${parents[i]}")
          expanded_children+=("$decoded_name")
          found_any=1
        done
        if [[ $found_any -eq 0 ]]; then
          printf 'Organization %q has no bucket archives in the backup\n' "${parents[i]}" >&2
          exit 1
        fi
      else
        expanded_parents+=("${parents[i]}")
        expanded_children+=("${children[i]}")
      fi
    done
    parents=("${expanded_parents[@]}")
    children=("${expanded_children[@]}")

    destinations=","
    restore_dirs=()
    for i in "${!parents[@]}"; do
      restore_dir="$backup_dir"
      if [[ -d "$backup_dir/selected" ]]; then
        org_path=$(encode_archive_name "${parents[i]}")
        if [[ -n "${children[i]}" ]]; then
          bucket_path=$(encode_archive_name "${children[i]}")
          if [[ -d "$backup_dir/selected/$org_path/$bucket_path" ]]; then
            restore_dir="$backup_dir/selected/$org_path/$bucket_path"
          elif [[ -d "$backup_dir/selected/$org_path/_all" ]]; then
            restore_dir="$backup_dir/selected/$org_path/_all"
          else
            printf 'Bucket %q in organization %q is missing from the backup\n' "${children[i]}" "${parents[i]}" >&2
            exit 1
          fi
        else
          if [[ -d "$backup_dir/selected/$org_path/_all" ]]; then
            restore_dir="$backup_dir/selected/$org_path/_all"
          else
            printf 'Organization %q is missing from the backup\n' "${parents[i]}" >&2
            exit 1
          fi
        fi
      fi
      restore_dirs+=("$restore_dir")
      dest_org=$(encode_archive_name "${new_org:-${parents[i]}}")
      dest_bucket=$(encode_archive_name "${new_bucket:-${children[i]}}")
      key="$dest_org/$dest_bucket"
      if [[ "$destinations" == *",${key},"* ]]; then
        echo "Multiple selected buckets resolve to the same destination" >&2
        exit 1
      fi
      destinations="${destinations}${key},"
    done
    for i in "${!parents[@]}"; do
      args=(--org "${parents[i]}")
      if [[ -n "${children[i]}" ]]; then
        args+=(--bucket "${children[i]}")
      fi
      if [[ -n ${new_bucket:-} ]]; then args+=(--new-bucket "$new_bucket"); fi
      if [[ -n ${new_org:-} ]]; then args+=(--new-org "$new_org"); fi
      influx restore "${args[@]}" "${restore_dirs[i]}"
    done
    ;;
  *) echo "Unknown backup mode" >&2; exit 1 ;;
esac
