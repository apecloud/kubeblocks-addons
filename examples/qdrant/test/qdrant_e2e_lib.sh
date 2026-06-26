#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${NAMESPACE:-demo}"
BACKUP_REPO="${BACKUP_REPO:-kb-oss}"
SERVICE_VERSION="${SERVICE_VERSION:-1.10.0}"
QDRANT_REPLICAS="${QDRANT_REPLICAS:-1}"
QDRANT_CPU="${QDRANT_CPU:-0.5}"
QDRANT_MEMORY="${QDRANT_MEMORY:-0.5Gi}"
QDRANT_STORAGE_SIZE="${QDRANT_STORAGE_SIZE:-20Gi}"
QDRANT_STORAGE_CLASS_NAME="${QDRANT_STORAGE_CLASS_NAME:-}"
QDRANT_API_KEY="${QDRANT_API_KEY:-qdrant-e2e-key}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"

TMP_DIR="${TMP_DIR:-$(mktemp -d)}"
QDRANT_E2E_SOURCE_CLUSTER=""
QDRANT_E2E_RESTORE_CLUSTER=""
QDRANT_E2E_BACKUP_NAME=""

kubectl_cmd() {
  if [ -n "${KUBECTL_CONTEXT:-}" ]; then
    kubectl --context "$KUBECTL_CONTEXT" "$@"
  else
    kubectl "$@"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

now_seconds() {
  date +%s
}

deadline_after() {
  echo $(( $(now_seconds) + "$1" ))
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

require_api_key_mode() {
  case "$1" in
    none|config|env) ;;
    *)
      echo "ERROR: api key mode must be one of: none, config, env. Got: $1" >&2
      exit 1
      ;;
  esac
}

qdrant_scheme() {
  if [ "$1" = "true" ]; then
    echo "https"
  else
    echo "http"
  fi
}

qdrant_case_cleanup() {
  local source_cluster="$1"
  local restore_cluster="$2"
  local backup_name="$3"

  if [ "$SKIP_CLEANUP" = "true" ]; then
    echo "INFO: SKIP_CLEANUP=true, leaving qdrant e2e resources in namespace ${NAMESPACE}"
    echo "INFO: temporary manifests are in ${TMP_DIR}"
    return
  fi

  kubectl_cmd -n "$NAMESPACE" delete cluster "$restore_cluster" --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl_cmd -n "$NAMESPACE" delete backup "$backup_name" --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl_cmd -n "$NAMESPACE" delete cluster "$source_cluster" --ignore-not-found=true >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}

wait_for_jsonpath() {
  local resource="$1"
  local jsonpath="$2"
  local expected="$3"
  local deadline
  local value

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    value="$(kubectl_cmd -n "$NAMESPACE" get "$resource" -o "jsonpath=${jsonpath}" 2>/dev/null || true)"
    if [ "$value" = "$expected" ]; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for ${resource} ${jsonpath}=${expected}" >&2
  kubectl_cmd -n "$NAMESPACE" get "$resource" -oyaml >&2 || true
  return 1
}

wait_for_qdrant_ready_pod_count() {
  local cluster="$1"
  local expected_count="$2"
  local deadline
  local ready_count

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    ready_count="$(kubectl_cmd -n "$NAMESPACE" get pod \
      -l "app.kubernetes.io/instance=${cluster},apps.kubeblocks.io/component-name=qdrant" \
      -o json 2>/dev/null | jq -r '
        [
          .items[]
          | select(.metadata.deletionTimestamp == null)
          | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
        ]
        | length
      ' || true)"
    if [ "$ready_count" = "$expected_count" ]; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for ${expected_count} ready qdrant pod(s) in cluster ${cluster}" >&2
  kubectl_cmd -n "$NAMESPACE" get pod -l "app.kubernetes.io/instance=${cluster},apps.kubeblocks.io/component-name=qdrant" -owide >&2 || true
  return 1
}

