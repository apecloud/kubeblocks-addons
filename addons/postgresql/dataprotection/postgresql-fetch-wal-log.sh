#!/bin/bash
function get_wal_name() {
    local fileName=$1
    local file_without_ext=${fileName%.*}
    echo $(basename $file_without_ext)
}

function fetch-wal-log(){
    wal_destination_dir=$1
    start_wal_name=$2
    restore_time=`date -d "$3" +%s`
    pitr=$4
    DP_log "PITR: $pitr"

    exit_fetch_wal=0 && mkdir -p $wal_destination_dir
    if ! dir_names=$(datasafed list /); then
       DP_error_log "failed to list the WAL archive root"
       return 1
    fi
    for dir_name in $dir_names ; do
      if [[ $exit_fetch_wal -eq 1 ]]; then
         break
      fi

      if ! dir_files=$(datasafed list "${dir_name}"); then
         DP_error_log "failed to list WAL archive directory ${dir_name}"
         return 1
      fi
      # check if the latest_wal_log after the start_wal_log
      latest_wal=$(printf '%s\n' "${dir_files}" | tail -n 1)
      latest_wal_name=$(get_wal_name ${latest_wal})
      if [[ ${latest_wal_name} < $start_wal_name ]]; then
         continue
      fi

      DP_log "start to fetch wal logs from ${dir_name}"
      for file in $(printf '%s\n' "${dir_files}" | grep ".zst"); do
         wal_name=$(get_wal_name ${file})
         if [[ $wal_name < $start_wal_name ]]; then
            continue
         fi
         if [[ $pitr != "true" && $file =~ ".history"  ]]; then
            # if not restored for pitr, only fetch the current timeline log
            DP_log "exit for new timeline."
            exit_fetch_wal=1
            break
         fi
         DP_log "copying $wal_name"
         # pull and decompress
         datasafed pull -d zstd $file ${wal_destination_dir}/$wal_name

         # check if the wal_log contains the restore_time logs. if ture, stop fetching
         latest_commit_time=$(pg_waldump ${wal_destination_dir}/$wal_name --rmgr=Transaction 2>/dev/null |tail -n 1|awk -F ' COMMIT ' '{print $2}'|awk -F ';' '{print $1}')
         if [[ -z $latest_commit_time ]]; then
            continue
         fi
         timestamp=`date -d "$latest_commit_time" +%s`
         if [[ $latest_commit_time != "" && $timestamp -gt $restore_time ]]; then
            DP_log "exit when reaching the target time log."
            exit_fetch_wal=1
            break
         fi
      done
    done
}
