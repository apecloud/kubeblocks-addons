# shellcheck disable=SC2148
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

connect_url="redis-cli -h ${DP_DB_HOST} -p ${DP_DB_PORT} -a ${DP_DB_PASSWORD}"
global_last_purge_time=$(date +%s)
global_aof_last_modify_time=0
global_acl_last_modify_time=0
global_old_size=0

AOF_DIR=$(${connect_url} CONFIG GET appenddirname | awk 'NR==2')
APPEND_FILE_NAME=$(${connect_url} CONFIG GET appendfilename | awk 'NR==2')
AOF_FILE_PREFIX="${DATA_DIR}/${AOF_DIR}/${APPEND_FILE_NAME}"
BASE_FILE_SUFFIX="base.$([ "$($connect_url CONFIG GET aof-use-rdb-preamble | awk 'NR==2')" == "no" ] && echo "aof" || echo "rdb")"
AOF_MANIFEST_FILE="${AOF_FILE_PREFIX}.manifest"

mkdir -p "${AOF_DIR}"

function get_base_file_ctime() {
  local base_file=${1}
  if [ "$BASE_FILE_SUFFIX" = "base.rdb" ]; then
    # use the creation time of the base file as the start time
    echo $(redis-check-rdb "$base_file" | grep 'ctime' | awk -F"'" '{print $2}')
    return
  fi

  # for aof base file
  # extract the timestamp from the first line of base_file
  timestamp=$(head -n 1 "$base_file" | grep -oP '(?<=#TS:)\d+')

  # ff no timestamp is found, get the file creation time
  if [ -z "$timestamp" ]; then
    timestamp=$(stat -c %W "$base_file")
  fi
  echo "$timestamp"
}

function aof_incr_file() {
  local seq=$1
  # absolute path
  echo "${AOF_FILE_PREFIX}.${seq}.incr.aof"
}

function aof_base_file() {
  local seq=$1
  # absolute path
  echo "${AOF_FILE_PREFIX}.${seq}.${BASE_FILE_SUFFIX}"
}

function get_backup_seq() {
  local remote_aof_dir=$(datasafed list -d / | sort -Vr | head -n 1)
  local remote_aof_seq=$(echo "$remote_aof_dir" | awk -F '.' '{print $2}')
  if [[ -z "$remote_aof_seq" ]] || ! [[ "$remote_aof_seq" =~ ^[0-9]+$ ]]; then
    echo 1
    return
  fi

  local remote_base_file_ctime=$(echo "$remote_aof_dir" | awk -F '.' '{print $1}')
  local local_aof_seq=$(awk '/type i/ { print $4 }' "${AOF_MANIFEST_FILE}")
  local local_base_file_ctime=$(get_base_file_ctime "$(aof_base_file "$local_aof_seq")")

  if [ "$remote_base_file_ctime" -gt "$local_base_file_ctime" ] ||
   { [ "$remote_base_file_ctime" -eq "$local_base_file_ctime" ] && [ "$remote_aof_seq" -gt "$local_aof_seq" ]; }; then
    # in replication mode, when failover happens, if the backup process switch to a new target, we should
    # call BGREWRITEAOF to make sure record from a new start time, which guarantees the consistency of data and continuity of time.
    ${connect_url} BGREWRITEAOF  >/dev/null 2>&1
  fi

  [ "$local_aof_seq" -lt "$remote_aof_seq" ] && echo "$local_aof_seq" || echo "$remote_aof_seq"
}

global_backup_seq=$(get_backup_seq)

function get_backup_files_prefix() {
  local base_file=${1}
  echo "$(get_base_file_ctime "$base_file")"."$global_backup_seq"
}

# generate backup manifest file for remote backup
function generate_backup_manifest() {
  local backup_manifest="$APPEND_FILE_NAME.manifest"
  local backup_incr_file=$(basename "$(aof_incr_file "$global_backup_seq")")
  local backup_base_file=$(basename "$(aof_base_file "$global_backup_seq")")

  echo "file $backup_incr_file seq $global_backup_seq type i" >"$AOF_DIR/$backup_manifest"
  echo "file $backup_base_file seq $global_backup_seq type b" >>"$AOF_DIR/$backup_manifest"
  echo ""${AOF_DIR}"/${backup_manifest}"
}

# archive aof and rdb file after aof rewrite
function archive_pair_files() {
  local incr_file=$(aof_incr_file "$global_backup_seq")
  local base_file=$(aof_base_file "$global_backup_seq")
  local backup_files_prefix=$(get_backup_files_prefix $base_file)
  local backup_manifest="$APPEND_FILE_NAME.manifest"

  if [ ! -f "$incr_file" ] || [ ! -f "$base_file" ]; then
    DP_log "archive_pair_files: $incr_file or $base_file do not exist"
    return
  fi

  local target_file="${backup_files_prefix}.tar.zst"
  # backup files include manifest file, incr file, base file, users.acl
  # and we retains the original directory hierarchy, which makes the recovery process simpler
  tar -cvf - "$(generate_backup_manifest)" -C "${DATA_DIR}" \
    "${AOF_DIR}/$(basename "${incr_file}")" "${AOF_DIR}/$(basename "${base_file}")" \
    "users.acl" | datasafed push -z zstd - "${target_file}"

  # delete remote and local uncompressed files we are tracking.
  datasafed rm -r "${backup_files_prefix}.dir"
  rm "${incr_file}" "${base_file}"

  DP_log "Archived files: ${incr_file} and ${base_file} to $target_file"
}