qdrant_ready_pod() {
  local cluster="$1"

  kubectl_cmd -n "$NAMESPACE" get pod \
    -l "app.kubernetes.io/instance=${cluster},apps.kubeblocks.io/component-name=qdrant" \
    -o json | jq -r '
      .items[]
      | select(.metadata.deletionTimestamp == null)
      | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
      | .metadata.name
    ' | head -n 1
}

qdrant_curl() {
  local cluster="$1"
  local tls_enabled="$2"
  local api_key_mode="$3"
  shift 3

  local pod
  local curl_args=(-sS -f)

  if [ "$tls_enabled" = "true" ]; then
    curl_args+=(-k)
  fi
  if [ "$api_key_mode" != "none" ]; then
    curl_args+=(-H "api-key: ${QDRANT_API_KEY}")
  fi

  pod="$(qdrant_ready_pod "$cluster")"
  if [ -z "$pod" ]; then
    echo "ERROR: no ready qdrant pod found for cluster ${cluster}" >&2
    return 1
  fi

  kubectl_cmd -n "$NAMESPACE" exec "$pod" -c qdrant -- /qdrant/tools/curl "${curl_args[@]}" "$@"
}

write_qdrant_cluster_manifest() {
  local cluster="$1"
  local file="$2"
  local tls_enabled="$3"
  local api_key_mode="$4"
  local restore_annotation="${5:-}"

  {
    echo "apiVersion: apps.kubeblocks.io/v1"
    echo "kind: Cluster"
    echo "metadata:"
    echo "  name: ${cluster}"
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
    echo "      replicas: ${QDRANT_REPLICAS}"
    if [ "$tls_enabled" = "true" ]; then
      echo "      tls: true"
      echo "      issuer:"
      echo "        name: KubeBlocks"
    fi
    if [ "$api_key_mode" = "config" ]; then
      echo "      configs:"
      echo "        - name: qdrant-config-template"
      echo "          variables:"
      echo "            service_api_key: ${QDRANT_API_KEY}"
    fi
    if [ "$api_key_mode" = "env" ]; then
      echo "      env:"
      echo "        - name: QDRANT__SERVICE__API_KEY"
      echo "          value: ${QDRANT_API_KEY}"
    fi
    echo "      resources:"
    echo "        limits:"
    echo "          cpu: \"${QDRANT_CPU}\""
    echo "          memory: \"${QDRANT_MEMORY}\""
    echo "        requests:"
    echo "          cpu: \"${QDRANT_CPU}\""
    echo "          memory: \"${QDRANT_MEMORY}\""
    echo "      volumeClaimTemplates:"
    echo "        - name: data"
    echo "          spec:"
    if [ -n "$QDRANT_STORAGE_CLASS_NAME" ]; then
      echo "            storageClassName: ${QDRANT_STORAGE_CLASS_NAME}"
    else
      echo "            storageClassName: \"\""
    fi
    echo "            accessModes:"
    echo "              - ReadWriteOnce"
    echo "            resources:"
    echo "              requests:"
    echo "                storage: ${QDRANT_STORAGE_SIZE}"
  } > "$file"
}

seed_qdrant_data() {
  local cluster="$1"
  local tls_enabled="$2"
  local api_key_mode="$3"
  local collection="$4"
  local case_name="$5"
  local scheme

  scheme="$(qdrant_scheme "$tls_enabled")"

  echo "INFO: creating qdrant collection ${collection} in ${cluster}"
  qdrant_curl "$cluster" "$tls_enabled" "$api_key_mode" \
    -X PUT "${scheme}://localhost:6333/collections/${collection}" \
    -H "Content-Type: application/json" \
    -d '{"vectors":{"size":4,"distance":"Cosine"},"wal_config":{"wal_capacity_mb":1,"wal_segments_ahead":0}}' >/dev/null

  echo "INFO: upserting qdrant points in ${collection}"
  qdrant_curl "$cluster" "$tls_enabled" "$api_key_mode" \
    -X PUT "${scheme}://localhost:6333/collections/${collection}/points?wait=true" \
    -H "Content-Type: application/json" \
    -d "{\"points\":[{\"id\":1,\"vector\":[0.11,0.12,0.13,0.14],\"payload\":{\"case\":\"${case_name}\",\"slot\":\"one\"}},{\"id\":2,\"vector\":[0.21,0.22,0.23,0.24],\"payload\":{\"case\":\"${case_name}\",\"slot\":\"two\"}},{\"id\":3,\"vector\":[0.31,0.32,0.33,0.34],\"payload\":{\"case\":\"${case_name}\",\"slot\":\"three\"}}]}" >/dev/null
}

