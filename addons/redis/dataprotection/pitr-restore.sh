export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function truncate_aof() {
  local aof_file=$(find "$DATA_DIR" -type f -name "*.aof" | sort -r | head -n 1)
  local temp_file="${aof_file}.tmp"
  local found=false
  local restore_time=$(date -d "$DP_RESTORE_TIME" +%s)

  while IFS= read -r line; do
    if [[ "$line" == \#TS:* ]]; then
      local timestamp=$(echo ${line#\#TS:} | tr -d '\r')
      if ((${timestamp} > ${restore_time})); then
        found=true
        break
      fi
    fi
    echo "$line" >>"$temp_file"
  done <"$aof_file"

  if [ "$found" = true ]; then
    DP_log "Truncate aof file: $aof_file"
    mv "$temp_file" "$aof_file"
  else
    rm "$temp_file"
  fi
}

function get_files_to_restore() {
  local restore_time=$(date -d "$DP_RESTORE_TIME" +%s)

  local filename=$(datasafed list / | sort -t '.' -k1,1r | awk -v rt="$restore_time" -F '.' '$1 <= rt {print; exit}')
  if [ -z "$filename" ]; then
    DP_log "No backup found for the given restore time: $DP_RESTORE_TIME"
    exit 0
  fi

  case "$filename" in
  *.dir/)
    DP_log "Pull directory: $filename"
    DP_pull_directory "${filename}" "${DATA_DIR}"
    ;;
  *.tar.zst)
    echo "Pull aof_file: $filename"
    datasafed pull -d zstd-fastest "${filename}" - | tar -xvf - -C "${DATA_DIR}/"
    ;;
  *)
    DP_log "Unknown aof_file type: $filename"
    ;;
  esac
}

res=$(find ${DATA_DIR} -type f)
data_protection_file=${DATA_DIR}/.kb-data-protection
if [ ! -z "${res}" ] && [ ! -f ${data_protection_file} ]; then
  echo "${DATA_DIR} is not empty! Please make sure that the directory is empty before restoring the backup."
  exit 1
fi
# touch placeholder file
touch ${data_protection_file}

get_files_to_restore
truncate_aof

chmod -R 777 "${DATA_DIR}"
rm -rf ${data_protection_file} && sync
DP_log "Restore complete."
