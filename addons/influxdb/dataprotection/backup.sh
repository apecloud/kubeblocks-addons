# shellcheck shell=bash

: "${DP_BACKUP_INFO_FILE:?}"
case "${INFLUX_BACKUP_MODE:-full}" in
  full) influx backup "${work_dir}/backup" ;;
  selective)
    backup_dir="${work_dir}/backup"
    selection="${work_dir}/selection"
    write_bucket_selection "$selection"
    read_bucket_selection "$selection"
    mkdir "$backup_dir"
    for i in "${!bucket_names[@]}"; do
      key=$(bucket_key "${bucket_orgs[i]}" "${bucket_names[i]}")
      if [[ ! -d "$backup_dir/$key" ]]; then
        influx backup --org "${bucket_orgs[i]}" --bucket "${bucket_names[i]}" "$backup_dir/$key"
        printf '%s\0%s\0' "${bucket_orgs[i]}" "${bucket_names[i]}" >> "$backup_dir/bucket-list"
      fi
    done
    ;;
  *) echo "Unknown backup mode" >&2; exit 1 ;;
esac
# influx already compresses shard files. Stream the archive to the repository.
tar -C "${work_dir}/backup" -cf - . | datasafed push - influxdb-full.tar
# Publish completion only after the upload and remote size lookup succeed.
total_size=$(datasafed stat / | awk '$1 == "TotalSize:" {print $2}')
[[ "$total_size" =~ ^[0-9]+$ ]] || { echo "Invalid backup size" >&2; exit 1; }
printf '{"totalSize":"%s"}' "$total_size" > "${DP_BACKUP_INFO_FILE}"
