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

# KUBECTL_BIN is the location where the CMPD init-kubectl container copies
# kubectl into the shared data volume. ActionSet jobs that mount the data
# volume and runOnTargetPodNode=true can use this binary.
KUBECTL_DATA_BIN="${MOUNT_DIR}/tmp/bin/kubectl"

# ensure_kubectl makes the kubectl CLI available. It checks PATH first, then
# the data-volume copy placed by CMPD init-kubectl. If neither is available it
# fails with a clear error and does NOT download from the internet, per project
# constraint: no extra self-built images except syncer.
function ensure_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    return 0
  fi
  if [ -x "$KUBECTL_DATA_BIN" ]; then
    export PATH="$(dirname "$KUBECTL_DATA_BIN"):$PATH"
    return 0
  fi

  echo "ERROR: kubectl not found in PATH and not available at ${KUBECTL_DATA_BIN}" >&2
  echo "ERROR: ensure the ActionSet job mounts the data volume and runOnTargetPodNode=true, or use an image that includes kubectl" >&2
  return 1
}

# syncerctl_exec runs syncerctl inside the target MongoDB pod via kubectl exec.
# The MongoDB pod has /tools/syncerctl (copied by init-syncer) and syncer
# listens on 127.0.0.1:3601, so syncerctl uses default host/port.
# DP_TARGET_POD_NAME is injected by KubeBlocks dataprotection. If it is missing
# (e.g. in postReady jobs), the primary pod is resolved from the cluster label.
function syncerctl_exec() {
  ensure_kubectl || exit 1
  resolve_target_pod || exit 1
  kubectl exec -n "$CLUSTER_NAMESPACE" "$DP_TARGET_POD_NAME" -c mongodb -- /tools/syncerctl "$@"
}

