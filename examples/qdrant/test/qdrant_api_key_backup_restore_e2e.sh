#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${NAMESPACE:-demo}"
CLUSTER_NAME="${CLUSTER_NAME:-qdrant-api-key-e2e}"
RESTORE_CLUSTER_NAME="${RESTORE_CLUSTER_NAME:-qdrant-api-key-e2e-restore}"
BACKUP_NAME="${BACKUP_NAME:-${CLUSTER_NAME}-backup}"
API_KEY="${QDRANT_API_KEY:-qdrant-e2e-key}"
API_KEY_ENABLED="${API_KEY_ENABLED:-true}"
QDRANT_TLS_ENABLED="${QDRANT_TLS_ENABLED:-false}"
RUN_LIFECYCLE_CHECK="${RUN_LIFECYCLE_CHECK:-true}"
CHECK_QDRANT_PEER_COUNT="${CHECK_QDRANT_PEER_COUNT:-false}"
SERVICE_VERSION="${SERVICE_VERSION:-1.10.0}"
STORAGE_CLASS_NAME="${STORAGE_CLASS_NAME:-}"
STORAGE_SIZE="${STORAGE_SIZE:-20Gi}"
BACKUP_TARGET_SETTLE_SECONDS="${BACKUP_TARGET_SETTLE_SECONDS:-20}"
LIFECYCLE_TIMEOUT_SECONDS="${LIFECYCLE_TIMEOUT_SECONDS:-300}"
QDRANT_COLLECTION="${QDRANT_COLLECTION:-api-key-backup-e2e}"
QDRANT_POINT_ID="${QDRANT_POINT_ID:-1}"
QDRANT_POINT_SOURCE="${QDRANT_POINT_SOURCE:-api-key-backup-e2e}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"

TMP_DIR="$(mktemp -d)"
QDRANT_SCHEME="http"
if [ "$QDRANT_TLS_ENABLED" = "true" ]; then
  QDRANT_SCHEME="https"
fi

cleanup() {
  if [ "$SKIP_CLEANUP" = "true" ]; then
    echo "INFO: SKIP_CLEANUP=true, leaving resources in namespace ${NAMESPACE}"
    echo "INFO: temporary manifests are in ${TMP_DIR}"
    return
  fi
  kubectl -n "$NAMESPACE" delete opsrequest "${CLUSTER_NAME}-scale-out-3" --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete opsrequest "${CLUSTER_NAME}-scale-in-1" --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete cluster "$RESTORE_CLUSTER_NAME" --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete backup "$BACKUP_NAME" --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete cluster "$CLUSTER_NAME" --ignore-not-found=true >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_bool() {
  local name="$1"
  local value="$2"

  case "$value" in
    true|false) ;;
    *)
      echo "ERROR: ${name} must be true or false, got: ${value}" >&2
      exit 1
      ;;
  esac
}

now_seconds() {
  date +%s
}

deadline_after() {
  echo $(( $(now_seconds) + "$1" ))
}

wait_for_jsonpath() {
  local resource="$1"
  local jsonpath="$2"
  local expected="$3"
  local deadline

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    value="$(kubectl -n "$NAMESPACE" get "$resource" -o "jsonpath=${jsonpath}" 2>/dev/null || true)"
    if [ "$value" = "$expected" ]; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for ${resource} ${jsonpath}=${expected}" >&2
  kubectl -n "$NAMESPACE" get "$resource" -oyaml >&2 || true
  return 1
}

wait_for_cluster_generation_running() {
  local cluster="$1"
  local generation="$2"
  local deadline
  local observed_generation
  local phase

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    observed_generation="$(kubectl -n "$NAMESPACE" get "cluster/${cluster}" -o "jsonpath={.status.observedGeneration}" 2>/dev/null || true)"
    phase="$(kubectl -n "$NAMESPACE" get "cluster/${cluster}" -o "jsonpath={.status.phase}" 2>/dev/null || true)"
    if [ "$observed_generation" = "$generation" ] && [ "$phase" = "Running" ]; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for cluster/${cluster} generation ${generation} to become Running" >&2
  kubectl -n "$NAMESPACE" get "cluster/${cluster}" -oyaml >&2 || true
  return 1
}

