#!/bin/sh

set -eu

rustfs_backup_on_exit() {
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    echo "ERROR: RustFS backup failed with exit code ${rc}" >&2
    if [ -n "${DP_BACKUP_INFO_FILE:-}" ]; then
      : > "${DP_BACKUP_INFO_FILE}.exit"
    fi
    exit "${rc}"
  fi
}
trap rustfs_backup_on_exit EXIT

rustfs_prepare_datasafed
rustfs_prepare_mc

backup_prefix="$(rustfs_archive_name)"
work_dir="${TMPDIR:-/tmp}/rustfs-backup"
objects_dir="${work_dir}/objects"
rm -rf "${work_dir}"
mkdir -p "${objects_dir}"

echo "INFO: Listing RustFS buckets from ${RUSTFS_ENDPOINT}"
rustfs_mc ls "${RUSTFS_ALIAS}/" > "${work_dir}/buckets.raw"
: > "${work_dir}/buckets.txt"
while IFS= read -r line; do
  bucket_entry=""
  for field in ${line}; do
    bucket_entry="${field}"
  done
  [ -n "${bucket_entry}" ] || continue
  bucket_name="${bucket_entry%/}"
  [ -n "${bucket_name}" ] || continue
  printf '%s\n' "${bucket_name}" >> "${work_dir}/buckets.txt"
done < "${work_dir}/buckets.raw"

rustfs_mc find "${RUSTFS_ALIAS}/" --name "*" > "${work_dir}/objects.txt" || true

if [ -s "${work_dir}/buckets.txt" ]; then
  echo "INFO: Mirroring RustFS buckets to local staging directory"
  rustfs_mc mirror --overwrite "${RUSTFS_ALIAS}/" "${objects_dir}"
else
  echo "INFO: RustFS has no buckets; creating empty logical backup"
fi

echo "INFO: Pushing RustFS logical backup ${backup_prefix}"
datasafed push "${work_dir}/buckets.txt" "${backup_prefix}/buckets.txt"
datasafed push "${work_dir}/objects.txt" "${backup_prefix}/objects.txt"

object_count=0
: > "${work_dir}/expected-objects.txt"
rustfs_mc find "${objects_dir}" --name "*" > "${work_dir}/local-files.txt" || true
while IFS= read -r local_file; do
  [ -f "${local_file}" ] || continue
  relative_path="${local_file#"${objects_dir}"/}"
  [ -n "${relative_path}" ] || continue
  object_count=$((object_count + 1))
  printf '%s\n' "${relative_path}" >> "${work_dir}/expected-objects.txt"
  datasafed push "${local_file}" "${backup_prefix}/objects/${relative_path}"
done < "${work_dir}/local-files.txt"

bucket_count="$(rustfs_count_lines "${work_dir}/buckets.txt")"
manifest="${work_dir}/manifest.txt"
{
  printf 'formatVersion=%s\n' "${RUSTFS_BACKUP_FORMAT_VERSION:-rustfs-s3-full.v1}"
  printf 'method=s3-full\n'
  printf 'backupName=%s\n' "${DP_BACKUP_NAME}"
  printf 'endpointScheme=%s\n' "${RUSTFS_SCHEME_EFFECTIVE:-unknown}"
  printf 'toolImage=%s\n' "${RUSTFS_MC_IMAGE:-unknown}"
  printf 'bucketCount=%s\n' "${bucket_count}"
  printf 'objectCount=%s\n' "${object_count}"
  while IFS= read -r bucket; do
    [ -n "${bucket}" ] || continue
    printf 'bucket:%s\n' "${bucket}"
  done < "${work_dir}/buckets.txt"
  while IFS= read -r object; do
    [ -n "${object}" ] || continue
    printf 'object:%s\n' "${object}"
  done < "${work_dir}/expected-objects.txt"
} > "${manifest}"
datasafed push "${manifest}" "${backup_prefix}/manifest.txt"

rustfs_save_backup_size
echo "INFO: RustFS logical backup ${backup_prefix} completed"
