#!/bin/bash
# shellcheck disable=SC2086

function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
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

function buildJsonString() {
    local jsonString=${1}
    local key=${2}
    local value=${3}
    if [ ! -z "$jsonString" ];then
       jsonString="${jsonString},"
    fi
    echo "${jsonString}\"${key}\":\"${value}\""
}

# Save backup status info file for syncing progress.
# timeFormat: %Y-%m-%dT%H:%M:%SZ
function DP_save_backup_status_info() {
    export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
    export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

    local totalSize=$1
    local startTime=$2
    local stopTime=$3
    local timeZone=$4
    local extras=$5
    local timeZoneStr=""
    if [ ! -z ${timeZone} ]; then
       timeZoneStr=",\"timeZone\":\"${timeZone}\""
    fi
    if [ -z "${stopTime}" ];then
      echo "{\"totalSize\":\"${totalSize}\"}" > ${DP_BACKUP_INFO_FILE}
    elif [ -z "${startTime}" ];then
      echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"end\":\"${stopTime}\"${timeZoneStr}}}" > ${DP_BACKUP_INFO_FILE}
    else
      echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"start\":\"${startTime}\",\"end\":\"${stopTime}\"${timeZoneStr}}}" > ${DP_BACKUP_INFO_FILE}
    fi
}

function getToolConfigValue() {
  local var=$1
  cat "$toolConfig" | grep "$var" | awk '{print $NF}'
}

function set_backup_config_env() {
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
  elif [[ "$provider" == "Minio" ]]; then
    export S3_FORCE_PATH_STYLE="true"
  else
    echo "Unsupported provider: $provider"
  fi
  backup_path=$(dirname "$DP_BACKUP_BASE_PATH")

  export S3_ACCESS_KEY="${access_key_id}"
  export S3_SECRET_KEY="${secret_access_key}"
  export S3_REGION="${region}"
  export S3_ENDPOINT="${endpoint}"
  export S3_BUCKET="${bucket}"
  export S3_PREFIX="${backup_path#/}/$PBM_BACKUP_DIR_NAME"

  DP_log "storage config have been extracted."
}

# config backup agent
generate_endpoints() {
    local fqdns=$1
    local port=$2

    if [ -z "$fqdns" ]; then
        echo "ERROR: No FQDNs provided for endpoints." >&2
        exit 1
    fi

    IFS=',' read -ra fqdn_array <<< "$fqdns"
    local endpoints=()

    for fqdn in "${fqdn_array[@]}"; do
        trimmed_fqdn=$(echo "$fqdn" | xargs)
        if [[ -n "$trimmed_fqdn" ]]; then
            endpoints+=("${trimmed_fqdn}:${port}")
        fi
    done

    IFS=','; echo "${endpoints[*]}"
}

function export_pbm_env_vars() {
  export PBM_AGENT_MONGODB_USERNAME="$MONGODB_USER"
  export PBM_AGENT_MONGODB_PASSWORD="$MONGODB_PASSWORD"

  cfg_server_endpoints="$(generate_endpoints "$CFG_SERVER_POD_FQDN_LIST" "$CFG_SERVER_INTERNAL_PORT")"
  export PBM_MONGODB_URI="mongodb://$PBM_AGENT_MONGODB_USERNAME:$PBM_AGENT_MONGODB_PASSWORD@$cfg_server_endpoints/?authSource=admin&replSetName=$CFG_SERVER_REPLICA_SET_NAME"
}

function export_pbm_env_vars_for_rs() {
  export PBM_AGENT_MONGODB_USERNAME="$MONGODB_USER"
  export PBM_AGENT_MONGODB_PASSWORD="$MONGODB_PASSWORD"

  mongodb_endpoints="$(generate_endpoints "$MONGODB_POD_FQDN_LIST" "$KB_SERVICE_PORT")"
  export PBM_MONGODB_URI="mongodb://$PBM_AGENT_MONGODB_USERNAME:$PBM_AGENT_MONGODB_PASSWORD@$mongodb_endpoints/?authSource=admin&replSetName=$MONGODB_REPLICA_SET_NAME"
}