wait_for_opsrequest_succeed() {
  local ops_name="$1"
  local deadline
  local phase

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    phase="$(kubectl -n "$NAMESPACE" get "opsrequest/${ops_name}" -o "jsonpath={.status.phase}" 2>/dev/null || true)"
    if [ "$phase" = "Succeed" ]; then
      return 0
    fi
    if [ "$phase" = "Failed" ] || [ "$phase" = "Cancelled" ]; then
      echo "ERROR: opsrequest/${ops_name} ended with phase ${phase}" >&2
      kubectl -n "$NAMESPACE" get "opsrequest/${ops_name}" -oyaml >&2 || true
      return 1
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for opsrequest/${ops_name} to Succeed" >&2
  kubectl -n "$NAMESPACE" get "opsrequest/${ops_name}" -oyaml >&2 || true
  return 1
}

scale_cluster_replicas() {
  local cluster="$1"
  local replicas="$2"
  local direction="$3"
  local changes="$4"
  local ops_suffix
  local ops_name
  local generation

  case "$direction" in
    scaleOut) ops_suffix="scale-out" ;;
    scaleIn) ops_suffix="scale-in" ;;
    *)
      echo "ERROR: unsupported scale direction: ${direction}" >&2
      return 1
      ;;
  esac
  ops_name="${cluster}-${ops_suffix}-${replicas}"

  cat > "${TMP_DIR}/${ops_name}.yaml" <<EOF
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ${ops_name}
  namespace: ${NAMESPACE}
spec:
  clusterName: ${cluster}
  type: HorizontalScaling
  horizontalScaling:
    - componentName: qdrant
      ${direction}:
        replicaChanges: ${changes}
EOF

  kubectl apply -f "${TMP_DIR}/${ops_name}.yaml"
  wait_for_opsrequest_succeed "$ops_name"
  generation="$(kubectl -n "$NAMESPACE" get "cluster/${cluster}" -o "jsonpath={.metadata.generation}")"
  wait_for_cluster_generation_running "$cluster" "$generation"
}

wait_for_qdrant_ready_pod_count() {
  local cluster="$1"
  local expected_count="$2"
  local deadline
  local ready_count
  local pod_names

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    ready_count="$(kubectl -n "$NAMESPACE" get pod \
      -l "app.kubernetes.io/instance=${cluster},apps.kubeblocks.io/component-name=qdrant" \
      -o json | jq -r '
        [
          .items[]
          | select(.metadata.deletionTimestamp == null)
          | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
        ]
        | length
      ')"
    if [ "$ready_count" = "$expected_count" ]; then
      return 0
    fi
    sleep 5
  done

  pod_names="$(kubectl -n "$NAMESPACE" get pod \
    -l "app.kubernetes.io/instance=${cluster},apps.kubeblocks.io/component-name=qdrant" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null || true)"
  echo "ERROR: timed out waiting for ${expected_count} ready qdrant pod(s) in cluster ${cluster}" >&2
  echo "$pod_names" >&2
  return 1
}

wait_for_qdrant_peer_count() {
  local cluster="$1"
  local expected_count="$2"
  local deadline
  local response
  local peer_count

  deadline="$(deadline_after "$LIFECYCLE_TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    response="$(qdrant_curl "$cluster" "${QDRANT_SCHEME}://localhost:6333/cluster" 2>/dev/null || true)"
    peer_count="$(echo "$response" | jq -r '.result.peers | length' 2>/dev/null || true)"
    if [ "$peer_count" = "$expected_count" ]; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for ${expected_count} qdrant peer(s) in cluster ${cluster}" >&2
  qdrant_curl "$cluster" "${QDRANT_SCHEME}://localhost:6333/cluster" >&2 || true
  return 1
}

qdrant_pod() {
  kubectl -n "$NAMESPACE" get pod \
    -l "app.kubernetes.io/instance=$1,apps.kubeblocks.io/component-name=qdrant" \
    -o jsonpath='{.items[0].metadata.name}'
}

qdrant_curl() {
  local cluster="$1"
  shift
  local pod
  local curl_args=(-sS -f)

  if [ "$QDRANT_TLS_ENABLED" = "true" ]; then
    curl_args+=(-k)
  fi
  if [ "$API_KEY_ENABLED" = "true" ]; then
    curl_args+=(-H "api-key: ${API_KEY}")
  fi

  pod="$(qdrant_pod "$cluster")"
  kubectl -n "$NAMESPACE" exec "$pod" -- /qdrant/tools/curl "${curl_args[@]}" "$@"
}

wait_for_qdrant_collection() {
  local cluster="$1"
  local deadline

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    if qdrant_curl "$cluster" "${QDRANT_SCHEME}://localhost:6333/collections/${QDRANT_COLLECTION}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for qdrant collection ${QDRANT_COLLECTION} in cluster ${cluster}" >&2
  return 1
}