# resolve_target_pod ensures DP_TARGET_POD_NAME is set. It prefers the
# KubeBlocks-injected env var and falls back to looking up the pod labelled
# kubeblocks.io/role=primary for this cluster.
function resolve_target_pod() {
  if [ -n "$DP_TARGET_POD_NAME" ]; then
    return 0
  fi
  if [ -z "$CLUSTER_NAME" ] || [ -z "$CLUSTER_NAMESPACE" ]; then
    echo "ERROR: DP_TARGET_POD_NAME is not set and CLUSTER_NAME/CLUSTER_NAMESPACE are missing" >&2
    return 1
  fi
  local retry_count=0
  local max_retries=30
  while [ $retry_count -lt $max_retries ]; do
    DP_TARGET_POD_NAME=$(kubectl get pod -n "$CLUSTER_NAMESPACE" \
      -l "app.kubernetes.io/instance=$CLUSTER_NAME,kubeblocks.io/role=primary" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$DP_TARGET_POD_NAME" ]; then
      export DP_TARGET_POD_NAME
      return 0
    fi
    retry_count=$((retry_count+1))
    echo "INFO: primary pod for $CLUSTER_NAME not ready yet, retrying... ($retry_count/$max_retries)" >&2
    sleep 2
  done
  echo "ERROR: cannot find primary pod for cluster $CLUSTER_NAME in namespace $CLUSTER_NAMESPACE" >&2
  return 1
}

# resolve_restore_target_pod ensures DP_TARGET_POD_NAME points at the pod that
# should drive a restore. For a sharded cluster this is the config-server
# primary; for a replicaset it is the replicaset primary.
#
# ActionSet restore postReady jobs do not inherit CMPD vars, so CLUSTER_NAME and
# CLUSTER_NAMESPACE may be unset. In that case we derive them from the
# KubeBlocks-injected DP_DB_HOST (which names the restore-driving pod) and
# POD_NAMESPACE (downward API injected into every job pod).
function resolve_restore_target_pod() {
  if [ -n "$DP_TARGET_POD_NAME" ] && [ -n "${CLUSTER_NAMESPACE:-}" ]; then
    return 0
  fi

  if [ -z "${DP_TARGET_POD_NAME:-}" ] && [ -n "${DP_DB_HOST:-}" ]; then
    DP_TARGET_POD_NAME=${DP_DB_HOST%%.*}
    export DP_TARGET_POD_NAME
  fi

  if [ -z "${CLUSTER_NAMESPACE:-}" ] && [ -n "${POD_NAMESPACE:-}" ]; then
    CLUSTER_NAMESPACE=$POD_NAMESPACE
    export CLUSTER_NAMESPACE
  fi

  if [ -z "${CLUSTER_NAME:-}" ] && [ -n "${DP_TARGET_POD_NAME:-}" ]; then
    # Sharded restore: the driving pod is <cluster>-config-server-0.
    CLUSTER_NAME=${DP_TARGET_POD_NAME%-config-server-0}
    export CLUSTER_NAME
  fi

  if [ -n "$DP_TARGET_POD_NAME" ] && [ -n "${CLUSTER_NAMESPACE:-}" ]; then
    return 0
  fi

  if [ -z "$CLUSTER_NAME" ] || [ -z "$CLUSTER_NAMESPACE" ]; then
    echo "ERROR: DP_TARGET_POD_NAME is not set and CLUSTER_NAME/CLUSTER_NAMESPACE are missing" >&2
    return 1
  fi
  local selector="app.kubernetes.io/instance=$CLUSTER_NAME,kubeblocks.io/role=primary"
  if [ -n "${CFG_SERVER_REPLICA_SET_NAME:-}" ]; then
    # KubeBlocks v1 uses apps.kubeblocks.io/component-name for the component
    # short name; app.kubernetes.io/component is the compDefName.
    selector="${selector},apps.kubeblocks.io/component-name=$CFG_SERVER_REPLICA_SET_NAME"
  fi
  local retry_count=0
  local max_retries=30
  while [ $retry_count -lt $max_retries ]; do
    DP_TARGET_POD_NAME=$(kubectl get pod -n "$CLUSTER_NAMESPACE" \
      -l "$selector" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$DP_TARGET_POD_NAME" ]; then
      export DP_TARGET_POD_NAME
      return 0
    fi
    retry_count=$((retry_count+1))
    echo "INFO: restore target pod for $CLUSTER_NAME not ready yet, retrying... ($retry_count/$max_retries)" >&2
    sleep 2
  done
  echo "ERROR: cannot find restore target pod for cluster $CLUSTER_NAME in namespace $CLUSTER_NAMESPACE" >&2
  return 1
}

# syncerctl_restore_exec runs syncerctl inside the restore-driving pod (config-
# server primary for sharded clusters, replicaset primary otherwise).
function syncerctl_restore_exec() {
  ensure_kubectl || exit 1
  resolve_restore_target_pod || exit 1
  kubectl exec -n "$CLUSTER_NAMESPACE" "$DP_TARGET_POD_NAME" -c mongodb -- /tools/syncerctl "$@"
}

# syncerctl_backup_start triggers a backup via syncer and returns the JSON response.
function syncerctl_backup_start() {
  local backup_type="$1"
  local compression="$2"
  syncerctl_exec backup start --type "$backup_type" --compression "$compression"
}

# syncerctl_backup_status polls backup status by op_id.
function syncerctl_backup_status() {
  local op_id="$1"
  syncerctl_exec backup status --op-id "$op_id"
}

# syncerctl_restore_start triggers a restore via syncer and returns the JSON response.
function syncerctl_restore_start() {
  local backup_name="$1"
  shift
  syncerctl_restore_exec restore start --backup-name "$backup_name" "$@"
}

# syncerctl_restore_status polls restore status by op_id.
function syncerctl_restore_status() {
  local op_id="$1"
  syncerctl_restore_exec restore status --op-id "$op_id"
}

# ensure_restore_cluster_env fills CLUSTER_NAME, CLUSTER_NAMESPACE, and
# DP_TARGET_POD_NAME when CMPD vars are not inherited by ActionSet restore jobs.
# KubeBlocks injects DP_DB_HOST (FQDN of the restore-driving pod) and POD_NAMESPACE
# into restore postReady job pods.
function ensure_restore_cluster_env() {
  if [ -z "${DP_TARGET_POD_NAME:-}" ] && [ -n "${DP_DB_HOST:-}" ]; then
    DP_TARGET_POD_NAME=${DP_DB_HOST%%.*}
    export DP_TARGET_POD_NAME
  fi
  if [ -z "${CLUSTER_NAMESPACE:-}" ] && [ -n "${POD_NAMESPACE:-}" ]; then
    CLUSTER_NAMESPACE=$POD_NAMESPACE
    export CLUSTER_NAMESPACE
  fi
  if [ -z "${CLUSTER_NAME:-}" ] && [ -n "${DP_TARGET_POD_NAME:-}" ]; then
    # The driving pod for a sharded restore is <cluster>-config-server-0.
    CLUSTER_NAME=${DP_TARGET_POD_NAME%-config-server-0}
    export CLUSTER_NAME
  fi
}


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

function normalizeBoolValue() {
  local value
  value=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  case "$value" in
    true | 1 | yes | y | on)
      echo "true"
      ;;
    false | 0 | no | n | off)
      echo "false"
      ;;
    *)
      echo "$value"
      ;;
  esac
}

