#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ADDON_DIR="${ROOT_DIR}/addons/hugegraph"
CLUSTER_DIR="${ROOT_DIR}/addons-cluster/hugegraph"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_equal() {
  local actual=$1
  local expected=$2
  local message=$3
  [[ "${actual}" == "${expected}" ]] || fail "${message}: got ${actual}, want ${expected}"
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_contains() {
  local file=$1
  local pattern=$2
  rg -q -- "$pattern" "$file" || fail "$file does not contain: $pattern"
}

assert_not_contains_tree() {
  local pattern=$1
  if rg -n -i -- "$pattern" \
    "${ADDON_DIR}/templates" \
    "${ADDON_DIR}/values.yaml" \
    "${ROOT_DIR}/examples/hugegraph"; then
    fail "forbidden pattern found: $pattern"
  fi
}

required_files=(
  "${ADDON_DIR}/Chart.yaml"
  "${ADDON_DIR}/values.yaml"
  "${ADDON_DIR}/templates/cmpd.yaml"
  "${ADDON_DIR}/templates/monitordefinition.yaml"
  "${ADDON_DIR}/templates/cmpv.yaml"
  "${ADDON_DIR}/templates/clusterdefinition.yaml"
  "${ADDON_DIR}/templates/backuppolicytemplate.yaml"
  "${ADDON_DIR}/templates/actionset.yaml"
  "${ADDON_DIR}/templates/script-template.yaml"
  "${ADDON_DIR}/scripts/start.sh"
  "${ADDON_DIR}/scripts/shutdown.sh"
  "${ADDON_DIR}/scripts/backup.sh"
  "${ADDON_DIR}/scripts/restore.sh"
  "${ADDON_DIR}/tests/scripts_test.sh"
  "${ADDON_DIR}/exporter/Dockerfile"
  "${ADDON_DIR}/exporter/go.mod"
  "${CLUSTER_DIR}/Chart.yaml"
  "${CLUSTER_DIR}/templates/cluster.yaml"
  "${ROOT_DIR}/examples/hugegraph/cluster.yaml"
  "${ROOT_DIR}/examples/hugegraph/backup.yaml"
  "${ROOT_DIR}/examples/hugegraph/restore.yaml"
)

for file in "${required_files[@]}"; do
  assert_file "$file"
done

bash -n \
  "${ADDON_DIR}/scripts/start.sh" \
  "${ADDON_DIR}/scripts/shutdown.sh" \
  "${ADDON_DIR}/scripts/backup.sh" \
  "${ADDON_DIR}/scripts/restore.sh"

assert_contains "${ADDON_DIR}/scripts/backup.sh" 'snapshot_create'
assert_contains "${ADDON_DIR}/scripts/backup.sh" 'manifest.properties'
assert_contains "${ADDON_DIR}/scripts/backup.sh" 'checksums.sha256'
assert_contains "${ADDON_DIR}/scripts/backup.sh" 'DP_BACKUP_INFO_FILE'
assert_contains "${ADDON_DIR}/scripts/restore.sh" 'sha256sum -c'
assert_contains "${ADDON_DIR}/scripts/restore.sh" 'restore-in-progress'
assert_contains "${ADDON_DIR}/scripts/restore.sh" 'payload.tar.gz'
assert_contains "${ADDON_DIR}/templates/backuppolicytemplate.yaml" 'snapshotVolumes: false'
assert_contains "${ADDON_DIR}/templates/backuppolicytemplate.yaml" 'name: checkpoint'
assert_contains "${ADDON_DIR}/templates/backuppolicytemplate.yaml" 'account: admin'
assert_contains "${ADDON_DIR}/templates/actionset.yaml" 'prepareData:'
assert_contains "${ADDON_DIR}/templates/actionset.yaml" 'runOnTargetPodNode: true'
assert_contains "${ADDON_DIR}/scripts/start.sh" './bin/enable-auth\.sh'
assert_contains "${ADDON_DIR}/scripts/shutdown.sh" 'graceful shutdown started'
assert_contains "${ADDON_DIR}/scripts/shutdown.sh" 'graceful shutdown completed'
assert_contains "${ADDON_DIR}/scripts/shutdown.sh" '\.kb-prestop\.log'
assert_contains "${ADDON_DIR}/templates/cmpd.yaml" 'terminationGracePeriodSeconds: 30'
assert_contains "${ADDON_DIR}/templates/cmpd.yaml" 'preStop:'
assert_contains "${ADDON_DIR}/templates/cmpd.yaml" '/scripts/shutdown\.sh'
assert_contains "${ADDON_DIR}/templates/cmpd.yaml" 'name: hugegraph-exporter'
assert_contains "${ADDON_DIR}/templates/cmpd.yaml" 'containerName: hugegraph-exporter'
assert_contains "${ADDON_DIR}/templates/cmpd.yaml" 'scrapePort: metrics'
assert_contains "${ADDON_DIR}/templates/cmpd.yaml" 'scrapePath: /metrics'

assert_not_contains_tree 'volume[-_ ]snapshot'
assert_not_contains_tree 'snapshotVolumes:[[:space:]]*true'

helm dependency build "${ADDON_DIR}" >/dev/null
helm dependency build "${CLUSTER_DIR}" >/dev/null
helm lint "${ADDON_DIR}"
helm lint "${CLUSTER_DIR}"

definition_render=$(mktemp)
cluster_render=$(mktemp)
trap 'rm -f "${definition_render}" "${cluster_render}"' EXIT

helm template hugegraph-def "${ADDON_DIR}" --namespace kb-system >"${definition_render}"
helm template hugegraph "${CLUSTER_DIR}" --namespace demo >"${cluster_render}"

for kind in ClusterDefinition ComponentDefinition ComponentVersion BackupPolicyTemplate ActionSet MonitorDefinition; do
  rg -q "^kind: ${kind}$" "${definition_render}" || fail "render misses ${kind}"
done

assert_contains "${definition_render}" 'serviceVersion: [\"]?1\.7\.0[\"]?'
assert_contains "${definition_render}" 'image: docker.io/hugegraph/hugegraph:1.7.0'
assert_contains "${definition_render}" 'mountPath: /hugegraph-data'
assert_contains "${definition_render}" 'containerPort: 8080'
assert_contains "${definition_render}" 'containerPort: 8182'
assert_contains "${definition_render}" 'name: hugegraph-exporter'
assert_contains "${definition_render}" 'image: docker.io/apecloud/hugegraph-exporter:0.1.0'
assert_contains "${definition_render}" 'containerPort: 9404'
assert_contains "${definition_render}" 'name: HUGEGRAPH_USERNAME'
assert_contains "${definition_render}" 'value: \$\(ADMIN_USER\)'
assert_contains "${definition_render}" 'name: HUGEGRAPH_PASSWORD'
assert_contains "${definition_render}" 'value: \$\(ADMIN_PASSWORD\)'
assert_contains "${definition_render}" 'cpu: 20m'
assert_contains "${definition_render}" 'memory: 32Mi'
assert_contains "${definition_render}" 'cpu: 100m'
assert_contains "${definition_render}" 'memory: 128Mi'
assert_contains "${definition_render}" 'kind: MonitorDefinition'
assert_contains "${definition_render}" 'clusterDefRef: hugegraph'
assert_contains "${definition_render}" 'componentDefRef: hugegraph'
assert_contains "${definition_render}" 'scrapePort: metrics'
assert_contains "${definition_render}" 'metricsPath: /metrics'
assert_contains "${definition_render}" 'collectionInterval: 30s'

assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition") | .spec.runtime.containers | length' "${definition_render}")" \
  "2" \
  "component container count"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition") | .spec.volumes | length' "${definition_render}")" \
  "1" \
  "component volume count"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition") | .spec.volumes[0].name' "${definition_render}")" \
  "data" \
  "component data volume"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition") | .spec.runtime.containers[] | select(.name == "hugegraph") | .volumeMounts | length' "${definition_render}")" \
  "2" \
  "main container volume mounts"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition") | .spec.runtime.containers[] | select(.name == "hugegraph-exporter") | (.volumeMounts // []) | length' "${definition_render}")" \
  "0" \
  "exporter PVC mounts"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition") | .spec.runtime.containers[] | select(.name == "hugegraph-exporter") | .env | length' "${definition_render}")" \
  "2" \
  "exporter credential env count"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition") | .spec.exporter.containerName' "${definition_render}")" \
  "hugegraph-exporter" \
  "spec.exporter container"
assert_equal \
  "$(yq 'select(.kind == "MonitorDefinition") | .spec.components[0].collectors[0].name' "${definition_render}")" \
  "hugegraph-exporter" \
  "MonitorDefinition collector"
assert_contains "${definition_render}" 'terminationGracePeriodSeconds: 30'
assert_contains "${definition_render}" 'preStop:'
assert_contains "${definition_render}" '/scripts/shutdown\.sh'
assert_contains "${cluster_render}" 'clusterDef: hugegraph'
assert_contains "${cluster_render}" 'topology: standalone'
assert_contains "${cluster_render}" 'replicas: 1'
assert_contains "${cluster_render}" 'serviceVersion: [\"]?1\.7\.0[\"]?'

"${ADDON_DIR}/tests/scripts_test.sh"

echo "HugeGraph addon offline contracts passed"
