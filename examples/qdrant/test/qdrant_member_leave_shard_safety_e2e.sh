#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${NAMESPACE:-demo}"
CLUSTER_NAME="${CLUSTER_NAME:-qdrant-memberleave-shard-drain}"
API_KEY="${QDRANT_API_KEY:-qdrant-shard-drain-key}"
API_KEY_ENABLED="${API_KEY_ENABLED:-true}"
QDRANT_TLS_ENABLED="${QDRANT_TLS_ENABLED:-false}"
SERVICE_VERSION="${SERVICE_VERSION:-1.18.2}"
STORAGE_CLASS_NAME="${STORAGE_CLASS_NAME:-}"
STORAGE_SIZE="${STORAGE_SIZE:-20Gi}"
QDRANT_COLLECTION="${QDRANT_COLLECTION:-memberleave-shard-drain}"
QDRANT_POINT_SOURCE="${QDRANT_POINT_SOURCE:-memberleave-shard-drain}"
QDRANT_POINT_COUNT="${QDRANT_POINT_COUNT:-18}"
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
  kubectl -n "$NAMESPACE" delete opsrequest "${CLUSTER_NAME}-scale-in-1" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete cluster "$CLUSTER_NAME" --ignore-not-found=true --timeout=300s >/dev/null 2>&1 || true
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
  local value

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

wait_for_qdrant_ready_pod_count() {
  local expected_count="$1"
  local deadline
  local ready_count

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    ready_count="$(kubectl -n "$NAMESPACE" get pod \
      -l "app.kubernetes.io/instance=${CLUSTER_NAME},apps.kubeblocks.io/component-name=qdrant" \
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

  echo "ERROR: timed out waiting for ${expected_count} ready qdrant pod(s)" >&2
  kubectl -n "$NAMESPACE" get pod -l "app.kubernetes.io/instance=${CLUSTER_NAME},apps.kubeblocks.io/component-name=qdrant" -owide >&2 || true
  return 1
}

qdrant_pod() {
  echo "${CLUSTER_NAME}-qdrant-0"
}

qdrant_curl() {
  local pod
  local curl_args=(-sS -f)

  if [ "$QDRANT_TLS_ENABLED" = "true" ]; then
    curl_args+=(-k)
  fi
  if [ "$API_KEY_ENABLED" = "true" ]; then
    curl_args+=(-H "api-key: ${API_KEY}")
  fi

  pod="$(qdrant_pod)"
  kubectl -n "$NAMESPACE" exec "$pod" -- /qdrant/tools/curl "${curl_args[@]}" "$@"
}

wait_for_qdrant_peer_count() {
  local expected_count="$1"
  local deadline
  local response
  local peer_count

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    response="$(qdrant_curl "${QDRANT_SCHEME}://localhost:6333/cluster" 2>/dev/null || true)"
    peer_count="$(echo "$response" | jq -r '.result.peers | length' 2>/dev/null || true)"
    if [ "$peer_count" = "$expected_count" ]; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for ${expected_count} qdrant peer(s)" >&2
  qdrant_curl "${QDRANT_SCHEME}://localhost:6333/cluster" >&2 || true
  return 1
}

peer_id_for_pod() {
  local pod_name="$1"

  qdrant_curl "${QDRANT_SCHEME}://localhost:6333/cluster" \
    | jq -r --arg pod "$pod_name" '
        .result.peers
        | to_entries[]
        | select(.value.uri | contains("://" + $pod + "."))
        | .key
      '
}

collection_cluster_info() {
  qdrant_curl "${QDRANT_SCHEME}://localhost:6333/collections/${QDRANT_COLLECTION}/cluster"
}