function set_backup_config_env() {
  toolConfig=${DATASAFED_CONFIG_FILE:-/etc/datasafed/datasafed.conf}
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
  local force_path_style=""

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
    elif [[ $line == "force_path_style"* ]]; then
      force_path_style=$(getToolConfigValue "$line")
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
  if [ -n "$force_path_style" ]; then
    export S3_FORCE_PATH_STYLE="$(normalizeBoolValue "$force_path_style")"
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
    current_force_path_style=$(echo "$check_config" | jq -r '.storage.s3.forcePathStyle')
    echo "INFO: Current PBM storage endpoint: $current_endpoint"
    echo "INFO: Current PBM storage region: $current_region"
    echo "INFO: Current PBM storage bucket: $current_bucket"
    echo "INFO: Current PBM storage prefix: $current_prefix"
    echo "INFO: Current PBM storage forcePathStyle: $current_force_path_style"
    if [ "$current_prefix" = "$S3_PREFIX" ] && [ "$current_region" = "$S3_REGION" ] && [ "$current_bucket" = "$S3_BUCKET" ] && [ "$current_endpoint" = "$S3_ENDPOINT" ] && [ "$current_force_path_style" = "${S3_FORCE_PATH_STYLE:-false}" ]; then
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
pitr:
  enabled: false
EOF
    sleep 5
    echo "INFO: PBM storage configuration completed."
  fi
}

# pbm_storage_config_yaml prints the PBM storage config (with PITR disabled) to
# stdout. The restore prepareData jobs write this YAML into the restore-coord
# ConfigMap so the syncer leader can apply it before starting PBM restore.
function pbm_storage_config_yaml() {
  cat <<EOF
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
pitr:
  enabled: false
EOF
}

# fqdns_to_pod_names extracts the pod name portion from a comma-separated list
# of Kubernetes pod FQDNs (<pod>.<service>.<namespace>.svc).
function fqdns_to_pod_names() {
  local fqdns="$1"
  local out=""
  local sep=""
  local fqdn
  IFS=',' read -ra fqdn_array <<< "$fqdns"
  for fqdn in "${fqdn_array[@]}"; do
    fqdn=$(echo "$fqdn" | xargs)
    if [ -z "$fqdn" ]; then
      continue
    fi
    local pod_name="${fqdn%%.*}"
    if [ -n "$pod_name" ]; then
      out="${out}${sep}${pod_name}"
      sep=","
    fi
  done
  echo "$out"
}

# merge_members combines two comma-separated member lists, removing duplicates.
function merge_members() {
  local existing="$1"
  local new="$2"
  local seen=""
  local out=""
  local sep=""
  local m
  for m in $(echo "$existing" | tr ',' '\n'; echo "$new" | tr ',' '\n'); do
    m=$(echo "$m" | xargs)
    if [ -z "$m" ]; then
      continue
    fi
    if [[ "$seen" == *"|$m|"* ]]; then
      continue
    fi
    seen="${seen}|${m}|"
    out="${out}${sep}${m}"
    sep=","
  done
  echo "$out"
}

# ensure_restore_coord creates or patches the restore-coord ConfigMap with the
# supplied expected member pod names and PBM storage config YAML. Multiple
# component prepareData jobs can call this concurrently; member lists are merged
# and the storage config is overwritten with the same content.
function ensure_restore_coord() {
  local members_csv="$1"
  local storage_config="$2"
  ensure_kubectl || exit 1

  local cm_name="${CLUSTER_NAME}-restore-coord"
  local cm_namespace="${CLUSTER_NAMESPACE}"
  local max_retries=5
  local retry_count=0

  while [ $retry_count -lt $max_retries ]; do
    if kubectl get configmap "$cm_name" -n "$cm_namespace" >/dev/null 2>&1; then
      local current_members
      current_members=$(kubectl get configmap "$cm_name" -n "$cm_namespace" -o jsonpath='{.data.expected-members}' 2>/dev/null || true)
      local merged_members
      merged_members=$(merge_members "$current_members" "$members_csv")
      local patch
      patch=$(jq -n \
        --arg members "$merged_members" \
        --arg storage "$storage_config" \
        '{"data":{"expected-members":$members,"pbm-storage-config":$storage}}')
      if kubectl patch configmap "$cm_name" -n "$cm_namespace" --type merge -p "$patch" >/dev/null 2>&1; then
        echo "INFO: Updated restore-coord ConfigMap ${cm_name} with members: ${merged_members}"
        return 0
      fi
      echo "INFO: restore-coord ConfigMap patch conflict, retrying... ($((retry_count+1))/$max_retries)"
    else
      local indented_config
      indented_config=$(echo "$storage_config" | sed 's/^/    /')
      if kubectl apply -f - <<EOF >/dev/null 2>&1
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${cm_name}
  namespace: ${cm_namespace}
data:
  expected-members: "${members_csv}"
  pbm-storage-config: |
${indented_config}
EOF
      then
        echo "INFO: Created restore-coord ConfigMap ${cm_name} with members: ${members_csv}"
        return 0
      fi
      echo "INFO: restore-coord ConfigMap create race, retrying... ($((retry_count+1))/$max_retries)"
    fi
    retry_count=$((retry_count+1))
    sleep 1
  done

  echo "ERROR: failed to ensure restore-coord ConfigMap ${cm_name} after $max_retries retries" >&2
  return 1
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

