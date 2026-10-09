#!/bin/sh

set -eu

rustfs_prepare_datasafed
rustfs_prepare_mc

backup_prefix="$(rustfs_archive_name)"
work_dir="${TMPDIR:-/tmp}/rustfs-restore"
objects_dir="${work_dir}/objects"
rm -rf "${work_dir}"
mkdir -p "${work_dir}"

rustfs_require_datasafed_object "${backup_prefix}/manifest.txt"

echo "INFO: Pulling RustFS logical backup ${backup_prefix}"
datasafed pull "${backup_prefix}/manifest.txt" "${work_dir}/manifest.txt"

manifest_format=""
manifest_method=""
manifest_bucket_count=""
manifest_object_count=""
manifest_format_fields=0
manifest_method_fields=0
manifest_bucket_count_fields=0
manifest_object_count_fields=0
: > "${work_dir}/buckets.txt"
: > "${work_dir}/expected-objects.txt"

while IFS= read -r line; do
  case "${line}" in
    formatVersion=*)
      manifest_format_fields=$((manifest_format_fields + 1))
      manifest_format="${line#formatVersion=}" ;;
    method=*)
      manifest_method_fields=$((manifest_method_fields + 1))
      manifest_method="${line#method=}" ;;
    bucketCount=*)
      manifest_bucket_count_fields=$((manifest_bucket_count_fields + 1))
      manifest_bucket_count="${line#bucketCount=}" ;;
    objectCount=*)
      manifest_object_count_fields=$((manifest_object_count_fields + 1))
      manifest_object_count="${line#objectCount=}" ;;
    bucket:*)
      manifest_bucket="${line#bucket:}"
      [ -n "${manifest_bucket}" ] || \
        rustfs_fail "backup manifest contains an empty bucket name"
      rustfs_validate_bucket_name "${manifest_bucket}"
      if rustfs_file_contains_exact_line "${manifest_bucket}" "${work_dir}/buckets.txt"; then
        rustfs_fail "backup manifest contains duplicate bucket ${manifest_bucket}"
      fi
      printf '%s\n' "${manifest_bucket}" >> "${work_dir}/buckets.txt" ;;
    object:*)
      manifest_object="${line#object:}"
      [ -n "${manifest_object}" ] || \
        rustfs_fail "backup manifest contains an empty object path"
      rustfs_validate_relative_artifact_path "${manifest_object}"
      case "${manifest_object}" in
        */?*) ;;
        *) rustfs_fail "backup manifest contains invalid object path ${manifest_object}" ;;
      esac
      if rustfs_file_contains_exact_line "${manifest_object}" "${work_dir}/expected-objects.txt"; then
        rustfs_fail "backup manifest contains duplicate object ${manifest_object}"
      fi
      printf '%s\n' "${manifest_object}" >> "${work_dir}/expected-objects.txt" ;;
    backupName=*|endpointScheme=*|toolImage=*) ;;
    *) rustfs_fail "backup manifest contains an unrecognized entry" ;;
  esac
done < "${work_dir}/manifest.txt"

[ "${manifest_format_fields}" = "1" ] || \
  rustfs_fail "backup manifest must contain formatVersion exactly once"
[ "${manifest_method_fields}" = "1" ] || \
  rustfs_fail "backup manifest must contain method exactly once"
[ "${manifest_bucket_count_fields}" = "1" ] || \
  rustfs_fail "backup manifest must contain bucketCount exactly once"
[ "${manifest_object_count_fields}" = "1" ] || \
  rustfs_fail "backup manifest must contain objectCount exactly once"
[ "${manifest_format}" = "${RUSTFS_BACKUP_FORMAT_VERSION:-rustfs-s3-full.v1}" ] || \
  rustfs_fail "backup manifest formatVersion ${manifest_format:-<empty>} is unsupported"
[ "${manifest_method}" = "s3-full" ] || \
  rustfs_fail "backup manifest method ${manifest_method:-<empty>} is unsupported"
rustfs_validate_nonnegative_integer bucketCount "${manifest_bucket_count}"
rustfs_validate_nonnegative_integer objectCount "${manifest_object_count}"

bucket_count="$(rustfs_count_lines "${work_dir}/buckets.txt")"
object_count="$(rustfs_count_lines "${work_dir}/expected-objects.txt")"
[ "${manifest_bucket_count}" = "${bucket_count}" ] || \
  rustfs_fail "backup manifest bucket count ${manifest_bucket_count:-<empty>} does not match list count ${bucket_count}"
[ "${manifest_object_count}" = "${object_count}" ] || \
  rustfs_fail "backup manifest object count ${manifest_object_count:-<empty>} does not match list count ${object_count}"

while IFS= read -r relative_path; do
  [ -n "${relative_path}" ] || continue
  object_bucket="${relative_path%%/*}"
  rustfs_file_contains_exact_line "${object_bucket}" "${work_dir}/buckets.txt" || \
    rustfs_fail "backup object ${relative_path} does not belong to a declared bucket"
done < "${work_dir}/expected-objects.txt"

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
  rustfs_validate_relative_artifact_path "${relative_path}"
  remote_object="${backup_prefix}/objects/${relative_path}"
  rustfs_require_datasafed_object "${remote_object}"
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

rustfs_mc find "${objects_dir}" --name "*" > "${work_dir}/local-objects.txt"
if [ -s "${work_dir}/local-objects.txt" ]; then
  rustfs_mc mirror --overwrite "${objects_dir}" "${RUSTFS_ALIAS}/"
fi

echo "INFO: RustFS restore from ${backup_prefix} completed"
