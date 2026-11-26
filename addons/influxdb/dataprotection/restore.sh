# shellcheck shell=bash

mkdir "${work_dir}/backup"
datasafed pull influxdb-full.tar - | tar -C "${work_dir}/backup" -xf -
# Full restore replaces BoltDB, SQLite and all shards. KubeBlocks restores the
# source admin account secret when creating the destination cluster.
case "${INFLUX_BACKUP_MODE:-full}" in
  full) influx restore --full "${work_dir}/backup" ;;
  selective)
    backup_dir="${work_dir}/backup"
    archive_base="$backup_dir"
    if [[ -d "$backup_dir/selected" ]]; then
      archive_base="$backup_dir/selected"
    fi

    target_parents=()
    target_children=()
    is_flat=0

    has_structured=0
    for b_dir in "$archive_base"/*/*; do
      if [[ -d "$b_dir" ]]; then
        has_structured=1
        break
      fi
    done
    if [[ $has_structured -eq 0 ]]; then
      is_flat=1
    fi

    if [[ -n ${selection:-} ]]; then
      parse_selection "$selection" 1 || { echo "Invalid InfluxDB bucket selection" >&2; exit 1; }

      if [[ $is_flat -eq 1 ]]; then
        if (( ${#parents[@]} != 1 )) || [[ -z ${children[0]:-} ]]; then
          echo "A flat archive or new_bucket requires exactly one selected bucket" >&2
          exit 1
        fi
        target_parents=("${parents[0]}")
        target_children=("${children[0]}")
      else
        for i in "${!parents[@]}"; do
          org="${parents[i]}"
          child="${children[i]}"
          org_path=$(encode_archive_name "$org")

          if [[ -z "$child" ]]; then
            org_dir="$archive_base/$org_path"
            if [[ ! -d "$org_dir" ]]; then
              printf 'Organization %q is missing from the backup\n' "$org" >&2
              exit 1
            fi
            found_bucket=0
            for b_dir in "$org_dir"/*; do
              [[ -d "$b_dir" ]] || continue
              decode_archive_name "${b_dir##*/}"
              target_parents+=("$org")
              target_children+=("$decoded_name")
              found_bucket=1
            done
            if [[ $found_bucket -eq 0 ]]; then
              printf 'Organization %q is missing from the backup\n' "$org" >&2
              exit 1
            fi
          else
            bucket_path=$(encode_archive_name "$child")
            b_dir="$archive_base/$org_path/$bucket_path"
            if [[ ! -d "$b_dir" ]]; then
              printf 'Bucket %q in organization %q is missing from the backup\n' "$child" "$org" >&2
              exit 1
            fi
            target_parents+=("$org")
            target_children+=("$child")
          fi
        done
      fi
    else
      if [[ $is_flat -eq 1 ]]; then
        echo "A flat archive requires an explicit bucket selection" >&2
        exit 1
      fi
      for b_dir in "$archive_base"/*/*; do
        [[ -d "$b_dir" ]] || continue
        org_dir=${b_dir%/*}
        decode_archive_name "${org_dir##*/}"
        org_name="$decoded_name"
        decode_archive_name "${b_dir##*/}"
        target_parents+=("$org_name")
        target_children+=("$decoded_name")
      done
    fi

    if [[ -z ${target_parents[0]:-} ]]; then
      echo "No bucket archives found" >&2
      exit 1
    fi

    if [[ -n ${new_bucket:-} ]] && (( ${#target_parents[@]} != 1 )); then
      echo "A flat archive or new_bucket requires exactly one selected bucket" >&2
      exit 1
    fi

    declare -A seen_destinations=()
    restore_dirs=()
    for i in "${!target_parents[@]}"; do
      org="${target_parents[i]}"
      bucket="${target_children[i]}"
      if [[ $is_flat -eq 1 ]]; then
        restore_dir="$backup_dir"
      else
        org_path=$(encode_archive_name "$org")
        bucket_path=$(encode_archive_name "$bucket")
        restore_dir="$archive_base/$org_path/$bucket_path"
      fi
      restore_dirs+=("$restore_dir")

      dest_org=$(encode_archive_name "${new_org:-$org}")
      dest_bucket=$(encode_archive_name "${new_bucket:-$bucket}")
      key="$dest_org/$dest_bucket"
      if [[ -n "${seen_destinations[$key]:-}" ]]; then
        echo "Multiple selected buckets resolve to the same destination" >&2
        exit 1
      fi
      seen_destinations[$key]=1
    done

    for i in "${!target_parents[@]}"; do
      args=(--org "${target_parents[i]}" --bucket "${target_children[i]}")
      if [[ -n ${new_bucket:-} ]]; then args+=(--new-bucket "$new_bucket"); fi
      if [[ -n ${new_org:-} ]]; then args+=(--new-org "$new_org"); fi
      influx restore "${args[@]}" "${restore_dirs[i]}"
    done
    ;;
  *) echo "Unknown backup mode" >&2; exit 1 ;;
esac
