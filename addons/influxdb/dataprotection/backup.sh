# shellcheck shell=bash

: "${DP_BACKUP_INFO_FILE:?}"
case "${INFLUX_BACKUP_MODE:-full}" in
  full) influx backup "${work_dir}/backup" ;;
  selective)
    parse_selection "${selection:-}" 1 || { echo "Invalid or empty InfluxDB bucket selection" >&2; exit 1; }
    backup_dir="${work_dir}/backup"
    mkdir -p "$backup_dir"

    # Resolve candidate (org, bucket) pairs
    declare -A seen_candidates=()
    candidate_pairs=()
    add_candidate() {
      local o="$1" b="$2"
      local k="${o}"$'\t'"${b}"
      if [[ -z "${seen_candidates[$k]:-}" ]]; then
        seen_candidates[$k]=1
        candidate_pairs+=("$k")
      fi
    }

    for i in "${!parents[@]}"; do
      org="${parents[i]}"
      child="${children[i]}"

      if [[ -z "$child" ]]; then
        if ! raw_bucket_list=$(influx bucket list --org "$org" --hide-headers); then
          printf 'Failed to look up organization %q\n' "$org" >&2
          exit 1
        fi
        bucket_list=$(printf '%s\n' "$raw_bucket_list" | cut -f2)
        found_bucket=0
        while IFS= read -r b; do
          [[ -n "$b" && "$b" != _* ]] || continue
          found_bucket=1
          add_candidate "$org" "$b"
        done <<< "$bucket_list"
        if [[ $found_bucket -eq 0 ]]; then
          printf 'No user buckets found in organization %q\n' "$org" >&2
          exit 1
        fi
      else
        add_candidate "$org" "$child"
      fi
    done

    # Backup each candidate bucket
    for pair in "${candidate_pairs[@]}"; do
      org="${pair%%$'\t'*}"
      bucket="${pair#*$'\t'}"
      org_path=$(encode_archive_name "$org")
      bucket_path=$(encode_archive_name "$bucket")
      archive_dir="$backup_dir/$org_path/$bucket_path"

      if ! influx bucket list --org "$org" --name "$bucket" >/dev/null; then
        printf 'Failed to look up bucket %q in organization %q\n' "$bucket" "$org" >&2
        exit 1
      fi
      mkdir -p "$backup_dir/$org_path"
      influx backup --org "$org" --bucket "$bucket" "$archive_dir"
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
