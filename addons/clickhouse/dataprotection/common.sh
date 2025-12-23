#!/bin/bash
# log info file
function DP_log() {
	msg=$1
	local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
	echo "${curr_date} INFO: $msg"
}

# log error info
function DP_error_log() {
	msg=$1
	local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
	echo "${curr_date} ERROR: $msg"
}

# Get file names without extensions based on the incoming file path
function DP_get_file_name_without_ext() {
	local fileName=$1
	local file_without_ext=${fileName%.*}
	echo $(basename ${file_without_ext})
}

# Save backup status info file for syncing progress.
# timeFormat: %Y-%m-%dT%H:%M:%SZ
function DP_save_backup_status_info() {
	local totalSize=$1
	local startTime=$2
	local stopTime=$3
	local timeZone=$4
	local extras=$5
	local timeZoneStr=""
	if [ ! -z ${timeZone} ]; then
		timeZoneStr=",\"timeZone\":\"${timeZone}\""
	fi
	if [ -z "${stopTime}" ]; then
		echo "{\"totalSize\":\"${totalSize}\"}" >${DP_BACKUP_INFO_FILE}
	elif [ -z "${startTime}" ]; then
		echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"end\":\"${stopTime}\"${timeZoneStr}}}" >${DP_BACKUP_INFO_FILE}
	else
		echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"start\":\"${startTime}\",\"end\":\"${stopTime}\"${timeZoneStr}}}" >${DP_BACKUP_INFO_FILE}
	fi
}

# Clean up expired logfiles.
# Default interval is 60s
# Default rootPath is /
function DP_purge_expired_files() {
	local currentUnix="${1:?missing current unix}"
	local last_purge_time="${2:?missing last_purge_time}"
	local root_path=${3:-"/"}
	local interval_seconds=${4:-60}
	local diff_time=$((${currentUnix} - ${last_purge_time}))
	if [[ -z ${DP_TTL_SECONDS} || ${diff_time} -lt ${interval_seconds} ]]; then
		return
	fi
	expiredUnix=$((${currentUnix} - ${DP_TTL_SECONDS}))
	files=$(datasafed list -f --recursive --older-than ${expiredUnix} ${root_path})
	for file in "${files[@]}"; do
		datasafed rm "$file"
		echo "$file"
	done
}

# analyze the start time of the earliest file from the datasafed backend.
# Then record the file name into dp_oldest_file.info.
# If the oldest file is no changed, exit the process.
# This can save traffic consumption.
function DP_analyze_start_time_from_datasafed() {
	local oldest_file="${1:?missing oldest file}"
	local get_start_time_from_file="${2:?missing get_start_time_from_file function}"
	local datasafed_pull="${3:?missing datasafed_pull function}"
	local info_file="${KB_BACKUP_WORKDIR}/dp_oldest_file.info"
	mkdir -p ${KB_BACKUP_WORKDIR} && cd ${KB_BACKUP_WORKDIR}
	if [ -f ${info_file} ]; then
		last_oldest_file=$(cat ${info_file})
		last_oldest_file_name=$(DP_get_file_name_without_ext ${last_oldest_file})
		if [ "$last_oldest_file" == "${oldest_file}" ]; then
			# oldest file no changed.
			${get_start_time_from_file} $last_oldest_file_name
			return
		fi
		# remove last oldest file
		if [ -f ${last_oldest_file_name} ]; then
			rm -rf ${last_oldest_file_name}
		fi
	fi
	# pull file
	${datasafed_pull} ${oldest_file}
	# record last oldest file
	echo ${oldest_file} >${info_file}
	oldest_file_name=$(DP_get_file_name_without_ext ${oldest_file})
	${get_start_time_from_file} ${oldest_file_name}
}

