# shellcheck shell=bash

: "${DP_BACKUP_INFO_FILE:?}"
# No bucket filter: preserve every organization, bucket, user and token.
influx backup "${work_dir}/backup"
# influx already compresses shard files. Stream the archive to the repository.
tar -C "${work_dir}/backup" -cf - . | datasafed push - influxdb-full.tar
# Publish completion only after the upload and remote size lookup succeed.
total_size=$(datasafed stat / | awk '$1 == "TotalSize:" {print $2}')
[[ "$total_size" =~ ^[0-9]+$ ]] || { echo "Invalid backup size" >&2; exit 1; }
printf '{"totalSize":"%s"}' "$total_size" > "${DP_BACKUP_INFO_FILE}"