retrieve_qdrant_points() {
  local cluster="$1"
  local tls_enabled="$2"
  local api_key_mode="$3"
  local collection="$4"
  local scheme

  scheme="$(qdrant_scheme "$tls_enabled")"

  qdrant_curl "$cluster" "$tls_enabled" "$api_key_mode" \
    -X POST "${scheme}://localhost:6333/collections/${collection}/points" \
    -H "Content-Type: application/json" \
    -d '{"ids":[1,2,3],"with_payload":true,"with_vector":true}'
}

normalize_qdrant_points() {
  jq -S '
    {
      status: .status,
      result: (
        .result
        | sort_by(.id)
        | map({id: .id, payload: .payload, vector: .vector})
      )
    }
  '
}

assert_qdrant_points_match_case() {
  local response="$1"
  local case_name="$2"

  if ! echo "$response" | jq -e --arg case_name "$case_name" '
    .status == "ok"
    and (.result | length) == 3
    and all(.result[]; .payload.case == $case_name)
    and all(.result[]; (.vector | length) == 4)
  ' >/dev/null; then
    echo "ERROR: qdrant points do not match expected case payload/vector shape" >&2
    echo "$response" >&2
    return 1
  fi
}

assert_qdrant_points_equal() {
  local source_response="$1"
  local restored_response="$2"
  local normalized_source
  local normalized_restored

  normalized_source="$(echo "$source_response" | normalize_qdrant_points)"
  normalized_restored="$(echo "$restored_response" | normalize_qdrant_points)"

  if [ "$normalized_source" != "$normalized_restored" ]; then
    echo "ERROR: restored qdrant points differ from source points" >&2
    echo "source: ${normalized_source}" >&2
    echo "restored: ${normalized_restored}" >&2
    return 1
  fi
}

wait_for_qdrant_collection() {
  local cluster="$1"
  local tls_enabled="$2"
  local api_key_mode="$3"
  local collection="$4"
  local scheme
  local deadline

  scheme="$(qdrant_scheme "$tls_enabled")"
  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    if qdrant_curl "$cluster" "$tls_enabled" "$api_key_mode" "${scheme}://localhost:6333/collections/${collection}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for qdrant collection ${collection} in cluster ${cluster}" >&2
  return 1
}

assert_qdrant_e2e_prereqs() {
  require_cmd kubectl
  require_cmd jq

  kubectl_cmd create namespace "$NAMESPACE" --dry-run=client -oyaml | kubectl_cmd apply -f - >/dev/null

  if [ "$(kubectl_cmd get backuprepo "$BACKUP_REPO" -o jsonpath='{.status.phase}' 2>/dev/null || true)" != "Ready" ]; then
    echo "ERROR: BackupRepo ${BACKUP_REPO} is not Ready" >&2
    kubectl_cmd get backuprepo "$BACKUP_REPO" -oyaml >&2 || true
    exit 1
  fi

  if [ "$(kubectl_cmd get backuprepo "$BACKUP_REPO" -o 'jsonpath={.metadata.annotations.dataprotection\.kubeblocks\.io/is-default-repo}' 2>/dev/null || true)" != "true" ]; then
    echo "ERROR: BackupRepo ${BACKUP_REPO} is not annotated as the default repo" >&2
    kubectl_cmd get backuprepo "$BACKUP_REPO" -oyaml >&2 || true
    exit 1
  fi
}