# get the timeZone offset for location, such as Asia/Shanghai
function getTimeZoneOffset() {
	local timeZone=${1:?missing time zone}
	if [[ $timeZone == "+"* ]] || [[ $timeZone == "-"* ]]; then
		echo ${timeZone}
		return
	fi
	local currTime=$(TZ=UTC date)
	local utcHour=$(TZ=UTC date -d "${currTime}" +"%H")
	local zoneHour=$(TZ=${timeZone} date -d "${currTime}" +"%H")
	local offset=$((${zoneHour} - ${utcHour}))
	if [ $offset -eq 0 ]; then
		return
	fi
	symbol="+"
	if [ $offset -lt 0 ]; then
		symbol="-" && offset=${offset:1}
	fi
	if [ $offset -lt 10 ]; then
		offset="0${offset}"
	fi
	echo "${symbol}${offset}:00"
}

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
	exit_code=$?
	if [ "$exit_code" -ne 0 ]; then
		DP_error_log "Backup failed with exit code $exit_code"
		touch "${DP_BACKUP_INFO_FILE}.exit"
		exit 1
	fi
}

function generate_backup_config() {
	clickhouse_backup_config=$(mktemp) || {
		DP_error_log "Failed to create temporary file"
		return 1
	}
	# whole config see https://github.com/Altinity/clickhouse-backup
	cat >"$clickhouse_backup_config" <<'EOF'
general:
  remote_storage: s3 # REMOTE_STORAGE, choice from: `azblob`,`gcs`,`s3`, etc; if `none` then `upload` and `download` commands will fail.
  max_file_size: 1125899906842624 # MAX_FILE_SIZE, 1PB by default, useless when upload_by_part is true, use to split data parts files by archives
  backups_to_keep_local: 0 # BACKUPS_TO_KEEP_LOCAL, how many latest local backup should be kept, 0 means all created backups will be stored on local disk, -1 means backup will keep after `create` but will delete after `create_remote` command
  backups_to_keep_remote: 0 # BACKUPS_TO_KEEP_REMOTE, how many latest backup should be kept on remote storage, 0 means all uploaded backups will be stored on remote storage.
  log_level: info # LOG_LEVEL, a choice from `debug`, `info`, `warning`, `error`
  allow_empty_backups: true # ALLOW_EMPTY_BACKUPS
  download_concurrency: 1 # DOWNLOAD_CONCURRENCY, max 255, by default, the value is round(sqrt(AVAILABLE_CPU_CORES / 2))
  upload_concurrency: 1 # UPLOAD_CONCURRENCY, max 255, by default, the value is round(sqrt(AVAILABLE_CPU_CORES / 2))
  download_max_bytes_per_second: 0 # DOWNLOAD_MAX_BYTES_PER_SECOND, 0 means no throttling
  upload_max_bytes_per_second: 0 # UPLOAD_MAX_BYTES_PER_SECOND, 0 means no throttling
  object_disk_server_side_copy_concurrency: 32
  allow_object_disk_streaming: false
  # restore schema on cluster is alway run by `INIT_CLUSTER_NAME` cluster of clickhouse, when schema restore, the ddl only runs on first pod of first shard
  restore_schema_on_cluster: "" # RESTORE_SCHEMA_ON_CLUSTER, execute all schema related SQL queries with `ON CLUSTER` clause as Distributed DDL. This isn't applicable when `use_embedded_backup_restore: true`
  upload_by_part: true # UPLOAD_BY_PART
  download_by_part: true # DOWNLOAD_BY_PART
  use_resumable_state: true # USE_RESUMABLE_STATE, allow resume upload and download according to the <backup_name>.resumable file. Resumable state is not supported for custom method in remote storage.
  restore_database_mapping: {} # RESTORE_DATABASE_MAPPING, like "src_db1:target_db1,src_db2:target_db2", restore rules from backup databases to target databases, which is useful when changing destination database, all atomic tables will be created with new UUIDs.
  restore_table_mapping: {} # RESTORE_TABLE_MAPPING, like "src_table1:target_table1,src_table2:target_table2" restore rules from backup tables to target tables, which is useful when changing destination tables.
  retries_on_failure: 3 # RETRIES_ON_FAILURE, how many times to retry after a failure during upload or download
  retries_pause: 5s # RETRIES_PAUSE, duration time to pause after each download or upload failure
  watch_interval: 1h # WATCH_INTERVAL, use only for `watch` command, backup will create every 1h
  full_interval: 24h # FULL_INTERVAL, use only for `watch` command, full backup will create every 24h
  watch_backup_name_template: "shard{shard}-{type}-{time:20060102150405}" # WATCH_BACKUP_NAME_TEMPLATE, used only for `watch` command, macros values will apply from `system.macros` for time:XXX, look format in https://go.dev/src/time/format.go
  sharded_operation_mode: none # SHARDED_OPERATION_MODE, how different replicas will shard backing up data for tables. Options are: none (no sharding), table (table granularity), database (database granularity), first-replica (on the lexicographically sorted first active replica). If left empty, then the "none" option will be set as default.
  cpu_nice_priority: 15 # CPU niceness priority, to allow throttling CPU intensive operation, more details https://manpages.ubuntu.com/manpages/xenial/man1/nice.1.html
  io_nice_priority: "idle" # IO niceness priority, to allow throttling DISK intensive operation, more details https://manpages.ubuntu.com/manpages/xenial/man1/ionice.1.html
  rbac_backup_always: true # always, backup RBAC objects
  rbac_resolve_conflicts: "recreate" # action, when RBAC object with the same name already exists, allow "recreate", "ignore", "fail" values
clickhouse:
  username: default # CLICKHOUSE_USERNAME
  password: "" # CLICKHOUSE_PASSWORD
  host: localhost # CLICKHOUSE_HOST, To make backup data `clickhouse-backup` requires access to the same file system as clickhouse-server, so `host` should localhost or address of another docker container on the same machine, or IP address bound to some network interface on the same host.
  port: 9000 # CLICKHOUSE_PORT, don't use 8123, clickhouse-backup doesn't support HTTP protocol
  disk_mapping: {} # CLICKHOUSE_DISK_MAPPING, use this mapping when your `system.disks` are different between the source and destination clusters during backup and restore process. The format for this env variable is "disk_name1:disk_path1,disk_name2:disk_path2". For YAML please continue using map syntax. If destination disk is different from source backup disk then you need to specify the destination disk in the config file: disk_mapping: disk_destination: /var/lib/clickhouse/disks/destination `disk_destination` needs to be referenced in backup (source config), and all names from this map (`disk:path`) shall exist in `system.disks` on destination server. During download of the backup from remote location (s3), if `name` is not present in `disk_mapping` (on the destination server config too) then `default` disk path will used for download. `disk_mapping` is used to understand during download where downloaded parts shall be unpacked (which disk) on destination server and where to search for data parts directories during restore.
  skip_tables: # CLICKHOUSE_SKIP_TABLES, the list of tables (pattern are allowed) which are ignored during backup and restore process The format for this env variable is "pattern1,pattern2,pattern3". For YAML please continue using list syntax
    - system.*
    - INFORMATION_SCHEMA.*
    - information_schema.*
  skip_table_engines: [] # CLICKHOUSE_SKIP_TABLE_ENGINES, the list of tables engines which are ignored during backup, upload, download, restore process The format for this env variable is "Engine1,Engine2,engine3". For YAML please continue using list syntax
  skip_disks: [] # CLICKHOUSE_SKIP_DISKS, list of disk names which are ignored during create, upload, download and restore command The format for this env variable is "Engine1,Engine2,engine3". For YAML please continue using list syntax
  skip_disk_types: [] # CLICKHOUSE_SKIP_DISK_TYPES, list of disk types which are ignored during create, upload, download and restore command The format for this env variable is "Engine1,Engine2,engine3". For YAML please continue using list syntax
  timeout: 5m # CLICKHOUSE_TIMEOUT
  freeze_by_part: false # CLICKHOUSE_FREEZE_BY_PART, allow freezing by part instead of freezing the whole table
  freeze_by_part_where: "" # CLICKHOUSE_FREEZE_BY_PART_WHERE, allow parts filtering during freezing when freeze_by_part: true
  secure: false # CLICKHOUSE_SECURE, use TLS encryption for connection
  skip_verify: false # CLICKHOUSE_SKIP_VERIFY, skip certificate verification and allow potential certificate warnings
  sync_replicated_tables: true # CLICKHOUSE_SYNC_REPLICATED_TABLES
  tls_key: "" # CLICKHOUSE_TLS_KEY, filename with TLS key file
  tls_cert: "" # CLICKHOUSE_TLS_CERT, filename with TLS certificate file
  tls_ca: "" # CLICKHOUSE_TLS_CA, filename with TLS custom authority file
  log_sql_queries: true # CLICKHOUSE_LOG_SQL_QUERIES, logging `clickhouse-backup` SQL queries on `info` level, when true, `debug` level when false
  debug: false # CLICKHOUSE_DEBUG
  config_dir: "/opt/bitnami/clickhouse/etc" # CLICKHOUSE_CONFIG_DIR
  restart_command: "sql:SYSTEM SHUTDOWN" # CLICKHOUSE_RESTART_COMMAND, use this command when restoring with --rbac, --rbac-only or --configs, --configs-only options will split command by ; and execute one by one, all errors will logged and ignore available prefixes - sql: will execute SQL query - exec: will execute command via shell
  ignore_not_exists_error_during_freeze: true # CLICKHOUSE_IGNORE_NOT_EXISTS_ERROR_DURING_FREEZE, helps to avoid backup failures when running frequent CREATE / DROP tables and databases during backup, `clickhouse-backup` will ignore `code: 60` and `code: 81` errors during execution of `ALTER TABLE ... FREEZE`
  check_replicas_before_attach: true # CLICKHOUSE_CHECK_REPLICAS_BEFORE_ATTACH, helps avoiding concurrent ATTACH PART execution when restoring ReplicatedMergeTree tables
  default_replica_path: "/clickhouse/tables/{layer}/{shard}/{database}/{table}" # CLICKHOUSE_DEFAULT_REPLICA_PATH, will use during restore Replicated tables without macros in replication_path if replica already exists, to avoid restoring conflicts
  default_replica_name: "{replica}" # CLICKHOUSE_DEFAULT_REPLICA_NAME, will use during restore Replicated tables without macros in replica_name if replica already exists, to avoid restoring conflicts
  use_embedded_backup_restore: false # CLICKHOUSE_USE_EMBEDDED_BACKUP_RESTORE, use BACKUP / RESTORE SQL statements instead of regular SQL queries to use features of modern ClickHouse server versions
  embedded_backup_disk: "" # CLICKHOUSE_EMBEDDED_BACKUP_DISK - disk from system.disks which will use when `use_embedded_backup_restore: true`
  backup_mutations: true # CLICKHOUSE_BACKUP_MUTATIONS, allow backup mutations from system.mutations WHERE is_done=0 and apply it during restore
  restore_as_attach: false # CLICKHOUSE_RESTORE_AS_ATTACH, allow restore tables which have inconsistent data parts structure and mutations in progress
  check_parts_columns: true # CLICKHOUSE_CHECK_PARTS_COLUMNS, check data types from system.parts_columns during create backup to guarantee mutation is complete
  max_connections: 0 # CLICKHOUSE_MAX_CONNECTIONS, how many parallel connections could be opened during operations
s3:
  access_key: "" # S3_ACCESS_KEY
  secret_key: "" # S3_SECRET_KEY
  bucket: "" # S3_BUCKET
  endpoint: "" # S3_ENDPOINT
  region: us-east-1 # S3_REGION
  acl: private # S3_ACL, AWS changed S3 defaults in April 2023 so that all new buckets have ACL disabled: https://aws.amazon.com/blogs/aws/heads-up-amazon-s3-security-changes-are-coming-in-april-of-2023/ They also recommend that ACLs are disabled: https://docs.aws.amazon.com/AmazonS3/latest/userguide/ensure-object-ownership.html use `acl: ""` if you see "api error AccessControlListNotSupported: The bucket does not allow ACLs"
  assume_role_arn: "" # S3_ASSUME_ROLE_ARN
  force_path_style: false # S3_FORCE_PATH_STYLE
  path: "" # S3_PATH, `system.macros` values can be applied as {macro_name}
  object_disk_path: "" # S3_OBJECT_DISK_PATH, path for backup of part from clickhouse object disks, if object disks present in clickhouse, then shall not be zero and shall not be prefixed by `path`
  disable_ssl: false # S3_DISABLE_SSL
  compression_level: 1 # S3_COMPRESSION_LEVEL
  compression_format: tar # S3_COMPRESSION_FORMAT, allowed values tar, lz4, bzip2, gzip, sz, xz, brortli, zstd, `none` for upload data part folders as is look at details in https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html
  sse: "" # S3_SSE, empty (default), AES256, or aws:kms
  sse_customer_algorithm: "" # S3_SSE_CUSTOMER_ALGORITHM, encryption algorithm, for example, AES256
  sse_customer_key: "" # S3_SSE_CUSTOMER_KEY, customer-provided encryption key use `openssl rand 32 > aws_sse.key` and `cat aws_sse.key | base64`
  sse_customer_key_md5: "" # S3_SSE_CUSTOMER_KEY_MD5, 128-bit MD5 digest of the encryption key according to RFC 1321 use `cat aws_sse.key | openssl dgst -md5 -binary | base64`
  sse_kms_key_id: "" # S3_SSE_KMS_KEY_ID, if S3_SSE is aws:kms then specifies the ID of the Amazon Web Services Key Management Service
  sse_kms_encryption_context: "" # S3_SSE_KMS_ENCRYPTION_CONTEXT, base64-encoded UTF-8 string holding a JSON with the encryption context Specifies the Amazon Web Services KMS Encryption Context to use for object encryption. This is a collection of non-secret key-value pairs that represent additional authenticated data. When you use an encryption context to encrypt data, you must specify the same (an exact case-sensitive match) encryption context to decrypt the data. An encryption context is supported only on operations with symmetric encryption KMS keys
  disable_cert_verification: false # S3_DISABLE_CERT_VERIFICATION
  use_custom_storage_class: false # S3_USE_CUSTOM_STORAGE_CLASS
  storage_class: STANDARD # S3_STORAGE_CLASS, by default allow only from list https://github.com/aws/aws-sdk-go-v2/blob/main/service/s3/types/enums.go#L787-L799
  concurrency: 1 # S3_CONCURRENCY
  max_parts_count: 4000 # S3_MAX_PARTS_COUNT, number of parts for S3 multipart uploads
  allow_multipart_download: false # S3_ALLOW_MULTIPART_DOWNLOAD, allow faster multipart download speed, but will require additional disk space, download_concurrency * part size in worst case
  checksum_algorithm: "" # S3_CHECKSUM_ALGORITHM, use it when you use object lock which allow to avoid delete keys from bucket until some timeout after creation, use CRC32 as fastest
  object_labels: {} # S3_OBJECT_LABELS, allow setup metadata for each object during upload, use {macro_name} from system.macros and {backupName} for current backup name The format for this env variable is "key1:value1,key2:value2". For YAML please continue using map syntax
  custom_storage_class_map: {} # S3_CUSTOM_STORAGE_CLASS_MAP, allow setup storage class depending on the backup name regexp pattern, format nameRegexp > className
  request_payer: "" # S3_REQUEST_PAYER, define who will pay to request, look https://docs.aws.amazon.com/AmazonS3/latest/userguide/RequesterPaysBuckets.html for details, possible values requester, if empty then bucket owner
  debug: false # S3_DEBUG
EOF
	export CLICKHOUSE_BACKUP_CONFIG="$clickhouse_backup_config"
}