function write_pbm_storage_config_file() {
  local file=$1
  if [ -z "$file" ]; then
    echo "ERROR: PBM storage config file path is empty"
    exit 1
  fi
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
storage:
  type: s3
  s3:
    region: ${S3_REGION}
    bucket: ${S3_BUCKET}
    prefix: ${S3_PREFIX}
    endpointUrl: ${S3_ENDPOINT}
    forcePathStyle: ${S3_FORCE_PATH_STYLE:-false}
    credentials:
      access-key-id: ${S3_ACCESS_KEY}
      secret-access-key: ${S3_SECRET_KEY}
restore:
  numDownloadWorkers: ${PBM_RESTORE_DOWNLOAD_WORKERS:-4}
backup:
  timeouts:
    startingStatus: 60
EOF
}

function target_syncer_host() {
  if [ -n "${DP_DB_HOST:-}" ] && [ -z "${DP_TARGET_POD_NAME:-}" ]; then
    echo "$DP_DB_HOST"
    return
  fi

  local pod_name="${DP_TARGET_POD_NAME:-${POD_NAME:-}}"
  local component_name="${CLUSTER_COMPONENT_NAME:-${KB_CLUSTER_COMP_NAME:-}}"
  local namespace="${CLUSTER_NAMESPACE:-${KB_NAMESPACE:-${POD_NAMESPACE:-}}}"
  local cluster_domain="${KUBERNETES_CLUSTER_DOMAIN:-cluster.local}"
  if [ -z "$pod_name" ] || [ -z "$component_name" ] || [ -z "$namespace" ]; then
    echo "ERROR: Cannot build target syncer host, pod=$pod_name component=$component_name namespace=$namespace" >&2
    exit 1
  fi
  echo "${pod_name}.${component_name}-headless.${namespace}.svc.${cluster_domain}"
}

function syncerctl_cmd() {
  local host
  host=$(target_syncer_host)
  local port="${SYNCER_SERVICE_PORT:-3601}"
  syncerctl --host "$host" --port "$port" "$@"
}