retrieve_qdrant_point() {
  local cluster="$1"

  qdrant_curl "$cluster" -X POST "${QDRANT_SCHEME}://localhost:6333/collections/${QDRANT_COLLECTION}/points" \
    -H "Content-Type: application/json" \
    -d "{\"ids\":[${QDRANT_POINT_ID}],\"with_payload\":true,\"with_vector\":true}"
}

run_lifecycle_check() {
  echo "INFO: scaling ${CLUSTER_NAME} from 1 to 3 replicas"
  scale_cluster_replicas "$CLUSTER_NAME" 3 scaleOut 2
  wait_for_qdrant_ready_pod_count "$CLUSTER_NAME" 3
  if [ "$CHECK_QDRANT_PEER_COUNT" = "true" ]; then
    wait_for_qdrant_peer_count "$CLUSTER_NAME" 3
  fi
  source_point_response="$(retrieve_qdrant_point "$CLUSTER_NAME")"
  assert_qdrant_point_shape "$source_point_response"

  echo "INFO: scaling ${CLUSTER_NAME} from 3 to 1 replicas"
  scale_cluster_replicas "$CLUSTER_NAME" 1 scaleIn 2
  wait_for_qdrant_ready_pod_count "$CLUSTER_NAME" 1
  if [ "$CHECK_QDRANT_PEER_COUNT" = "true" ]; then
    wait_for_qdrant_peer_count "$CLUSTER_NAME" 1
  fi
  source_point_response="$(retrieve_qdrant_point "$CLUSTER_NAME")"
  assert_qdrant_point_shape "$source_point_response"
}

assert_qdrant_point_shape() {
  local response="$1"

  if ! echo "$response" | jq -e \
    --arg source "$QDRANT_POINT_SOURCE" \
    --argjson point_id "$QDRANT_POINT_ID" \
    '
      def absdiff(a; b): ((a - b) | if . < 0 then -. else . end);
      .status == "ok"
      and (.result | length) == 1
      and .result[0].id == $point_id
      and .result[0].payload.source == $source
      and (.result[0].vector | length) == 4
      and (.result[0].vector[] | type == "number")
    ' >/dev/null; then
    echo "ERROR: qdrant point does not match expected shape" >&2
    echo "$response" >&2
    return 1
  fi
}

assert_qdrant_points_equal() {
  local source_response="$1"
  local restored_response="$2"

  if ! jq -n -e \
    --argjson source "$source_response" \
    --argjson restored "$restored_response" \
    '
      def absdiff(a; b): ((a - b) | if . < 0 then -. else . end);
      ($source.result[0]) as $s
      | ($restored.result[0]) as $r
      | $s.id == $r.id
      and $s.payload == $r.payload
      and ($s.vector | length) == ($r.vector | length)
      and all(range(0; ($s.vector | length)); absdiff($s.vector[.]; $r.vector[.]) < 0.00001)
    ' >/dev/null; then
    echo "ERROR: restored qdrant point differs from source point" >&2
    echo "source:   ${source_response}" >&2
    echo "restored: ${restored_response}" >&2
    return 1
  fi
}

write_cluster_manifest() {
  local name="$1"
  local file="$2"
  local restore_annotation="${3:-}"

  {
    echo "apiVersion: apps.kubeblocks.io/v1"
    echo "kind: Cluster"
    echo "metadata:"
    echo "  name: ${name}"
    echo "  namespace: ${NAMESPACE}"
    if [ -n "$restore_annotation" ]; then
      echo "  annotations:"
      echo "    kubeblocks.io/restore-from-backup: '${restore_annotation}'"
    fi
    echo "spec:"
    echo "  terminationPolicy: Delete"
    echo "  clusterDef: qdrant"
    echo "  topology: cluster"
    echo "  componentSpecs:"
    echo "    - name: qdrant"
    echo "      serviceVersion: ${SERVICE_VERSION}"
    echo "      replicas: 1"
    if [ "$QDRANT_TLS_ENABLED" = "true" ]; then
      echo "      tls: true"
      echo "      issuer:"
      echo "        name: KubeBlocks"
    fi
    if [ "$API_KEY_ENABLED" = "true" ]; then
      echo "      configs:"
      echo "        - name: qdrant-config-template"
      echo "          variables:"
      echo "            service_api_key: ${API_KEY}"
    fi
    echo "      resources:"
    echo "        limits:"
    echo "          cpu: \"0.5\""
    echo "          memory: \"0.5Gi\""
    echo "        requests:"
    echo "          cpu: \"0.5\""
    echo "          memory: \"0.5Gi\""
    echo "      volumeClaimTemplates:"
    echo "        - name: data"
    echo "          spec:"
    if [ -n "$STORAGE_CLASS_NAME" ]; then
      echo "            storageClassName: ${STORAGE_CLASS_NAME}"
    else
      echo "            storageClassName: \"\""
    fi
    echo "            accessModes:"
    echo "              - ReadWriteOnce"
    echo "            resources:"
    echo "              requests:"
    echo "                storage: ${STORAGE_SIZE}"
  } > "$file"
}