function update_aof_file() {
  local incr_file=$(aof_incr_file "$global_backup_seq")
  local base_file=$(aof_base_file "$global_backup_seq")
  local backup_files_prefix=$(get_backup_files_prefix $base_file)
  local backup_manifest="$(generate_backup_manifest)"

  if [ ! -f "$incr_file" ] || [ ! -f "$base_file" ]; then
    DP_log "update_aof_file: $incr_file or $base_file do not exist"
    return
  fi

  # create a directory for backup files we are tracking, and after a aof rewrite, we will archive them in to a tar.zst file
  if [ $(get_base_file_ctime "$base_file") -gt ${global_aof_last_modify_time} ]; then
    datasafed push "${base_file}" "${backup_files_prefix}.dir/${AOF_DIR}/$(basename "${base_file}")"
    datasafed push "${backup_manifest}" "${backup_files_prefix}.dir/${backup_manifest}"
    datasafed push "${DATA_DIR}/users.acl" "${backup_files_prefix}.dir/users.acl"
    DP_log "Upload file: $base_file $backup_manifest users.acl"
  fi

  # keep updating the latest aof file
  local aof_modify_time=$(stat -c %Y "${incr_file}")
  if [ "${aof_modify_time}" -gt "${global_aof_last_modify_time}" ]; then
    datasafed push "${incr_file}" "${backup_files_prefix}.dir/${AOF_DIR}/$(basename "${incr_file}")"
    global_aof_last_modify_time=${aof_modify_time}
    DP_log "Update file: $incr_file"
  fi

  # keep updating the latest acl file
  local acl_file="${DATA_DIR}/users.acl"
  local acl_modify_time=$(stat -c %Y "${acl_file}")
  if [ "${acl_modify_time}" -gt "${global_acl_last_modify_time}" ]; then
    datasafed push "${acl_file}"  "${backup_files_prefix}.dir/users.acl"
    global_acl_last_modify_time=${acl_modify_time}
    DP_log "Update file: $acl_file"
  fi
}

function purge_expired_files() {
  local current_unix=$(date +%s)
  info=$(DP_purge_expired_files ${current_unix} ${global_last_purge_time} / 600)
  if [ ! -z "${info}" ]; then
    global_last_purge_time=${currentUnix}
    DP_log "Cleanup expired aof files: ${info}"
    local total_size=$(datasafed stat / | grep TotalSize | awk '{print $2}')
    DP_save_backup_status_info "${total_size}"
  fi
}

function save_backup_status() {
  # if no size changes, return
  local total_size=$(datasafed stat / | grep TotalSize | awk '{print $2}')
  if [[ -z ${total_size} || ${total_size} -eq 0 || ${total_size} == ${global_old_size} ]]; then
    return
  fi
  global_old_size=${total_size}
  local start_time=$(datasafed list / | awk -F '.' '{print $1}' | sort | head -n 1)
  if [ -z "$start_time" ]; then
    start_time=$(date +%s)
    DP_log "save_backup_status: empty start_time from backup repo, use current time"
  fi
  DP_save_backup_status_info "${total_size}" "${start_time}" "$(date +%s)"
}

function check_conf() {
  aof_timestamp_enabled=$(${connect_url} CONFIG GET aof-timestamp-enabled 2>/dev/null | awk 'NR==2')
  if [ "$aof_timestamp_enabled" == "no" ]; then
    DP_error_log "aof-timestamp-enabled is not set to yes, set it to yes by 'kbcli cluster edit-config' or 'kbcli cluster configure'"
    ${connect_url} CONFIG SET aof-disable-auto-gc no
    exit 1
  fi

  disable_gc=$(${connect_url} CONFIG GET aof-disable-auto-gc 2>/dev/null | awk 'NR==2')
  if [ "$disable_gc" == "no" ]; then
    ${connect_url} CONFIG SET aof-disable-auto-gc yes
    DP_log "aof-disable-auto-gc set to yes"
  fi
}

# archived files named as ${base_file_ctime}.${seq}.suffix
# we use {base_file_ctime} to track files between different target pods in replication mode and used for restore
# every time a failover happens, we will choose to track the new one target pod with the latest {base_file_ctime}, keep
# time increasing, and use {seq} to track the selected one target pod`s incremental backup files

trap "echo 'Terminating...' && sync && ${connect_url} CONFIG SET aof-disable-auto-gc no && exit 0" TERM
echo "INFO: start to backup"
while true; do
  check_conf

  aof_seq=$(awk '/type i/ { print $4 }' "${AOF_MANIFEST_FILE}")
  while [ "${global_backup_seq}" -lt "${aof_seq}" ]; do
    archive_pair_files
    global_backup_seq=$((global_backup_seq + 1))
  done

  update_aof_file

  purge_expired_files

  save_backup_status

  sleep "${LOG_ARCHIVE_SECONDS}"
done