function expected_restore_shard_names_json() {
  local shardsvr_names="${MONGODB_SHARD_REPLICA_SET_NAME_LIST:-}"
  if [ -z "$shardsvr_names" ]; then
    echo "[]"
    return
  fi

  local -a shardsvr_array
  IFS="." read -r -a shardsvr_array <<< "$shardsvr_names"
  local shardsvr_count=${#shardsvr_array[@]}
  local json="["
  local i
  for i in "${!shardsvr_array[@]}"; do
    local shard_name
    if [ "$shardsvr_count" -gt 1 ]; then
      shard_name="$CLUSTER_NAME-${shardsvr_array[i]%%@*}"
    else
      shard_name="${shardsvr_array[i]%%,*}"
    fi
    if [ -z "$shard_name" ]; then
      continue
    fi
    local escaped="$shard_name"
    escaped=${escaped//\\/\\\\}
    escaped=${escaped//\"/\\\"}
    if [ "$json" != "[" ]; then
      json="$json,"
    fi
    json="$json\"$escaped\""
  done
  echo "$json]"
}

function wait_for_mongos_router_ready() {
  if [ -z "${MONGOS_INTERNAL_HOST:-}" ] || [ -z "${MONGOS_INTERNAL_PORT:-}" ]; then
    echo "ERROR: Cannot wait for mongos router, host=${MONGOS_INTERNAL_HOST:-} port=${MONGOS_INTERNAL_PORT:-}"
    exit 1
  fi

  local client="mongosh"
  if ! command -v mongosh >/dev/null 2>&1; then
    client="mongo"
  fi

  local expected_shards
  expected_shards=$(expected_restore_shard_names_json)
  local max_retries=${MONGOS_ROUTE_WAIT_MAX_RETRIES:-90}
  local retry_interval=${MONGOS_ROUTE_WAIT_INTERVAL_SECONDS:-2}
  local settle_seconds=${MONGOS_ROUTE_SETTLE_SECONDS:-20}
  local eval_timeout=${MONGOS_ROUTE_EVAL_TIMEOUT_SECONDS:-15}
  local attempt=1
  local script
  script=$(cat <<EOF
var expected = $expected_shards;
var ping = db.adminCommand({ ping: 1 });
if (!ping.ok) {
  print('ping failed: ' + JSON.stringify(ping));
  quit(2);
}
var flush = db.adminCommand({ flushRouterConfig: 1 });
if (!flush.ok) {
  print('flushRouterConfig failed: ' + JSON.stringify(flush));
  quit(3);
}
var shards = db.adminCommand({ listShards: 1 });
if (!shards.ok) {
  print('listShards failed: ' + JSON.stringify(shards));
  quit(4);
}
var found = {};
for (var i = 0; i < (shards.shards || []).length; i++) {
  var shard = shards.shards[i];
  if (shard.state === 1) {
    found[shard._id] = shard.host;
  }
}
var missing = [];
for (var j = 0; j < expected.length; j++) {
  if (!found[expected[j]]) {
    missing.push(expected[j]);
  }
}
if (missing.length > 0) {
  print('missing shards: ' + missing.join(','));
  quit(5);
}
var configShardCursorCount = db.getSiblingDB('config').shards.find({ state: 1 }).limit(Math.max(expected.length, 1)).itcount();
if (configShardCursorCount < Math.max(expected.length, 1)) {
  print('config.shards cursor saw ' + configShardCursorCount + ' active shards, expected at least ' + Math.max(expected.length, 1));
  quit(6);
}
print('router ready: ' + JSON.stringify(found));
EOF
)

  while [ "$attempt" -le "$max_retries" ]; do
    local result
    local timeout_cmd=()
    if command -v timeout >/dev/null 2>&1; then
      timeout_cmd=(timeout -k 2s "${eval_timeout}s")
    fi
    set +e
    result=$("${timeout_cmd[@]}" "$client" --host "$MONGOS_INTERNAL_HOST" --port "$MONGOS_INTERNAL_PORT" -u "$MONGODB_USER" -p "$MONGODB_PASSWORD" --authenticationDatabase admin --quiet --eval "$script" 2>&1)
    local exit_code
    exit_code=$?
    set -e
    if [ "$exit_code" -eq 0 ]; then
      echo "INFO: Mongos router is ready: $result"
      if [ "$settle_seconds" -gt 0 ]; then
        echo "INFO: Waiting ${settle_seconds}s for mongos router cache to settle."
        sleep "$settle_seconds"
      fi
      return 0
    fi
    echo "INFO: Waiting for mongos router to be ready... (attempt $attempt/$max_retries): $result"
    attempt=$((attempt+1))
    sleep "$retry_interval"
  done

  echo "ERROR: Mongos router failed to become ready after $max_retries attempts."
  exit 1
}

function configure_syncer_backup() {
  local cnf_file="${MOUNT_DIR:-/tmp}/tmp/pbm_syncer_storage.yaml"
  write_pbm_storage_config_file "$cnf_file"
  echo "INFO: Configuring PBM storage through syncer on $(target_syncer_host)..."
  syncerctl_cmd backup configure --file "$cnf_file"
}

function ensure_restore_coord_storage_config() {
  local cnf_file="${MOUNT_DIR:-/tmp}/tmp/pbm_restore_syncer_storage.yaml"
  local coord_cm="${CLUSTER_NAME}-restore-coord"
  local namespace="${CLUSTER_NAMESPACE:-${KB_NAMESPACE:-${POD_NAMESPACE:-}}}"
  if [ -z "$CLUSTER_NAME" ] || [ -z "$namespace" ]; then
    echo "ERROR: Cannot prepare restore coord ConfigMap, cluster=$CLUSTER_NAME namespace=$namespace"
    exit 1
  fi
  write_pbm_storage_config_file "$cnf_file"
  if ! kubectl get configmap "$coord_cm" -n "$namespace" >/dev/null 2>&1; then
    kubectl create configmap "$coord_cm" -n "$namespace" >/dev/null 2>&1 || kubectl get configmap "$coord_cm" -n "$namespace" >/dev/null
  fi
  kubectl label configmap "$coord_cm" -n "$namespace" app.kubernetes.io/instance="$CLUSTER_NAME" --overwrite >/dev/null
  local cfg_json
  cfg_json=$(jq -Rs . < "$cnf_file")
  kubectl patch configmap "$coord_cm" -n "$namespace" --type=merge -p "{\"data\":{\"pbm-storage-config\":$cfg_json}}" >/dev/null
  echo "INFO: Restore coord storage config prepared in $namespace/$coord_cm."
}

function wait_for_syncer_backup_completion() {
  local backup_name=$1
  local max_retries=${SYNCER_PBM_WAIT_MAX_RETRIES:-720}
  local retry_interval=${SYNCER_PBM_WAIT_INTERVAL_SECONDS:-5}
  local attempt=0
  describe_result=""
  while true; do
    describe_result=$(syncerctl_cmd backup status --op-id "$backup_name")
    local found
    local status
    found=$(echo "$describe_result" | jq -r '.found // false')
    status=$(echo "$describe_result" | jq -r '.status // empty')
    echo "INFO: Backup $backup_name status: found=$found status=$status"
    if [ "$found" = "true" ] && [ "$status" = "done" ]; then
      return 0
    fi
    if [ "$status" = "error" ] || [ "$status" = "failed" ]; then
      echo "ERROR: Backup $backup_name failed: $(echo "$describe_result" | jq -r '.error // empty')"
      exit 1
    fi
    attempt=$((attempt+1))
    if [ $attempt -gt $max_retries ]; then
      echo "ERROR: Backup $backup_name did not complete after $max_retries retries"
      exit 1
    fi
    sleep "$retry_interval"
  done
}

function wait_for_syncer_restore_completion() {
  local coord_cm="${CLUSTER_NAME}-restore-coord"
  local namespace="${CLUSTER_NAMESPACE:-${KB_NAMESPACE:-${POD_NAMESPACE:-}}}"
  local max_retries=${SYNCER_RESTORE_WAIT_MAX_RETRIES:-7200}
  local retry_interval=${SYNCER_RESTORE_WAIT_INTERVAL_SECONDS:-1}
  local attempt=0
  local last_phase=""
  local last_op_id=""
  while true; do
    set +e
    local cm_json
    cm_json=$(kubectl get configmap "$coord_cm" -n "$namespace" -o json 2>/dev/null)
    local get_exit=$?
    set -e
    if [ $get_exit -ne 0 ]; then
      if [ "$last_phase" = "done" ] || [ "$last_phase" = "finalizing" ]; then
        echo "INFO: Restore coord ConfigMap was removed after phase=$last_phase; treating restore as completed."
        return 0
      fi
      if [ -n "$last_op_id" ]; then
        set +e
        local restore_status
        restore_status=$(syncerctl_cmd restore status --op-id "$last_op_id" 2>/dev/null)
        local status_exit=$?
        set -e
        if [ $status_exit -eq 0 ]; then
          local status
          status=$(echo "$restore_status" | jq -r '.status // empty')
          if [ "$status" = "done" ]; then
            echo "INFO: Restore $last_op_id completed after coord cleanup."
            return 0
          fi
          if [ "$status" = "failed" ] || [ "$status" = "error" ]; then
            echo "ERROR: Syncer restore failed after coord cleanup: $(echo "$restore_status" | jq -r '.error // empty')"
            exit 1
          fi
        fi
      fi
      echo "INFO: Waiting for restore coord ConfigMap $namespace/$coord_cm..."
    else
      local phase
      local op_id
      local err_msg
      local state_json
      state_json=$(echo "$cm_json" | jq -r '.data.state // empty')
      if [ -n "$state_json" ]; then
        phase=$(echo "$state_json" | jq -r '.phase // empty')
        op_id=$(echo "$state_json" | jq -r '.op_id // empty')
        err_msg=$(echo "$state_json" | jq -r '.error // empty')
      else
        phase=""
        op_id=""
        err_msg=""
      fi
      if [ -z "$phase" ]; then
        phase=$(echo "$cm_json" | jq -r '.metadata.annotations["restore.syncer/phase"] // empty')
      fi
      if [ -z "$op_id" ]; then
        op_id=$(echo "$cm_json" | jq -r '.metadata.annotations["restore.syncer/op-id"] // empty')
      fi
      if [ -z "$err_msg" ]; then
        err_msg=$(echo "$cm_json" | jq -r '.metadata.annotations["restore.syncer/error"] // empty')
      fi
      if [ -n "$op_id" ]; then
        last_op_id="$op_id"
      fi
      if [ -n "$phase" ] && [ "$phase" != "$last_phase" ]; then
        echo "INFO: Restore coord phase=$phase op_id=$op_id"
        last_phase="$phase"
      fi
      if [ "$phase" = "done" ]; then
        return 0
      fi
      if [ "$phase" = "failed" ]; then
        echo "ERROR: Syncer restore failed: $err_msg"
        exit 1
      fi
    fi
    attempt=$((attempt+1))
    if [ $attempt -gt $max_retries ]; then
      echo "ERROR: Restore did not complete after $max_retries retries"
      exit 1
    fi
    sleep "$retry_interval"
  done
}

function sync_pbm_storage_config() {
  echo "INFO: Checking if PBM storage config exists"
  pbm_config_exists=true
  check_config=$(pbm config --mongodb-uri "$PBM_MONGODB_URI" -o json) || {
    pbm_config_exists=false
    echo "INFO: PBM storage config does not exist."
  }
  if [ "$pbm_config_exists" = "true" ]; then
    # check_config=$(pbm config --mongodb-uri "$PBM_MONGODB_URI" -o json)
    current_endpoint=$(echo "$check_config" | jq -r '.storage.s3.endpointUrl')
    current_region=$(echo "$check_config" | jq -r '.storage.s3.region')
    current_bucket=$(echo "$check_config" | jq -r '.storage.s3.bucket')
    current_prefix=$(echo "$check_config" | jq -r '.storage.s3.prefix')
    echo "INFO: Current PBM storage endpoint: $current_endpoint"
    echo "INFO: Current PBM storage region: $current_region"
    echo "INFO: Current PBM storage bucket: $current_bucket"
    echo "INFO: Current PBM storage prefix: $current_prefix"
    if [ "$current_prefix" = "$S3_PREFIX" ] && [ "$current_region" = "$S3_REGION" ] && [ "$current_bucket" = "$S3_BUCKET" ] && [ "$current_endpoint" = "$S3_ENDPOINT" ]; then
      echo "INFO: PBM storage config already exists."
    else
      pbm_config_exists=false
    fi
  fi
  if [ "$pbm_config_exists" = "false" ]; then
    cat <<EOF | pbm config --mongodb-uri "$PBM_MONGODB_URI" --file /dev/stdin > /dev/null
storage:
  type: s3
  s3:
    region: ${S3_REGION}
    bucket: ${S3_BUCKET}
    prefix: ${S3_PREFIX}
    endpointUrl: ${S3_ENDPOINT}
    forcePathStyle: ${S3_FORCE_PATH_STYLE:-false}
    credentials:
      access-key-id: ${S3_ACCESS_KEY}
      secret-access-key: ${S3_SECRET_KEY}
restore:
  numDownloadWorkers: ${PBM_RESTORE_DOWNLOAD_WORKERS:-4}
backup:
  timeouts:
    startingStatus: 60
EOF
    sleep 5
    echo "INFO: PBM storage configuration completed."
  fi
}

function print_pbm_logs_by_event() {
  local pbm_event=$1
  # echo "INFO: Printing PBM logs by event: $pbm_event"
  # shellcheck disable=SC2328
  local pbm_logs=$(pbm logs -e $pbm_event --tail 200 --mongodb-uri "$PBM_MONGODB_URI" > /dev/null)
  local purged_logs=$(echo "$pbm_logs" | awk -v start="$PBM_LOGS_START_TIME" '$1 >= start')
  if [ -z "$purged_logs" ]; then
    return
  fi
  echo "$purged_logs"
  # echo "INFO: PBM logs by event: $pbm_event printed."
}

function print_pbm_tail_logs() {
  echo "INFO: Printing PBM tail logs"
  pbm logs --tail 20 --mongodb-uri "$PBM_MONGODB_URI"
}

function handle_backup_exit() {
  exit_code=$?
  set +e
  if [ $exit_code -ne 0 ]; then
    print_pbm_tail_logs

    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

function handle_restore_exit() {
  exit_code=$?
  set +e
  if [ $exit_code -ne 0 ]; then
    print_pbm_tail_logs

    echo "failed with exit code $exit_code"
    exit 1
  fi
}

function handle_pitr_exit() {
  exit_code=$?
  set +e
  if [[ "$PBM_DISABLE_PITR_WHEN_EXIT" == "true" ]]; then
    disable_pitr
  fi

  if [ $exit_code -ne 0 ]; then
    print_pbm_tail_logs

    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

function wait_for_other_operations() {
  status_result=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json) || {
    echo "INFO: PBM is not configured."
    return
  }
  local except_type=$1
  local running_status=$(echo "$status_result" | jq -r '.running')
  local retry_count=0
  local max_retries=60
  while [ -n "$running_status" ] && [ "$running_status" != "{}" ] && [ $retry_count -lt $max_retries ]; do
    retry_count=$((retry_count+1))
    local running_type=$(echo "$running_status" | jq -r '.type')
    if [ -n "$running_type" ] && [ "$running_type" = "$except_type" ]; then
      break
    fi
    echo "INFO: Other operation $running_type is running, waiting... ($retry_count/$max_retries)"
    sleep 5
    running_status=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.running')
  done
  if [ $retry_count -ge $max_retries ]; then
    echo "ERROR: Other operations are still running after $max_retries retries"
    exit 1
  fi
}

function export_logs_start_time_env() {
  local logs_start_time=$(date +"%Y-%m-%dT%H:%M:%SZ")
  export PBM_LOGS_START_TIME="${logs_start_time}"
}

function sync_pbm_config_from_storage() {
  echo "INFO: Syncing PBM config from storage..."

  wait_for_other_operations

  pbm config --force-resync --mongodb-uri "$PBM_MONGODB_URI"
  # print_pbm_logs_by_event "resync"

  # resync wait flag might don't work
  wait_for_other_operations

  echo "INFO: PBM config synced from storage."
}

function wait_for_backup_completion() {
  describe_result=""
  local retry_interval=5
  local attempt=1
  local max_retries=12
  set +e
  while true; do
    describe_result=$(pbm describe-backup --mongodb-uri "$PBM_MONGODB_URI" "$backup_name" -o json 2>&1)
    if [ $? -eq 0 ] && [ -n "$describe_result" ]; then
      backup_status=$(echo "$describe_result" | jq -r '.status')
      if [ "$backup_status" = "starting" ] || [ "$backup_status" = "running" ]; then
        echo "INFO: Backup status is $backup_status, retrying in ${retry_interval}s..."
      elif [ "$backup_status" = "" ]; then
        echo "INFO: Backup status is $backup_status, retrying in ${retry_interval}s..."
        attempt=$((attempt+1))
      elif [ "$backup_status" = "done" ]; then
        echo "INFO: Backup status is done."
        break
      else
        echo "ERROR: Backup failed with status: $backup_status"
        exit 1
      fi
    elif echo "$describe_result" | grep -q "not found"; then
      echo "INFO: Backup metadata not found, retrying in ${retry_interval}s..."
      attempt=$((attempt+1))
    else
      echo "ERROR: Unexpected: $describe_result"
      exit 1
    fi
    sleep $retry_interval
    if [ $attempt -gt $max_retries ]; then
      echo "ERROR: Failed to get backup status after $max_retries attempts"
      exit 1
    fi
  done
  set -e

  backup_status=$(echo "$describe_result" | jq -r '.status')
  if [ "$backup_status" != "done" ]; then
      echo "ERROR: Backup did not complete successfully, final status: $backup_status"
      exit 1
  fi
}

function create_restore_signal() {
    phase=$1
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: $dp_cm_name
  namespace: $dp_cm_namespace
  labels:
    app.kubernetes.io/instance: $CLUSTER_NAME
    apps.kubeblocks.io/restore-mongodb-shard: $phase
  ownerReferences:
    - apiVersion: apps.kubeblocks.io/v1
      blockOwnerDeletion: true
      controller: true
      kind: Cluster
      name: $CLUSTER_NAME
      uid: $CLUSTER_UID
EOF
}

function process_restore_start_signal() {
    echo "INFO: Waiting for prepare restore start signal..."
    dp_cm_name="$CLUSTER_NAME-restore-signal"
    dp_cm_namespace="$CLUSTER_NAMESPACE"
    while true; do
        set +e
        kubectl_get_result=$(kubectl get configmap $dp_cm_name -n $dp_cm_namespace -o json 2>&1)
        kubectl_get_exit_code=$?
        set -e
        # Wait for the restore signal ConfigMap to be created or updated
        if [[ "$kubectl_get_exit_code" -ne 0 ]]; then
            if [[ "$kubectl_get_result" == *"not found"* ]]; then
                create_restore_signal "start"
            fi
        else
            annotation_value=$(echo "$kubectl_get_result" | jq -r '.metadata.labels["apps.kubeblocks.io/restore-mongodb-shard"] // empty')
            if [[ "$annotation_value" == "start" ]]; then
                break
            elif [[ "$annotation_value" == "end" ]]; then
                echo "INFO: Restore completed, exiting."
                exit 0
            else
                echo "INFO: Restore start signal is $annotation_value, updating..."
                create_restore_signal "start"
            fi
        fi
        sleep 1
    done
    sleep 5
    echo "INFO: Prepare restore start signal completed."
}

function process_restore_end_signal() {
    echo "INFO: Waiting for prepare restore end signal..."
    sleep 5
    dp_cm_name="$CLUSTER_NAME-restore-signal"
    dp_cm_namespace="$CLUSTER_NAMESPACE"
    while true; do
        set +e
        kubectl_get_result=$(kubectl get configmap $dp_cm_name -n $dp_cm_namespace -o json 2>&1)
        kubectl_get_exit_code=$?
        set -e
        # Wait for the restore signal ConfigMap to be created or updated
        if [[ "$kubectl_get_exit_code" -ne 0 ]]; then
            if [[ "$kubectl_get_result" == *"not found"* ]]; then
                create_restore_signal "end"
            fi
        else
            annotation_value=$(echo "$kubectl_get_result" | jq -r '.metadata.labels["apps.kubeblocks.io/restore-mongodb-shard"] // empty')
            if [[ "$annotation_value" == "end" ]]; then
                break
            else
                echo "INFO: Restore end signal is $annotation_value, updating..."
                create_restore_signal "end"
            fi
        fi
        sleep 1
    done
    echo "INFO: Prepare restore end signal completed."
}

function get_describe_backup_info() {
  describe_result=""
  local max_retries=60
  local retry_interval=5
  local attempt=1
  set +e
  while [ $attempt -le $max_retries ]; do
      describe_result=$(pbm describe-backup --mongodb-uri "$PBM_MONGODB_URI" "$backup_name" -o json 2>&1)
      if [ $? -eq 0 ] && [ -n "$describe_result" ]; then
          break
      elif echo "$describe_result" | grep -q "not found"; then
          echo "INFO: Attempt $attempt: backup $backup_name not found, retrying in ${retry_interval}s..."
          if [ $((attempt % 30)) -eq 29 ]; then
              echo "INFO: Sync PBM config from storage again."
              sync_pbm_config_from_storage
          fi
          sleep $retry_interval
          ((attempt++))
          continue
      else
          echo "ERROR: Failed to get backup metadata: $describe_result"
          exit 1
      fi
  done
  set -e

  if [ -z "$describe_result" ] || echo "$describe_result" | grep -q "not found"; then
      echo "ERROR: Failed to get backup metadata after $max_retries attempts"
      exit 1
  fi
}

function wait_for_restoring() {
  local cnf_file="${MOUNT_DIR}/tmp/pbm_restore.cnf"
  cat <<EOF > ${MOUNT_DIR}/tmp/pbm_restore.cnf
storage:
  type: s3
  s3:
    region: ${S3_REGION}
    bucket: ${S3_BUCKET}
    prefix: ${S3_PREFIX}
    endpointUrl: ${S3_ENDPOINT}
    forcePathStyle: ${S3_FORCE_PATH_STYLE:-false}
    credentials:
      access-key-id: ${S3_ACCESS_KEY}
      secret-access-key: ${S3_SECRET_KEY}
EOF
  local attempt=0
  local max_retries=12
  local try_interval=5
  while true; do
    restore_status=$(pbm describe-restore "$restore_name" -c $cnf_file -o json | jq -r '.status')
    echo "INFO: Restore $restore_name status: $restore_status, retrying in ${try_interval}s..."
    if [ "$restore_status" = "done" ]; then
      rm $cnf_file
      break
    elif [ "$restore_status" = "starting" ] || [ "$restore_status" = "running" ]; then
      sleep $try_interval
    elif [ "$restore_status" = "" ]; then
      sleep $try_interval
      attempt=$((attempt+1))
      if [ $attempt -gt $max_retries ]; then
        echo "ERROR: Restore $restore_name status is still empty after $max_retries retries"
        rm $cnf_file
        exit 1
      fi
    else
      rm $cnf_file
      exit 1
    fi
  done
}