require_cmd kubectl
require_cmd jq
require_bool API_KEY_ENABLED "$API_KEY_ENABLED"
require_bool QDRANT_TLS_ENABLED "$QDRANT_TLS_ENABLED"
require_bool RUN_LIFECYCLE_CHECK "$RUN_LIFECYCLE_CHECK"
require_bool CHECK_QDRANT_PEER_COUNT "$CHECK_QDRANT_PEER_COUNT"
kubectl create namespace "$NAMESPACE" --dry-run=client -oyaml | kubectl apply -f -

cluster_manifest="${TMP_DIR}/cluster.yaml"
write_cluster_manifest "$CLUSTER_NAME" "$cluster_manifest"
kubectl apply -f "$cluster_manifest"
wait_for_jsonpath "cluster/${CLUSTER_NAME}" "{.status.phase}" "Running"

echo "INFO: creating qdrant collection ${QDRANT_COLLECTION}"
qdrant_curl "$CLUSTER_NAME" -X PUT "${QDRANT_SCHEME}://localhost:6333/collections/${QDRANT_COLLECTION}" \
  -H "Content-Type: application/json" \
  -d '{"vectors":{"size":4,"distance":"Cosine"},"wal_config":{"wal_capacity_mb":1,"wal_segments_ahead":0}}' >/dev/null

qdrant_curl "$CLUSTER_NAME" -X PUT "${QDRANT_SCHEME}://localhost:6333/collections/${QDRANT_COLLECTION}/points?wait=true" \
  -H "Content-Type: application/json" \
  -d "{\"points\":[{\"id\":${QDRANT_POINT_ID},\"vector\":[0.1,0.2,0.3,0.4],\"payload\":{\"source\":\"${QDRANT_POINT_SOURCE}\"}}]}" >/dev/null

echo "INFO: verifying source qdrant data before backup"
source_point_response="$(retrieve_qdrant_point "$CLUSTER_NAME")"
assert_qdrant_point_shape "$source_point_response"
if [ "$RUN_LIFECYCLE_CHECK" = "true" ]; then
  run_lifecycle_check
fi
wait_for_qdrant_ready_pod_count "$CLUSTER_NAME" 1
if [ "$BACKUP_TARGET_SETTLE_SECONDS" -gt 0 ]; then
  echo "INFO: waiting ${BACKUP_TARGET_SETTLE_SECONDS}s for qdrant backup target to settle after lifecycle changes"
  sleep "$BACKUP_TARGET_SETTLE_SECONDS"
fi

cat > "${TMP_DIR}/backup.yaml" <<EOF
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: ${BACKUP_NAME}
  namespace: ${NAMESPACE}
spec:
  backupMethod: datafile
  backupPolicyName: ${CLUSTER_NAME}-qdrant-backup-policy
  deletionPolicy: Delete
EOF

kubectl apply -f "${TMP_DIR}/backup.yaml"
wait_for_jsonpath "backup/${BACKUP_NAME}" "{.status.phase}" "Completed"

restore_manifest="${TMP_DIR}/restore-cluster.yaml"
restore_from_backup="{\"qdrant\":{\"name\":\"${BACKUP_NAME}\",\"namespace\":\"${NAMESPACE}\",\"volumeRestorePolicy\":\"Parallel\"}}"
write_cluster_manifest "$RESTORE_CLUSTER_NAME" "$restore_manifest" "$restore_from_backup"
kubectl apply -f "$restore_manifest"
wait_for_jsonpath "cluster/${RESTORE_CLUSTER_NAME}" "{.status.phase}" "Running"

echo "INFO: verifying restored collection ${QDRANT_COLLECTION}"
wait_for_qdrant_collection "$RESTORE_CLUSTER_NAME"
echo "INFO: verifying restored qdrant point data"
restored_point_response="$(retrieve_qdrant_point "$RESTORE_CLUSTER_NAME")"
assert_qdrant_point_shape "$restored_point_response"
assert_qdrant_points_equal "$source_point_response" "$restored_point_response"

echo "INFO: qdrant backup/restore e2e passed with TLS=${QDRANT_TLS_ENABLED}, API key=${API_KEY_ENABLED}"