function getToolConfigValue() {
	local var=$1
	cat "$toolConfig" | grep "$var" | awk '{print $NF}'
}

function set_clickhouse_backup_config_env() {
	toolConfig=/etc/datasafed/datasafed.conf
	if [ ! -f ${toolConfig} ]; then
		DP_error_log "Config file not found: ${toolConfig}"
		exit 1
	fi

	local provider=""
	local access_key_id=""
	local secret_access_key=""
	local region=""
	local endpoint=""
	local bucket=""

	IFS=$'\n'
	for line in $(cat ${toolConfig}); do
		line=$(eval echo $line)
		if [[ $line == "access_key_id"* ]]; then
			access_key_id=$(getToolConfigValue "$line")
		elif [[ $line == "secret_access_key"* ]]; then
			secret_access_key=$(getToolConfigValue "$line")
		elif [[ $line == "region"* ]]; then
			region=$(getToolConfigValue "$line")
		elif [[ $line == "endpoint"* ]]; then
			endpoint=$(getToolConfigValue "$line")
		elif [[ $line == "root"* ]]; then
			bucket=$(getToolConfigValue "$line")
		elif [[ $line == "chunk_size"* ]]; then
			chunk_size=$(getToolConfigValue "$line")
		elif [[ $line == "provider"* ]]; then
			provider=$(getToolConfigValue "$line")
		fi
	done

	if [[ ! $endpoint =~ ^https?:// ]]; then
		endpoint="https://${endpoint}"
	fi

	if [[ "$provider" == "Alibaba" ]]; then
		regex='https?:\/\/oss-(.*?)\.aliyuncs\.com'
		if [[ "$endpoint" =~ $regex ]]; then
			region="${BASH_REMATCH[1]}"
			DP_log "Extract region from $endpoint-> $region"
		else
			DP_log "Failed to extract region from endpoint: $endpoint"
		fi
	elif [[ "$provider" == "TencentCOS" ]]; then
		regex='https?:\/\/cos\.(.*?)\.myqcloud\.com'
		if [[ "$endpoint" =~ $regex ]]; then
			region="${BASH_REMATCH[1]}"
			DP_log "Extract region from $endpoint-> $region"
		else
			DP_log "Failed to extract region from endpoint: $endpoint"
		fi
	elif [[ "$provider" == "Minio" || "$provider" == "RustFS" ]]; then
		export S3_FORCE_PATH_STYLE=true
	else
		echo "Unsupported provider: $provider"
	fi

	export S3_ACCESS_KEY="${access_key_id}"
	export S3_SECRET_KEY="${secret_access_key}"
	export S3_REGION="${region}"
	export S3_ENDPOINT="${endpoint}"
	export S3_BUCKET="${bucket}"
	export S3_PART_SIZE="${chunk_size}"
	export S3_PATH="${DP_BACKUP_BASE_PATH}"

	export RESTORE_SCHEMA_ON_CLUSTER="${INIT_CLUSTER_NAME}"
	export CLICKHOUSE_HOST="${DP_DB_HOST}"
	export CLICKHOUSE_USERNAME="${CLICKHOUSE_ADMIN_USER}"
	export CLICKHOUSE_PASSWORD="${CLICKHOUSE_ADMIN_PASSWORD}"
	if [[ "${TLS_ENABLED:-false}" == "true" ]]; then
		export CLICKHOUSE_SECURE=true
		export CLICKHOUSE_PORT="${CLICKHOUSE_TCP_SECURE_PORT:-9440}"
		export CLICKHOUSE_TLS_CA="/etc/pki/tls/ca.pem"
		export CLICKHOUSE_TLS_CERT="/etc/pki/tls/cert.pem"
		export CLICKHOUSE_TLS_KEY="/etc/pki/tls/key.pem"
	fi
	DP_log "Dynamic environment variables for clickhouse-backup have been set."
}

function ch_query() {
	local query="$1"
	local ch_port="${CLICKHOUSE_PORT:-9000}"
	local ch_args=(--user "${CLICKHOUSE_USERNAME}" --password "${CLICKHOUSE_PASSWORD}" --host "${CLICKHOUSE_HOST}" --port "$ch_port" --connect_timeout=5)
	clickhouse-client "${ch_args[@]}" --query "$query"
}

function download_backup() {
	local backup_name="$1"
	clickhouse-backup download "$backup_name" || {
		DP_error_log "Failed to download backup '$backup_name'"
		return 1
	}
	DP_log "Downloading backup '$backup_name' from remote storage..."
	return 0
}

function fetch_backup() {
	local backup_name=$1
	if clickhouse-backup list local | grep -q "$backup_name"; then
		DP_log "Local backup '$backup_name' found."
	else
		DP_log "Local backup '$backup_name' not found. Downloading..."
		download_backup "$backup_name" || {
			DP_error_log "Failed to download backup '$backup_name'. Exiting."
			exit 1
		}
		clickhouse-backup list local | grep -q "$backup_name" || {
			DP_error_log "Backup '$backup_name' not found after download. Exiting."
			exit 1
		}
	fi
	DP_log "Backup '$backup_name' is available locally."
}

function delete_backups_except() {
	local latest_backup=$1
	DP_log "delete backup except $latest_backup"
	backup_list=$(clickhouse-backup list)
	echo "$backup_list" | awk '/local/ {print $1}' | while IFS= read -r backup_name; do
		if [ "$backup_name" != "$latest_backup" ]; then
			clickhouse-backup delete local "$backup_name" || {
				DP_error_log "Clickhouse-backup delete local backup $backup_name FAILED"
			}
		fi
	done
}
