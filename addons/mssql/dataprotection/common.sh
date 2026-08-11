# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

# Auto-detect sqlcmd path: mssql-tools18 (2022) vs mssql-tools (2019)
if [ -f /opt/mssql-tools18/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools18/bin/sqlcmd
elif [ -f /opt/mssql-tools/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools/bin/sqlcmd
else
  SQLCMD=sqlcmd
fi

sql_cmd="$SQLCMD -S ${DP_DB_HOST} -U $DP_DB_USER -P $DP_DB_PASSWORD -C -h-1 -W -x"
DP_CERTIFICATE_NAME="dbm_certificate"

trap handle_exit EXIT

function quote_tsql_identifier() {
  local value=${1:?'T-SQL identifier is required'}
  printf '[%s]' "${value//]/]]}"
}

function quote_tsql_literal() {
  local value=${1-}
  printf "N'"
  printf '%s' "$value" | sed "s/'/''/g"
  printf "'"
}

function datasafed_list_paths_to_file() {
  local output_file=${1:?'output file is required'}
  shift
  local json_file path_file
  json_file=$(mktemp "${output_file}.json.XXXXXX") || return 1
  path_file=$(mktemp "${output_file}.nul.XXXXXX") || {
    rm -f "$json_file"
    return 1
  }

  if ! datasafed list "$@" -o json > "$json_file"; then
    rm -f "$json_file" "$path_file"
    return 1
  fi
  if ! perl -MJSON::PP=decode_json -MEncode=encode,FB_CROAK -e '
    use strict;
    use warnings;
    binmode STDOUT, ":raw";

    sub emit_path {
      my ($value) = @_;
      if (ref($value) eq "ARRAY") {
        emit_path($_) for @{$value};
        return;
      }
      die "datasafed JSON entry is not an object\n" unless ref($value) eq "HASH";
      die "datasafed JSON entry has no scalar path\n"
        unless exists($value->{path}) && defined($value->{path}) && !ref($value->{path});
      die "datasafed path is empty\n" unless length($value->{path});
      die "datasafed path contains NUL\n" if index($value->{path}, "\0") >= 0;
      print encode("UTF-8", $value->{path}, FB_CROAK), "\0";
    }

    while (my $line = <>) {
      next if $line =~ /^\s*$/;
      emit_path(decode_json($line));
    }
  ' "$json_file" > "$path_file"; then
    rm -f "$json_file" "$path_file"
    return 1
  fi

  rm -f "$json_file"
  mv "$path_file" "$output_file"
}

function archive_metadata_version_for_path() {
  local path=${1:?'archive path is required'}
  if [[ "$path" =~ [[:space:]] ]]; then
    printf 'v2'
  else
    printf 'legacy'
  fi
}

function archive_metadata_encode_path() {
  local path=${1:?'archive path is required'}
  printf '%s' "$path" | perl -e '
    use strict;
    use warnings;
    binmode STDIN, ":raw";
    local $/;
    my $value = <STDIN>;
    die "archive path is empty\n" unless defined($value) && length($value);
    die "archive path contains NUL\n" if index($value, "\0") >= 0;
    print unpack("H*", $value);
  '
}

function archive_chain_format_entry() {
  local path=${1:?'archive path is required'} version encoded
  version=$(archive_metadata_version_for_path "$path") || return 1
  if [ "$version" = legacy ]; then
    printf '%s\n' "$path"
  else
    encoded=$(archive_metadata_encode_path "$path") || return 1
    printf 'v2\t%s\n' "$encoded"
  fi
}

function archive_metadata_decode_path() {
  local encoded=${1:?'encoded archive path is required'} decoded
  [[ "$encoded" =~ ^[0-9A-Fa-f]+$ ]] || return 1
  (( ${#encoded} % 2 == 0 )) || return 1
  decoded=$(perl -MEncode=decode,encode,FB_CROAK -e '
    use strict;
    use warnings;
    binmode STDOUT, ":raw";
    my $value = pack("H*", $ARGV[0]);
    die "archive path contains NUL\n" if index($value, "\0") >= 0;
    my $decoded = decode("UTF-8", $value, FB_CROAK);
    print encode("UTF-8", $decoded, FB_CROAK);
  ' "$encoded" && printf x) || return 1
  ARCHIVE_METADATA_DECODED_PATH=${decoded%x}
  [ -n "$ARCHIVE_METADATA_DECODED_PATH" ]
}

function archive_metadata_valid_next_timestamp() {
  local value=${1-}
  [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" = "${NEXT_LOG_BACKUP_PLACEHOLDER:-NEXT_LOG_BACKUP_PLACEHOLDER}" ]
}

function archive_metadata_parse_record() {
  local line=${1-} rest encoded full_timestamp next_timestamp path version
  ARCHIVE_METADATA_RECORD_VERSION=
  ARCHIVE_METADATA_RECORD_PATH=
  ARCHIVE_METADATA_RECORD_FULL_TIMESTAMP=
  ARCHIVE_METADATA_RECORD_NEXT_LOG_TIMESTAMP=

  if [[ "$line" == v2$'\t'* ]]; then
    version=v2
    rest=${line#v2$'\t'}
    [[ "$rest" == *$'\t'* ]] || return 1
    encoded=${rest%%$'\t'*}
    rest=${rest#*$'\t'}
    [[ "$rest" == *$'\t'* ]] || return 1
    full_timestamp=${rest%%$'\t'*}
    next_timestamp=${rest#*$'\t'}
    [[ "$next_timestamp" != *$'\t'* ]] || return 1
    archive_metadata_decode_path "$encoded" || return 1
    path=$ARCHIVE_METADATA_DECODED_PATH
  else
    version=legacy
    [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([0-9]+)[[:space:]]+([^[:space:]]+)$ ]] || return 1
    path=${BASH_REMATCH[1]}
    full_timestamp=${BASH_REMATCH[2]}
    next_timestamp=${BASH_REMATCH[3]}
  fi

  [[ "$full_timestamp" =~ ^[0-9]+$ ]] || return 1
  archive_metadata_valid_next_timestamp "$next_timestamp" || return 1
  ARCHIVE_METADATA_RECORD_VERSION=$version
  ARCHIVE_METADATA_RECORD_PATH=$path
  ARCHIVE_METADATA_RECORD_FULL_TIMESTAMP=$full_timestamp
  ARCHIVE_METADATA_RECORD_NEXT_LOG_TIMESTAMP=$next_timestamp
}

function archive_metadata_format_record() {
  local version=${1:?'archive metadata version is required'}
  local path=${2:?'archive path is required'}
  local full_timestamp=${3:?'full backup timestamp is required'}
  local next_timestamp=${4:?'next log timestamp is required'} encoded
  [[ "$full_timestamp" =~ ^[0-9]+$ ]] || return 1
  archive_metadata_valid_next_timestamp "$next_timestamp" || return 1

  case "$version" in
    legacy)
      [[ ! "$path" =~ [[:space:]] ]] || return 1
      printf '%s %s %s\n' "$path" "$full_timestamp" "$next_timestamp"
      ;;
    v2)
      encoded=$(archive_metadata_encode_path "$path") || return 1
      printf 'v2\t%s\t%s\t%s\n' "$encoded" "$full_timestamp" "$next_timestamp"
      ;;
    *)
      return 1
      ;;
  esac
}

function archive_metadata_load_file() {
  local file=${1:?'archive metadata file is required'} line
  ARCHIVE_METADATA_VERSIONS=()
  ARCHIVE_METADATA_PATHS=()
  ARCHIVE_METADATA_FULL_TIMESTAMPS=()
  ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS=()
  [ -r "$file" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    if ! archive_metadata_parse_record "$line"; then
      ARCHIVE_METADATA_VERSIONS=()
      ARCHIVE_METADATA_PATHS=()
      ARCHIVE_METADATA_FULL_TIMESTAMPS=()
      ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS=()
      return 1
    fi
    ARCHIVE_METADATA_VERSIONS+=("$ARCHIVE_METADATA_RECORD_VERSION")
    ARCHIVE_METADATA_PATHS+=("$ARCHIVE_METADATA_RECORD_PATH")
    ARCHIVE_METADATA_FULL_TIMESTAMPS+=("$ARCHIVE_METADATA_RECORD_FULL_TIMESTAMP")
    ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS+=("$ARCHIVE_METADATA_RECORD_NEXT_LOG_TIMESTAMP")
  done < "$file"
  [ "${#ARCHIVE_METADATA_PATHS[@]}" -gt 0 ]
}

function archive_metadata_write_loaded_file() {
  local file=${1:?'archive metadata file is required'}
  local start_index=${2:-0} temp_file index
  [ "${#ARCHIVE_METADATA_PATHS[@]}" -gt "$start_index" ] || return 1
  temp_file=$(mktemp "${file}.tmp.XXXXXX") || return 1
  for ((index=start_index; index<${#ARCHIVE_METADATA_PATHS[@]}; index++)); do
    if ! archive_metadata_format_record \
      "${ARCHIVE_METADATA_VERSIONS[$index]}" \
      "${ARCHIVE_METADATA_PATHS[$index]}" \
      "${ARCHIVE_METADATA_FULL_TIMESTAMPS[$index]}" \
      "${ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS[$index]}" >> "$temp_file"; then
      rm -f "$temp_file"
      return 1
    fi
  done
  mv "$temp_file" "$file"
}

function archive_metadata_write_single_record() {
  local file=${1:?'archive metadata file is required'}
  local path=${2:?'archive path is required'}
  local full_timestamp=${3:?'full backup timestamp is required'}
  local next_timestamp=${4:?'next log timestamp is required'} version
  version=$(archive_metadata_version_for_path "$path") || return 1
  ARCHIVE_METADATA_VERSIONS=("$version")
  ARCHIVE_METADATA_PATHS=("$path")
  ARCHIVE_METADATA_FULL_TIMESTAMPS=("$full_timestamp")
  ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS=("$next_timestamp")
  archive_metadata_write_loaded_file "$file"
}

function archive_metadata_append_record() {
  local file=${1:?'archive metadata file is required'}
  local path=${2:?'archive path is required'}
  local full_timestamp=${3:?'full backup timestamp is required'}
  local next_timestamp=${4:?'next log timestamp is required'} version
  if [ -s "$file" ]; then
    archive_metadata_load_file "$file" || return 1
  else
    ARCHIVE_METADATA_VERSIONS=()
    ARCHIVE_METADATA_PATHS=()
    ARCHIVE_METADATA_FULL_TIMESTAMPS=()
    ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS=()
  fi
  version=$(archive_metadata_version_for_path "$path") || return 1
  ARCHIVE_METADATA_VERSIONS+=("$version")
  ARCHIVE_METADATA_PATHS+=("$path")
  ARCHIVE_METADATA_FULL_TIMESTAMPS+=("$full_timestamp")
  ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS+=("$next_timestamp")
  archive_metadata_write_loaded_file "$file"
}

function archive_metadata_set_last_next() {
  local file=${1:?'archive metadata file is required'}
  local next_timestamp=${2:?'next log timestamp is required'} index
  archive_metadata_valid_next_timestamp "$next_timestamp" || return 1
  archive_metadata_load_file "$file" || return 1
  index=$((${#ARCHIVE_METADATA_PATHS[@]} - 1))
  ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS[index]=$next_timestamp
  archive_metadata_write_loaded_file "$file"
}

function archive_metadata_contains_path() {
  local file=${1:?'archive metadata file is required'}
  local expected_path=${2:?'archive path is required'} path
  archive_metadata_load_file "$file" || return 1
  for path in "${ARCHIVE_METADATA_PATHS[@]}"; do
    [ "$path" = "$expected_path" ] && return 0
  done
  return 2
}

function load_database_names() {
  local scope=${1:?'database scope is required'} exclusions query encoded_output encoded decoded
  case "$scope" in
    include-master)
      exclusions="'tempdb','model','msdb'"
      ;;
    user-only)
      exclusions="'tempdb','model','msdb','master'"
      ;;
    *)
      return 1
      ;;
  esac

  # sqlcmd row formatting cannot represent embedded newlines unambiguously.
  # Transport the nvarchar bytes as one hex-only line per database, then decode
  # them back to UTF-8 before the caller iterates the quoted Bash array.
  query="SET NOCOUNT ON; SELECT CONVERT(varchar(max), CONVERT(varbinary(max), name), 2) FROM sys.databases WHERE name NOT IN (${exclusions}) ORDER BY database_id;"
  DP_DATABASE_NAMES=()
  encoded_output=$(${sql_cmd} -Q "$query") || return 1
  while IFS= read -r encoded || [ -n "$encoded" ]; do
    [ -z "$encoded" ] && continue
    if [[ ! "$encoded" =~ ^[0-9A-Fa-f]+$ ]] || (( ${#encoded} % 4 != 0 )); then
      DP_DATABASE_NAMES=()
      return 1
    fi
    decoded=$(perl -MEncode=decode,encode,FB_CROAK -e '
      my $value = decode("UTF-16LE", pack("H*", $ARGV[0]), FB_CROAK);
      print encode("UTF-8", $value, FB_CROAK);
    ' "$encoded" && printf x) || {
      DP_DATABASE_NAMES=()
      return 1
    }
    DP_DATABASE_NAMES+=("${decoded%x}")
  done <<< "$encoded_output"

  if [ "$scope" = include-master ] && [ "${#DP_DATABASE_NAMES[@]}" -eq 0 ]; then
    return 1
  fi
}

DP_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} INFO: $msg"
}

# log error info
DP_error_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} ERROR: $msg"
}

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    DP_error_log "failed with exit code $exit_code"
    if [ "${clean_backup_after_failure}" == "true" ]; then
       rm -rf ${BACKUP_DIR}/${DP_BACKUP_NAME}
    fi
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

function copy_only_parameter() {
  # On an AG secondary, SQL Server only permits COPY_ONLY full backups; a plain
  # (non-COPY_ONLY) full backup on a secondary replica is rejected. Emit the
  # COPY_ONLY clause so the caller can splice it into the BACKUP statement.
  #
  # This MUST echo the clause rather than set a variable: the caller uses
  # $(copy_only_parameter) in a command substitution, which runs in a subshell,
  # so any variable assignment here would be discarded and the clause lost.
  # Echoing also keeps the function's stdout limited to the clause, so a role
  # query error can never be spliced verbatim into the BACKUP statement.
  local role
  role=$(${sql_cmd} -Q "SET NOCOUNT ON;select role_desc from sys.dm_hadr_availability_replica_states where is_local=1")
  if [[ "${role}" == *"SECONDARY"* ]]; then
    echo ", COPY_ONLY"
  fi
}

function backup_database_with_full() {
  local database_name=${1:?"missing database name"}
  local database_sql backup_path_sql media_name_sql database_literal
  database_sql=$(quote_tsql_identifier "$database_name")
  backup_path_sql=$(quote_tsql_literal "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.full.bak")
  media_name_sql=$(quote_tsql_literal "KB-${DP_BACKUP_NAME}")
  database_literal=$(quote_tsql_literal "$database_name")
  backup_sql=$(cat <<EOF
BACKUP DATABASE ${database_sql}
TO DISK = ${backup_path_sql}
   WITH FORMAT,
    COMPRESSION,
    MEDIANAME = ${media_name_sql},
    STATS=1,
    NAME = ${database_literal}$(copy_only_parameter);
GO
EOF
)
  DP_log "execute ${backup_sql}"
  local value rc
  value=$($SQLCMD -S "${DP_DB_HOST}" -U "$DP_DB_USER" -P "$DP_DB_PASSWORD" -C -x -Q "$backup_sql")
  rc=$?
  # Treat both a non-zero sqlcmd exit (connection/tool failure) and a T-SQL
  # error message ("Msg NNNN, ...", which sqlcmd reports with exit 0 unless -b)
  # as a failure, so the caller can fail-fast instead of silently omitting a
  # database from the backup.
  if [ $rc -ne 0 ] || [[ "$value" == *"Msg "* ]]; then
    DP_error_log "${value}"
    return 1
  fi
  return 0
}

function backup_server_roles_and_login_name() {
    ${sql_cmd} -Q "EXEC dbo.sp_help_revlogin" | datasafed push  - "server_login_names.sql"
}


function push_backups() {
  backup_server_roles_and_login_name
  backup_certificate
  # Note: ${sql_cmd} cannot be used after this point since we change to backup directory
  cd "${BACKUP_DIR}/${DP_BACKUP_NAME}"
  while IFS= read -r -d '' file; do
    file_name=${file#./}
    DP_log "push backup file: ${file_name}"
    datasafed push -z zstd-fastest "${file}" "/${file_name}.zst"
  done < <(find . -type f -not -name "*.pfx" -not -name "*.cer" -not -name "*.pvk" -print0)
}

function save_backup_status() {
  rm -rf "${BACKUP_DIR:?}/${DP_BACKUP_NAME:?}"
  local extras="" status_rows name_hex database_backup_lsn
  local differential_base_lsn checkpoint_lsn first_lsn last_lsn type finish_time extra
  local result_json stop_epoch stat_output total_size info_tmp
  local row_count=0 parse_failed=false
  local result_file stop_file
  local sql="SET NOCOUNT ON;
SELECT CONCAT(
  CONVERT(varchar(max), CONVERT(varbinary(max), b.name), 2), CHAR(9),
  COALESCE(CONVERT(varchar(50), b.database_backup_lsn), 'NULL'), CHAR(9),
  COALESCE(CONVERT(varchar(50), b.differential_base_lsn), 'NULL'), CHAR(9),
  COALESCE(CONVERT(varchar(50), b.checkpoint_lsn), 'NULL'), CHAR(9),
  COALESCE(CONVERT(varchar(50), b.first_lsn), 'NULL'), CHAR(9),
  COALESCE(CONVERT(varchar(50), b.last_lsn), 'NULL'), CHAR(9),
  COALESCE(CONVERT(varchar(1), b.type), 'NULL'), CHAR(9),
  CONVERT(varchar(19), b.backup_finish_date, 126))
FROM backupmediaset AS m
JOIN backupset AS b ON b.media_set_id = m.media_set_id
WHERE b.name != 'master' AND m.name = 'KB-${DP_BACKUP_NAME}'
ORDER BY b.backup_finish_date;"

  STOP_TIME=$(date -u "+%Y-%m-%dT%H:%M:%SZ") || return 1
  result_file=$(mktemp) || return 1
  stop_file=$(mktemp) || {
    rm -f "$result_file"
    return 1
  }

  if ! status_rows=$(${sql_cmd} -d msdb -Q "${sql}"); then
    rm -f "$result_file" "$stop_file"
    return 1
  fi

  while IFS=$'\t' read -r name_hex database_backup_lsn differential_base_lsn \
    checkpoint_lsn first_lsn last_lsn type finish_time extra; do
    [ -z "$name_hex" ] && continue
    if [[ ! "$name_hex" =~ ^([0-9A-Fa-f]{4})+$ ]] ||
      [[ ! "$database_backup_lsn" =~ ^(NULL|[0-9]+)$ ]] ||
      [[ ! "$differential_base_lsn" =~ ^(NULL|[0-9]+)$ ]] ||
      [[ ! "$checkpoint_lsn" =~ ^(NULL|[0-9]+)$ ]] ||
      [[ ! "$first_lsn" =~ ^(NULL|[0-9]+)$ ]] ||
      [[ ! "$last_lsn" =~ ^(NULL|[0-9]+)$ ]] ||
      [[ ! "$type" =~ ^(D|I)$ ]] ||
      [[ ! "$finish_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] ||
      [ -n "$extra" ]; then
      parse_failed=true
      break
    fi

    if ! result_json=$(perl -MEncode=decode,FB_CROAK -MJSON::PP=encode_json -e '
      my ($encoded_name, @values) = @ARGV;
      my $name = decode("UTF-16LE", pack("H*", $encoded_name), FB_CROAK);
      die "empty database name" unless length $name;
      print encode_json({
        name => $name,
        databaseBackupLSN => $values[0],
        differentialBaseLSN => $values[1],
        checkpointLSN => $values[2],
        firstLSN => $values[3],
        lastLSN => $values[4],
        type => $values[5],
      });
    ' "$name_hex" "$database_backup_lsn" "$differential_base_lsn" \
      "$checkpoint_lsn" "$first_lsn" "$last_lsn" "$type"); then
      parse_failed=true
      break
    fi
    printf '%s\n' "$result_json" >> "$result_file" || {
      parse_failed=true
      break
    }
    printf '%s\n' "$finish_time" > "$stop_file" || {
      parse_failed=true
      break
    }
    row_count=$((row_count + 1))
  done <<< "$status_rows"

  if [ "$parse_failed" = true ] || [ "$row_count" -eq 0 ]; then
    rm -f "$result_file" "$stop_file"
    return 1
  fi

  while IFS= read -r result_json; do
    if [ -n "$extras" ]; then
      extras="${extras},"
    fi
    extras="${extras}${result_json}"
  done < "$result_file"

  if [ -s "$stop_file" ]; then
    # sqlserver 时间点恢复时，如果恢复时间点在全量备份应用的日志时间点之前，会报错。所以我们可以把备份时间往后推1秒，使用上一个全量备份来进行时间点恢复。
    finish_time=$(cat "$stop_file")
    stop_epoch=$(date -d "$finish_time" +%s) || {
      rm -f "$result_file" "$stop_file"
      return 1
    }
    stop_epoch=$((stop_epoch + 1))
    STOP_TIME=$(date -d "@${stop_epoch}" -u "+%Y-%m-%dT%H:%M:%SZ") || {
      rm -f "$result_file" "$stop_file"
      return 1
    }
  fi

  if ! stat_output=$(datasafed stat --json /); then
    DP_error_log "failed to stat backup repository with DataSafed JSON output"
    rm -f "$result_file" "$stop_file"
    return 1
  fi
  if ! total_size=$(printf '%s\n' "$stat_output" | perl -MJSON::PP=decode_json,encode_json -0777 -e '
    my $document = decode_json(<>);
    die "invalid stat document" unless ref($document) eq "HASH" && exists $document->{total_size};
    my $encoded_size = encode_json($document->{total_size});
    die "invalid total_size" unless $encoded_size =~ /\A(?:0|[1-9][0-9]*)\z/;
    print $encoded_size;
  ' 2>/dev/null); then
    DP_error_log "failed to parse DataSafed total_size from JSON output"
    rm -f "$result_file" "$stop_file"
    return 1
  fi

  info_tmp="${DP_BACKUP_INFO_FILE}.tmp.$$"
  if ! printf '{"totalSize":"%s","extras":[%s],"timeRange":{"end":"%s"}}\n' \
    "$total_size" "$extras" "$STOP_TIME" > "$info_tmp" ||
    ! mv "$info_tmp" "$DP_BACKUP_INFO_FILE"; then
    DP_error_log "failed to write backup status info atomically"
    rm -f "$result_file" "$stop_file" "$info_tmp"
    return 1
  fi
  rm -f "$result_file" "$stop_file"
}

function backup_certificate() {
  # backup certificate
  local certificate_sql certificate_literal password_literal
  certificate_sql=$(quote_tsql_identifier "$DP_CERTIFICATE_NAME")
  certificate_literal=$(quote_tsql_literal "$DP_CERTIFICATE_NAME")
  password_literal=$(quote_tsql_literal "$MSSQL_PRIVATE_ENCRYPTION_PASSWORD")
  certificate_check=$(${sql_cmd} -Q "select * from sys.certificates where name = ${certificate_literal}")
  if [ -z "${certificate_check}" ];then
    DP_error_log "certificate ${DP_CERTIFICATE_NAME} not exist"
    exit 1
  fi

  # Detect SQL Server major version: 16=2022 (supports PFX), 15=2019 (PVK/CER only)
  local mssql_major_version
  mssql_major_version=$(${sql_cmd} -Q "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS INT)" 2>/dev/null | tr -d '[:space:]')

  if [ "${mssql_major_version:-16}" -ge 16 ]; then
    local pfx_path_sql
    pfx_path_sql=$(quote_tsql_literal "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.pfx")
    backup_sql=$(cat <<EOF
BACKUP CERTIFICATE ${certificate_sql} TO FILE = ${pfx_path_sql}
WITH
    FORMAT = 'PFX',
    PRIVATE KEY (
ENCRYPTION BY PASSWORD = ${password_literal},
ALGORITHM = 'AES_256'
    )
EOF
)
    ${sql_cmd} -Q "${backup_sql}"
    if [[ $? -ne 0 ]]; then
      DP_error_log "backup certificate ${DP_CERTIFICATE_NAME} failed (PFX)"
      exit 1
    fi
    datasafed push "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.pfx" "/${DP_CERTIFICATE_NAME}.pfx"
  else
    # SQL Server 2019: use CER + PVK format
    local cer_path_sql pvk_path_sql
    cer_path_sql=$(quote_tsql_literal "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.cer")
    pvk_path_sql=$(quote_tsql_literal "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.pvk")
    backup_sql=$(cat <<EOF
BACKUP CERTIFICATE ${certificate_sql} TO FILE = ${cer_path_sql}
WITH PRIVATE KEY (
    FILE = ${pvk_path_sql},
    ENCRYPTION BY PASSWORD = ${password_literal}
)
EOF
)
    ${sql_cmd} -Q "${backup_sql}"
    if [[ $? -ne 0 ]]; then
      DP_error_log "backup certificate ${DP_CERTIFICATE_NAME} failed (PVK/CER)"
      exit 1
    fi
    datasafed push "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.cer" "/${DP_CERTIFICATE_NAME}.cer"
    datasafed push "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.pvk" "/${DP_CERTIFICATE_NAME}.pvk"
  fi
  echo ${MSSQL_PRIVATE_ENCRYPTION_PASSWORD} | datasafed push - "${DP_CERTIFICATE_NAME}.password"
}
