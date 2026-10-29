#!/bin/bash
function get_wal_name() {
    local fileName=$1
    local file_without_ext=${fileName%.*}
    basename "$file_without_ext"
}

function fetch-wal-log(){
    local wal_destination_dir=$1
    local start_wal_name=$2
    local restore_time
    if ! restore_time=$(date -d "$3" +%s); then
       DP_error_log "failed to parse PITR restore time $3"
       return 1
    fi
    local pitr=$4
    DP_log "PITR: $pitr"

    if ! mkdir -p "$wal_destination_dir"; then
       DP_error_log "failed to create WAL destination ${wal_destination_dir}"
       return 1
    fi
    local dir_names dir_name dir_files file wal_name archive_files=
    if ! dir_names=$(datasafed list /); then
       DP_error_log "failed to list the WAL archive root"
       return 1
    fi
    # Date directories describe upload time, not WAL order: reconciliation
    # can put an older segment in a later directory. Index every directory
    # before using a commit timestamp to stop fetching any timeline.
    for dir_name in $dir_names; do
       [[ ${dir_name} == */ ]] || continue
       if ! dir_files=$(datasafed list "${dir_name}"); then
          DP_error_log "failed to list WAL archive directory ${dir_name}"
          return 1
       fi
       for file in $dir_files; do
          [[ ${file} == *.zst ]] || continue
          wal_name=$(get_wal_name "$file")
          if [[ $wal_name =~ ^[0-9A-F]{24}$ || $wal_name =~ ^[0-9A-F]{8}\.history$ ]]; then
             archive_files+="${wal_name}"$'\t'"${file}"$'\n'
          fi
       done
    done
    if ! archive_files=$(printf '%s' "${archive_files}" | LC_ALL=C sort -k1,1 -k2,2); then
       DP_error_log "failed to sort the WAL archive index"
       return 1
    fi

    # Fetch history independently of WAL cutoffs. PostgreSQL uses these files
    # to follow timeline ancestry; a later upload date must not hide them.
    local previous_name=
    if [[ ${pitr} == true ]]; then
       while IFS=$'\t' read -r wal_name file; do
          [[ ${wal_name} == *.history && ${wal_name} != "${previous_name}" ]] || continue
          if ! datasafed pull -d zstd "$file" "${wal_destination_dir}/${wal_name}"; then
             DP_error_log "failed to pull WAL archive ${file}"
             return 1
          fi
          previous_name=${wal_name}
       done <<< "${archive_files}"
    fi

    local start_timeline=${start_wal_name:0:8}
    local completed_timeline='' timeline wal_dump latest_commit_time timestamp
    previous_name=
    while IFS=$'\t' read -r wal_name file; do
       [[ ${wal_name} =~ ^[0-9A-F]{24}$ ]] || continue
       [[ ${wal_name} != "${previous_name}" ]] || continue
       previous_name=${wal_name}
       [[ ${wal_name} < ${start_wal_name} ]] && continue
       timeline=${wal_name:0:8}
       if [[ ${pitr} != true && ${timeline} != "${start_timeline}" ]]; then
          continue
       fi
       [[ ${timeline} == "${completed_timeline}" ]] && continue
       DP_log "copying $wal_name"
       if ! datasafed pull -d zstd "$file" "${wal_destination_dir}/${wal_name}"; then
          DP_error_log "failed to pull WAL archive ${file}"
          return 1
       fi
       if ! wal_dump=$(pg_waldump "${wal_destination_dir}/${wal_name}" --rmgr=Transaction 2>/dev/null); then
          DP_error_log "failed to inspect WAL ${wal_name}"
          return 1
       fi
       latest_commit_time=$(printf '%s\n' "${wal_dump}" | tail -n 1 | awk -F ' COMMIT ' '{print $2}' | awk -F ';' '{print $1}')
       [[ -n ${latest_commit_time} ]] || continue
       if ! timestamp=$(date -d "$latest_commit_time" +%s); then
          DP_error_log "failed to parse commit time for WAL ${wal_name}: ${latest_commit_time}"
          return 1
       fi
       if [[ ${timestamp} -gt ${restore_time} ]]; then
          DP_log "reached the target time on timeline ${timeline}"
          # Other timelines may contain the required continuation after a
          # promotion. Let PostgreSQL select its ancestry from the history.
          completed_timeline=${timeline}
       fi
    done <<< "${archive_files}"
    return 0
}