collection_has_shard_on_peer() {
  local peer_id="$1"
  local response="$2"

  echo "$response" | jq -e --arg peer_id "$peer_id" '
    [
      .result.local_shards[]? | select((.peer_id? // .peer_id | tostring) == $peer_id)
    ]
    +
    [
      .result.remote_shards[]? | select((.peer_id | tostring) == $peer_id)
    ]
    | length > 0
  ' >/dev/null
}

wait_for_leaving_peer_with_shards() {
  local deadline
  local response
  local peer_id
  local pod_name

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    response="$(collection_cluster_info 2>/dev/null || true)"
    for pod_name in "${CLUSTER_NAME}-qdrant-1" "${CLUSTER_NAME}-qdrant-2"; do
      peer_id="$(peer_id_for_pod "$pod_name" 2>/dev/null || true)"
      if [ -n "$peer_id" ] && collection_has_shard_on_peer "$peer_id" "$response"; then
        echo "INFO: ${pod_name} peer ${peer_id} owns collection shards"
        return 0
      fi
    done
    sleep 5
  done

  echo "ERROR: timed out waiting for a leaving qdrant peer to own collection shards" >&2
  collection_cluster_info >&2 || true
  qdrant_curl "${QDRANT_SCHEME}://localhost:6333/cluster" >&2 || true
  return 1
}

seed_points() {
  local payload

  payload="$(jq -n \
    --arg source "$QDRANT_POINT_SOURCE" \
    --argjson count "$QDRANT_POINT_COUNT" '
      {
        points: [
          range(1; $count + 1) as $id
          | {
              id: $id,
              vector: [($id / 100), 0.2, 0.3, 0.4],
              payload: {
                source: $source,
                seq: $id
              }
            }
        ]
      }
    ')"

  qdrant_curl -X PUT "${QDRANT_SCHEME}://localhost:6333/collections/${QDRANT_COLLECTION}/points?wait=true" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null
}

point_count() {
  qdrant_curl -X POST "${QDRANT_SCHEME}://localhost:6333/collections/${QDRANT_COLLECTION}/points/count" \
    -H "Content-Type: application/json" \
    -d '{"exact":true}' \
    | jq -r '.result.count'
}

points_digest() {
  local limit

  limit=$((QDRANT_POINT_COUNT + 5))
  qdrant_curl -X POST "${QDRANT_SCHEME}://localhost:6333/collections/${QDRANT_COLLECTION}/points/scroll" \
    -H "Content-Type: application/json" \
    -d "{\"limit\":${limit},\"with_payload\":true,\"with_vector\":true}" \
    | jq -c --arg source "$QDRANT_POINT_SOURCE" '
        [
          .result.points[]
          | select(.payload.source == $source)
          | {
              id,
              payload: {
                source: .payload.source,
                seq: .payload.seq
              },
              vector
            }
        ]
        | sort_by(.id)
      '
}

wait_for_point_count() {
  local expected_count="$1"
  local deadline
  local actual_count

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    actual_count="$(point_count 2>/dev/null || true)"
    if [ "$actual_count" = "$expected_count" ]; then
      return 0
    fi
    sleep 5
  done

  echo "ERROR: timed out waiting for ${expected_count} qdrant point(s)" >&2
  point_count >&2 || true
  return 1
}

create_scale_in_opsrequest() {
  local ops_name="${CLUSTER_NAME}-scale-in-1"

  cat > "${TMP_DIR}/${ops_name}.yaml" <<EOF
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ${ops_name}
  namespace: ${NAMESPACE}
spec:
  clusterName: ${CLUSTER_NAME}
  type: HorizontalScaling
  horizontalScaling:
    - componentName: qdrant
      scaleIn:
        replicaChanges: 2
EOF

  kubectl apply -f "${TMP_DIR}/${ops_name}.yaml"
}

wait_for_scale_in_succeed() {
  local ops_name="${CLUSTER_NAME}-scale-in-1"
  local deadline
  local phase

  deadline="$(deadline_after "$TIMEOUT_SECONDS")"

  while [ "$(now_seconds)" -lt "$deadline" ]; do
    phase="$(kubectl -n "$NAMESPACE" get "opsrequest/${ops_name}" -o "jsonpath={.status.phase}" 2>/dev/null || true)"
    case "$phase" in
      Succeed)
        return 0
        ;;
      Failed|Cancelled|Aborted)
        echo "ERROR: opsrequest/${ops_name} ended with phase ${phase}" >&2
        kubectl -n "$NAMESPACE" get "opsrequest/${ops_name}" -oyaml >&2 || true
        collection_cluster_info >&2 || true
        return 1
        ;;
    esac
    sleep 5
  done

  echo "ERROR: timed out waiting for opsrequest/${ops_name} to succeed" >&2
  kubectl -n "$NAMESPACE" get "opsrequest/${ops_name}" -oyaml >&2 || true
  collection_cluster_info >&2 || true
  return 1
}

assert_points_consistent() {
  local expected_digest="$1"
  local actual_count
  local actual_digest

  wait_for_point_count "$QDRANT_POINT_COUNT"
  actual_count="$(point_count)"
  actual_digest="$(points_digest)"
  if [ "$actual_count" != "$QDRANT_POINT_COUNT" ]; then
    echo "ERROR: expected ${QDRANT_POINT_COUNT} qdrant point(s), got ${actual_count}" >&2
    return 1
  fi
  if [ "$actual_digest" != "$expected_digest" ]; then
    echo "ERROR: qdrant point digest changed after scale-in" >&2
    echo "expected: ${expected_digest}" >&2
    echo "actual:   ${actual_digest}" >&2
    return 1
  fi
}

write_cluster_manifest() {
  local file="$1"

  {
    echo "apiVersion: apps.kubeblocks.io/v1"
    echo "kind: Cluster"
    echo "metadata:"
    echo "  name: ${CLUSTER_NAME}"
    echo "  namespace: ${NAMESPACE}"
    echo "spec:"
    echo "  terminationPolicy: Delete"
    echo "  clusterDef: qdrant"
    echo "  topology: cluster"
    echo "  componentSpecs:"
    echo "    - name: qdrant"
    echo "      serviceVersion: ${SERVICE_VERSION}"
    echo "      replicas: 3"
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

kubectl create namespace "$NAMESPACE" --dry-run=client -oyaml | kubectl apply -f -

cluster_manifest="${TMP_DIR}/cluster.yaml"
write_cluster_manifest "$cluster_manifest"
kubectl apply -f "$cluster_manifest"
wait_for_jsonpath "cluster/${CLUSTER_NAME}" "{.status.phase}" "Running"
wait_for_qdrant_ready_pod_count 3
wait_for_qdrant_peer_count 3

echo "INFO: creating sharded qdrant collection ${QDRANT_COLLECTION}"
qdrant_curl -X PUT "${QDRANT_SCHEME}://localhost:6333/collections/${QDRANT_COLLECTION}" \
  -H "Content-Type: application/json" \
  -d '{"vectors":{"size":4,"distance":"Cosine"},"shard_number":6,"replication_factor":1,"write_consistency_factor":1}' >/dev/null

echo "INFO: writing ${QDRANT_POINT_COUNT} qdrant point(s)"
seed_points
wait_for_point_count "$QDRANT_POINT_COUNT"
expected_digest="$(points_digest)"

wait_for_leaving_peer_with_shards

echo "INFO: verifying qdrant memberLeave drains shards before removing peers"
create_scale_in_opsrequest
wait_for_scale_in_succeed
wait_for_qdrant_ready_pod_count 1
wait_for_qdrant_peer_count 1
assert_points_consistent "$expected_digest"

echo "INFO: qdrant memberLeave shard-drain e2e passed"
