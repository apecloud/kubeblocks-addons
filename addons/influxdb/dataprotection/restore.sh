# shellcheck shell=bash

mkdir "${work_dir}/backup"
datasafed pull influxdb-full.tar - | tar -C "${work_dir}/backup" -xf -
# Full restore replaces BoltDB, SQLite and all shards. KubeBlocks restores the
# source admin account secret when creating the destination cluster.
case "${INFLUX_BACKUP_MODE:-full}" in
  full) influx restore --full "${work_dir}/backup" ;;
  selective)
    backup_dir="${work_dir}/backup"
    catalog="$backup_dir/bucket-list"
    selection="$catalog"
    if [[ -n ${buckets:-} || ! -f $catalog ]]; then
      selection="${work_dir}/selection"
      write_bucket_selection "$selection"
    fi
    read_bucket_selection "$selection"
    if (( ${#bucket_names[@]} > 1 )) && [[ -n ${new_bucket:-} || ! -f $catalog ]]; then
      echo "A single-bucket archive or new_bucket requires exactly one selected bucket" >&2
      exit 1
    fi

    # Check archive membership and duplicate destinations before creating buckets.
    mkdir "${work_dir}/destinations"
    restore_dirs=()
    for i in "${!bucket_names[@]}"; do
      restore_dir="$backup_dir"
      if [[ -f $catalog ]]; then
        key=$(bucket_key "${bucket_orgs[i]}" "${bucket_names[i]}")
        restore_dir="$backup_dir/$key"
        if [[ ! -d $restore_dir ]]; then
          printf 'Bucket %q in organization %q is missing from the backup\n' "${bucket_names[i]}" "${bucket_orgs[i]}" >&2
          exit 1
        fi
      fi
      restore_dirs+=("$restore_dir")
      key=$(bucket_key "${new_org:-${bucket_orgs[i]}}" "${new_bucket:-${bucket_names[i]}}")
      if [[ -e ${work_dir}/destinations/$key ]]; then
        echo "Multiple selected buckets resolve to the same destination" >&2
        exit 1
      fi
      touch "${work_dir}/destinations/$key"
    done

    for i in "${!bucket_names[@]}"; do
      args=(--org "${bucket_orgs[i]}" --bucket "${bucket_names[i]}")
      if [[ -n ${new_bucket:-} ]]; then args+=(--new-bucket "$new_bucket"); fi
      if [[ -n ${new_org:-} ]]; then args+=(--new-org "$new_org"); fi
      # Never use --full for a bucket backup: destination credentials stay intact.
      influx restore "${args[@]}" "${restore_dirs[i]}"
    done
    ;;
  *) echo "Unknown backup mode" >&2; exit 1 ;;
esac
