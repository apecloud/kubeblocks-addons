# shellcheck shell=bash

: "${DP_BACKUP_INFO_FILE:?}"
case "${INFLUX_BACKUP_MODE:-full}" in
  full) influx backup "${work_dir}/backup" ;;
  selective)
    parse_selection "${selection:-}" 1 || { echo "Invalid or empty InfluxDB bucket selection" >&2; exit 1; }
    backup_dir="${work_dir}/backup"
    mkdir -p "$backup_dir/selected"

    # Identify whole-organization selections to avoid duplicate bucket backups
    whole_orgs=","
    for i in "${!parents[@]}"; do
      if [[ -z "${children[i]}" ]]; then
        org_path=$(encode_archive_name "${parents[i]}")
        whole_orgs="${whole_orgs}${org_path},"
      fi
    done

    backed_up=","
    for i in "${!parents[@]}"; do
      org_path=$(encode_archive_name "${parents[i]}")
      if [[ -n "${children[i]}" && "$whole_orgs" == *",${org_path},"* ]]; then
        continue
      fi

      if [[ -n "${children[i]}" ]]; then
        bucket_path=$(encode_archive_name "${children[i]}")
        key="${org_path}/${bucket_path}"
        if [[ "$backed_up" == *",${key},"* ]]; then
          continue
        fi
        archive_dir="$backup_dir/selected/$org_path/$bucket_path"
        if ! influx bucket list --org "${parents[i]}" --name "${children[i]}" >/dev/null; then
          printf 'Failed to look up bucket %q in organization %q\n' "${children[i]}" "${parents[i]}" >&2
          exit 1
        fi
        mkdir -p "$backup_dir/selected/$org_path"
        influx backup --org "${parents[i]}" --bucket "${children[i]}" "$archive_dir"
        backed_up="${backed_up}${key},"
      else
        key="${org_path}/_all"
        if [[ "$backed_up" == *",${key},"* ]]; then
          continue
        fi
        archive_dir="$backup_dir/selected/$org_path/_all"
        if ! influx bucket list --org "${parents[i]}" >/dev/null; then
          printf 'Failed to look up organization %q\n' "${parents[i]}" >&2
          exit 1
        fi
        mkdir -p "$backup_dir/selected/$org_path"
        influx backup --org "${parents[i]}" "$archive_dir"
        backed_up="${backed_up}${key},"
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
