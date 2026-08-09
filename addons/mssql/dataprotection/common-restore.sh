# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

DP_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} INFO: $msg"
}

function load_datasafed_paths() {
   local output_file
   DP_DATASAFED_PATHS=()
   output_file=$(mktemp) || return 1
   if ! (
     set -o pipefail
     datasafed list "$@" -o json | perl -MJSON::PP -MEncode=encode,FB_CROAK -e '
       my $parser = JSON::PP->new->utf8;
       sub emit_rows {
         my ($value) = @_;
         my $rows = ref($value) eq "ARRAY" ? $value : [$value];
         for my $row (@$rows) {
           die "datasafed JSON row has no scalar path\n"
             unless ref($row) eq "HASH" && defined($row->{path}) && !ref($row->{path});
           print encode("UTF-8", $row->{path}, FB_CROAK), "\0";
         }
       }
       while (read(STDIN, my $chunk, 8192)) {
         my $rows = $parser->incr_parse($chunk);
         while (defined($rows)) {
           emit_rows($rows);
           $rows = $parser->incr_parse;
         }
       }
       my $tail = $parser->incr_text;
       die "incomplete datasafed JSON document\n" if $tail =~ /\S/;
     '
   ) > "$output_file"; then
     rm -f "$output_file"
     return 1
   fi

   local path
   while IFS= read -r -d '' path; do
     DP_DATASAFED_PATHS+=("$path")
   done < "$output_file"
   rm -f "$output_file"
}

function load_local_files() {
   local root=${1:?'local file root is required'} output_file file
   DP_LOCAL_FILES=()
   output_file=$(mktemp) || return 1
   if ! find "$root" -type f -print0 > "$output_file"; then
     rm -f "$output_file"
     return 1
   fi
   while IFS= read -r -d '' file; do
     DP_LOCAL_FILES+=("$file")
   done < "$output_file"
   rm -f "$output_file"
}

function append_chain_entry() {
   local chain_file=${1:?'chain file is required'} entry=${2:?'chain entry is required'}
   printf '%s\0' "$entry" >> "$chain_file"
}

function prepend_chain_entry() {
   local chain_file=${1:?'chain file is required'} entry=${2:?'chain entry is required'} temp_file
   [ -f "$chain_file" ] || return 0
   temp_file=$(mktemp "${chain_file}.XXXXXX") || return 1
   if ! printf '%s\0' "$entry" > "$temp_file" || ! cat "$chain_file" >> "$temp_file"; then
     rm -f "$temp_file"
     return 1
   fi
   if ! mv "$temp_file" "$chain_file"; then
     rm -f "$temp_file"
     return 1
   fi
}

function download_backups() {
   local backup_name=$1
   local target_path=${BACKUP_DIR}/INIT_BACKUPS/${backup_name}
   mkdir -p "${target_path}"
   load_datasafed_paths / -r -f || return 1
   local file file_name
   for file in "${DP_DATASAFED_PATHS[@]}"; do
     case "$file" in
       *.json|*.pfx|*.cer|*.pvk|*.password) continue ;;
     esac
     file_name=${file#/}
     file_name=${file_name%.zst}
     echo "download ${file} to ${target_path}"
     if [[ "${file_name}" == *".sql" ]]; then
        datasafed pull "${file}" "${target_path}/${file_name}"
     else
        datasafed pull -d zstd-fastest "${file}" "${target_path}/${file_name}"
     fi
   done
}

function download_certificates() {
   local cert_path=${BACKUP_DIR}/INIT_BACKUPS/certificates
   mkdir -p "${cert_path}"
   load_datasafed_paths / -f || return 1
   local file file_name
   for file in "${DP_DATASAFED_PATHS[@]}"; do
     case "$file" in
       *.pfx|*.cer|*.pvk|*.password) ;;
       *) continue ;;
     esac
     file_name=${file#/}
     DP_log "download certificate file: ${file} to ${cert_path}"
     datasafed pull "${file}" "${cert_path}/${file_name}"
   done
}
