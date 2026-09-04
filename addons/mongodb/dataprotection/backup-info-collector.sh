# shellcheck disable=SC2148
function get_current_time() {
  local client curr_time status

  if command -v mongosh >/dev/null 2>&1; then
    client="mongosh"
  elif command -v mongo >/dev/null 2>&1; then
    client="mongo"
  else
    printf 'backup info timestamp client unavailable rc=127\n' >&2
    return 127
  fi

  if curr_time=$(
    "$client" \
      -u "$DP_DB_USER" \
      -p "$DP_DB_PASSWORD" \
      --port "$DP_DB_PORT" \
      --host "$DP_DB_HOST" \
      --authenticationDatabase admin \
      --eval 'db.isMaster().lastWrite.lastWriteDate.getTime()/1000' \
      --quiet
  ); then
    :
  else
    status=$?
    printf 'backup info timestamp client failed rc=%s\n' "$status" >&2
    return "$status"
  fi

  if [ -z "$curr_time" ]; then
    printf 'backup info timestamp client returned empty output rc=65\n' >&2
    return 65
  fi

  if curr_time=$(date -d "@${curr_time}" -u '+%Y-%m-%dT%H:%M:%SZ'); then
    :
  else
    status=$?
    printf 'backup info timestamp conversion failed rc=%s\n' "$status" >&2
    return "$status"
  fi

  if [ -z "$curr_time" ]; then
    printf 'backup info timestamp conversion returned empty output rc=65\n' >&2
    return 65
  fi

  printf '%s\n' "$curr_time"
}

function stat_and_save_backup_info() {
  local start_time stop_time stat_output status total_size tmp_file

  export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
  export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

  start_time=${1:-}
  stop_time=${2:-}
  if [ -z "$stop_time" ]; then
    if stop_time=$(get_current_time); then
      :
    else
      status=$?
      printf 'backup info stop timestamp failed rc=%s\n' "$status" >&2
      return "$status"
    fi
  fi

  if stat_output=$(datasafed stat /); then
    :
  else
    status=$?
    printf 'backup info datasafed stat failed rc=%s\n' "$status" >&2
    return "$status"
  fi

  if total_size=$(
    printf '%s\n' "$stat_output" |
      awk '
        $1 == "TotalSize:" {
          count++
          if (NF == 2 && $2 ~ /^[0-9]+$/) {
            valid++
            value = $2
          }
        }
        END {
          if (count == 1 && valid == 1) {
            print value
            exit 0
          }
          exit 65
        }
      '
  ); then
    :
  else
    printf 'backup info TotalSize validation failed rc=65\n' >&2
    return 65
  fi

  if tmp_file=$(mktemp "${DP_BACKUP_INFO_FILE}.tmp.XXXXXX"); then
    :
  else
    status=$?
    printf 'backup info temporary file creation failed rc=%s\n' "$status" >&2
    return "$status"
  fi

  if printf '{"totalSize":"%s","timeRange":{"start":"%s","end":"%s"}}\n' \
    "$total_size" "$start_time" "$stop_time" >"$tmp_file"; then
    :
  else
    status=$?
    rm -f "$tmp_file" || :
    printf 'backup info temporary file write failed rc=%s\n' "$status" >&2
    return "$status"
  fi

  if mv "$tmp_file" "$DP_BACKUP_INFO_FILE"; then
    return 0
  else
    status=$?
  fi

  rm -f "$tmp_file" || :
  printf 'backup info publication failed rc=%s\n' "$status" >&2
  return "$status"
}

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
