#!/bin/sh

set -eu

rustfs_prepare_datasafed
rustfs_prepare_mc

backup_prefix="$(rustfs_archive_name)"
work_dir="${TMPDIR:-/tmp}/rustfs-restore"
objects_dir="${work_dir}/objects"
rm -rf "${work_dir}"
mkdir -p "${work_dir}"

if [ "$(datasafed list "${backup_prefix}/manifest.txt" 2>/dev/null || true)" != "${backup_prefix}/manifest.txt" ]; then
  rustfs_fail "backup manifest ${backup_prefix}/manifest.txt not found"
fi

echo "INFO: Pulling RustFS logical backup ${backup_prefix}"
datasafed pull "${backup_prefix}/manifest.txt" "${work_dir}/manifest.txt"

manifest_format=""
manifest_method=""
manifest_bucket_count=""
manifest_object_count=""
: > "${work_dir}/buckets.txt"
: > "${work_dir}/expected-objects.txt"

while IFS= read -r line; do
  case "${line}" in
    formatVersion=*) manifest_format="${line#formatVersion=}" ;;
    method=*) manifest_method="${line#method=}" ;;
    bucketCount=*) manifest_bucket_count="${line#bucketCount=}" ;;
    objectCount=*) manifest_object_count="${line#objectCount=}" ;;
    bucket:*) printf '%s\n' "${line#bucket:}" >> "${work_dir}/buckets.txt" ;;
    object:*) printf '%s\n' "${line#object:}" >> "${work_dir}/expected-objects.txt" ;;
  esac
done < "${work_dir}/manifest.txt"

[ "${manifest_format}" = "${RUSTFS_BACKUP_FORMAT_VERSION:-rustfs-s3-full.v1}" ] || \
  rustfs_fail "backup manifest formatVersion ${manifest_format:-<empty>} is unsupported"
[ "${manifest_method}" = "s3-full" ] || \
  rustfs_fail "backup manifest method ${manifest_method:-<empty>} is unsupported"

bucket_count="$(rustfs_count_lines "${work_dir}/buckets.txt")"
object_count="$(rustfs_count_lines "${work_dir}/expected-objects.txt")"
[ "${manifest_bucket_count}" = "${bucket_count}" ] || \
  rustfs_fail "backup manifest bucket count ${manifest_bucket_count:-<empty>} does not match list count ${bucket_count}"
[ "${manifest_object_count}" = "${object_count}" ] || \
  rustfs_fail "backup manifest object count ${manifest_object_count:-<empty>} does not match list count ${object_count}"

if [ ! -s "${work_dir}/buckets.txt" ]; then
  [ "${manifest_object_count}" = "0" ] || \
    rustfs_fail "backup manifest has objects but no buckets"
  echo "INFO: Backup contains no buckets; restore is complete"
  exit 0
fi

mkdir -p "${objects_dir}"
pulled_count=0
while IFS= read -r relative_path; do
  [ -n "${relative_path}" ] || continue
  remote_object="${backup_prefix}/objects/${relative_path}"
  if [ "$(datasafed list "${remote_object}" 2>/dev/null || true)" != "${remote_object}" ]; then
    rustfs_fail "backup object artifact ${remote_object} not found"
  fi
  local_file="${objects_dir}/${relative_path}"
  mkdir -p "$(dirname "${local_file}")"
  datasafed pull "${remote_object}" "${local_file}"
  pulled_count=$((pulled_count + 1))
done < "${work_dir}/expected-objects.txt"

[ "${pulled_count}" = "${manifest_object_count}" ] || \
  rustfs_fail "pulled object count ${pulled_count} does not match manifest object count ${manifest_object_count}"

echo "INFO: Restoring RustFS buckets to ${RUSTFS_ENDPOINT}"
while IFS= read -r bucket; do
  [ -n "${bucket}" ] || continue
  rustfs_mc mb --ignore-existing "${RUSTFS_ALIAS}/${bucket}"
done < "${work_dir}/buckets.txt"

rustfs_mc find "${objects_dir}" --name "*" > "${work_dir}/local-objects.txt" || true
if [ -s "${work_dir}/local-objects.txt" ]; then
  rustfs_mc mirror --overwrite "${objects_dir}" "${RUSTFS_ALIAS}/"
fi

echo "INFO: RustFS restore from ${backup_prefix} completed"