run_qdrant_backup_restore_case() {
  local case_name="$1"
  local tls_enabled="$2"
  local api_key_mode="$3"
  local source_cluster="${CLUSTER_NAME:-qdrant-${case_name}}"
  local restore_cluster="${RESTORE_CLUSTER_NAME:-${source_cluster}-restore}"
  local backup_name="${BACKUP_NAME:-${source_cluster}-backup}"
  local collection="e2e_${case_name//-/_}"
  local source_manifest="${TMP_DIR}/${source_cluster}.yaml"
  local restore_manifest="${TMP_DIR}/${restore_cluster}.yaml"
  local backup_manifest="${TMP_DIR}/${backup_name}.yaml"
  local restore_from_backup
  local source_response
  local restored_response

  require_bool tls_enabled "$tls_enabled"
  require_api_key_mode "$api_key_mode"
  assert_qdrant_e2e_prereqs

  QDRANT_E2E_SOURCE_CLUSTER="$source_cluster"
  QDRANT_E2E_RESTORE_CLUSTER="$restore_cluster"
  QDRANT_E2E_BACKUP_NAME="$backup_name"
  trap 'qdrant_case_cleanup "$QDRANT_E2E_SOURCE_CLUSTER" "$QDRANT_E2E_RESTORE_CLUSTER" "$QDRANT_E2E_BACKUP_NAME"' EXIT

  echo "INFO: running qdrant backup/restore e2e case=${case_name} tls=${tls_enabled} api_key_mode=${api_key_mode}"

  write_qdrant_cluster_manifest "$source_cluster" "$source_manifest" "$tls_enabled" "$api_key_mode"
  kubectl_cmd apply -f "$source_manifest"
  wait_for_jsonpath "cluster/${source_cluster}" "{.status.phase}" "Running"
  wait_for_qdrant_ready_pod_count "$source_cluster" "$QDRANT_REPLICAS"

  seed_qdrant_data "$source_cluster" "$tls_enabled" "$api_key_mode" "$collection" "$case_name"
  source_response="$(retrieve_qdrant_points "$source_cluster" "$tls_enabled" "$api_key_mode" "$collection")"
  assert_qdrant_points_match_case "$source_response" "$case_name"

  cat > "$backup_manifest" <<EOF
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: ${backup_name}
  namespace: ${NAMESPACE}
spec:
  backupMethod: datafile
  backupPolicyName: ${source_cluster}-qdrant-backup-policy
  deletionPolicy: Delete
EOF

  kubectl_cmd apply -f "$backup_manifest"
  wait_for_jsonpath "backup/${backup_name}" "{.status.phase}" "Completed"

  restore_from_backup="{\"qdrant\":{\"name\":\"${backup_name}\",\"namespace\":\"${NAMESPACE}\",\"volumeRestorePolicy\":\"Parallel\"}}"
  write_qdrant_cluster_manifest "$restore_cluster" "$restore_manifest" "$tls_enabled" "$api_key_mode" "$restore_from_backup"
  kubectl_cmd apply -f "$restore_manifest"
  wait_for_jsonpath "cluster/${restore_cluster}" "{.status.phase}" "Running"
  wait_for_qdrant_ready_pod_count "$restore_cluster" "$QDRANT_REPLICAS"

  wait_for_qdrant_collection "$restore_cluster" "$tls_enabled" "$api_key_mode" "$collection"
  restored_response="$(retrieve_qdrant_points "$restore_cluster" "$tls_enabled" "$api_key_mode" "$collection")"
  assert_qdrant_points_match_case "$restored_response" "$case_name"
  assert_qdrant_points_equal "$source_response" "$restored_response"

  echo "INFO: qdrant backup/restore e2e passed case=${case_name} tls=${tls_enabled} api_key_mode=${api_key_mode}"
}
