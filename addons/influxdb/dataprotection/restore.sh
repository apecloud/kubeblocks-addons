# shellcheck shell=bash

mkdir "${work_dir}/backup"
datasafed pull influxdb-full.tar - | tar -C "${work_dir}/backup" -xf -
# Full restore replaces BoltDB, SQLite and all shards. KubeBlocks restores the
# source admin account secret when creating the destination cluster.
case "${INFLUX_BACKUP_MODE:-full}" in
  full) influx restore --full "${work_dir}/backup" ;;
  selective)
    [[ -n ${org:-} ]] || { echo "A source organization name is required" >&2; exit 1; }
    [[ -n ${bucket:-} ]] || { echo "A source bucket name is required" >&2; exit 1; }
    args=(--org "$org" --bucket "$bucket")
    if [[ -n ${new_bucket:-} ]]; then args+=(--new-bucket "$new_bucket"); fi
    if [[ -n ${new_org:-} ]]; then args+=(--new-org "$new_org"); fi
    # Never use --full for a bucket backup: destination credentials stay intact.
    influx restore "${args[@]}" "${work_dir}/backup"
    ;;
  *) echo "Unknown backup mode" >&2; exit 1 ;;
esac
