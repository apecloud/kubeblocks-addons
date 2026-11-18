# shellcheck shell=bash

: "${DP_BACKUP_INFO_FILE:?}"
case "${INFLUX_BACKUP_MODE:-full}" in
  full) influx backup "${work_dir}/backup" ;;
  selective)
    [[ -n ${org:-} ]] || { echo "A source organization name is required" >&2; exit 1; }
    [[ -n ${bucket:-} ]] || { echo "A source bucket name is required" >&2; exit 1; }
    influx backup --org "$org" --bucket "$bucket" "${work_dir}/backup"
    ;;
  *) echo "Unknown backup mode" >&2; exit 1 ;;
esac
# influx already compresses shard files. Stream the archive to the repository.
tar -C "${work_dir}/backup" -cf - . | datasafed push - influxdb-full.tar
# Publish completion only after the upload and remote size lookup succeed.
total_size=$(datasafed stat / | awk '$1 == "TotalSize:" {print $2}')
[[ "$total_size" =~ ^[0-9]+$ ]] || { echo "Invalid backup size" >&2; exit 1; }
printf '{"totalSize":"%s"}' "$total_size" > "${DP_BACKUP_INFO_FILE}"
