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
  "${ADDON_DIR}/scripts/start-pd.sh"
  "${ADDON_DIR}/scripts/start-store.sh"
  "${ADDON_DIR}/scripts/start-server.sh"
  "${ADDON_DIR}/scripts/shutdown.sh"
  "${ADDON_DIR}/scripts/backup.sh"
  "${ADDON_DIR}/scripts/restore.sh"
  "${ADDON_DIR}/templates/cmpd-pd.yaml"
  "${ADDON_DIR}/templates/cmpd-store.yaml"
  "${ADDON_DIR}/templates/cmpd-server.yaml"
  "${ADDON_DIR}/tests/scripts_test.sh"
  "${ADDON_DIR}/tests/start_pd_test.sh"
  "${ADDON_DIR}/tests/start_store_test.sh"
  "${ADDON_DIR}/tests/start_server_test.sh"
  "${ADDON_DIR}/exporter/Dockerfile"
  "${ROOT_DIR}/examples/hugegraph/cluster-distributed.yaml"
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
  "${ADDON_DIR}/scripts/start-pd.sh" \
  "${ADDON_DIR}/scripts/start-store.sh" \
  "${ADDON_DIR}/scripts/start-server.sh" \
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
assert_contains "${definition_render}" 'image: docker.io/apecloud/hugegraph-exporter:0.1.1'
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
  "$(yq 'select(.kind == "ComponentDefinition" and .metadata.name == "hugegraph-1.0.0") | .spec.runtime.containers | length' "${definition_render}")" \
  "2" \
  "standalone container count"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition" and .metadata.name == "hugegraph-1.0.0") | .spec.volumes | length' "${definition_render}")" \
  "1" \
  "standalone volume count"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition" and .metadata.name == "hugegraph-1.0.0") | .spec.volumes[0].name' "${definition_render}")" \
  "data" \
  "standalone data volume"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition" and .metadata.name == "hugegraph-1.0.0") | .spec.runtime.containers[] | select(.name == "hugegraph") | .volumeMounts | length' "${definition_render}")" \
  "2" \
  "main container volume mounts"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition" and .metadata.name == "hugegraph-1.0.0") | .spec.runtime.containers[] | select(.name == "hugegraph-exporter") | (.volumeMounts // []) | length' "${definition_render}")" \
  "0" \
  "exporter PVC mounts"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition" and .metadata.name == "hugegraph-1.0.0") | .spec.runtime.containers[] | select(.name == "hugegraph-exporter") | .env | length' "${definition_render}")" \
  "2" \
  "exporter credential env count"
assert_equal \
  "$(yq 'select(.kind == "ComponentDefinition" and .metadata.name == "hugegraph-1.0.0") | .spec.exporter.containerName' "${definition_render}")" \
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

assert_contains "${definition_render}" 'name: distributed'
assert_contains "${definition_render}" 'name: hugegraph-pd-1.0.0'
assert_contains "${definition_render}" 'name: hugegraph-store-1.0.0'
assert_contains "${definition_render}" 'name: hugegraph-server-1.0.0'
assert_contains "${definition_render}" 'compDef: \^hugegraph-\[0-9\]'
assert_contains "${definition_render}" 'compDef: \^hugegraph-pd-'
assert_contains "${definition_render}" 'docker.io/hugegraph/pd:1.7.0'
assert_contains "${definition_render}" 'docker.io/hugegraph/store:1.7.0'
assert_contains "${definition_render}" 'docker.io/hugegraph/server:1.7.0'
assert_contains "${ADDON_DIR}/scripts/start-pd.sh" 'HG_PD_RAFT_PEERS_LIST'
assert_contains "${ADDON_DIR}/scripts/start-pd.sh" 'HG_PD_RAFT_ADDRESS'
assert_contains "${ADDON_DIR}/scripts/start-pd.sh" 'HG_PD_INITIAL_STORE_COUNT='
assert_contains "${ADDON_DIR}/scripts/start-pd.sh" 'count_hosts'
assert_contains "${ADDON_DIR}/scripts/start-store.sh" 'HG_STORE_PD_ADDRESS'
assert_contains "${ADDON_DIR}/scripts/start-store.sh" 'PD is not healthy'
assert_contains "${ADDON_DIR}/scripts/start-store.sh" 'HG_STORE_HEALTH_ATTEMPTS:-90'
assert_contains "${ADDON_DIR}/scripts/start-server.sh" 'HG_SERVER_BACKEND=hstore'
assert_contains "${ADDON_DIR}/scripts/start-server.sh" 'Store is not healthy'
assert_contains "${ADDON_DIR}/scripts/start-server.sh" 'HG_SERVER_HEALTH_ATTEMPTS:-90'
assert_equal \
  "$(yq ea '[select(.kind == "ComponentDefinition" and .metadata.name == "hugegraph-store-1.0.0") | .spec.runtime.containers[] | select(.name == "store") | .startupProbe.failureThreshold] | .[0]' "${definition_render}" | tr -d '\n')" \
  "72" \
  "store startupProbe covers PD wait plus process start"
assert_equal \
  "$(yq ea '[select(.kind == "ComponentDefinition" and .metadata.name == "hugegraph-server-1.0.0") | .spec.runtime.containers[] | select(.name == "server") | .startupProbe.failureThreshold] | .[0]' "${definition_render}" | tr -d '\n')" \
  "72" \
  "server startupProbe covers Store wait plus process start"
assert_contains "${ROOT_DIR}/examples/hugegraph/cluster-distributed.yaml" 'topology: distributed'
assert_contains "${ROOT_DIR}/examples/hugegraph/cluster-distributed.yaml" 'name: pd'
assert_contains "${ROOT_DIR}/examples/hugegraph/cluster-distributed.yaml" 'name: store'
assert_contains "${ADDON_DIR}/README.md" 'Topology `distributed`'
assert_contains "${ADDON_DIR}/README.md" 'Distributed backup/restore'
assert_contains "${ADDON_DIR}/README.md" 'Store scale-in/rebalance is not supported'
assert_contains "${ADDON_DIR}/README.md" 'matches only the standalone Server ComponentDefinition'
assert_contains "${ADDON_DIR}/README.md" 'do not declare `systemAccounts`'
assert_contains "${ADDON_DIR}/README.md" 'no generated admin Secret'
assert_equal \
  "$(yq '[select(.kind == "BackupPolicyTemplate") | .spec.compDefs[]] | join(",")' "${definition_render}" | tr -d '\n')" \
  "^hugegraph-[0-9]" \
  "BPT matches only standalone server"
assert_equal \
  "$(yq ea '[select(.kind == "ComponentDefinition" and (.metadata.name == "hugegraph-pd-1.0.0" or .metadata.name == "hugegraph-store-1.0.0" or .metadata.name == "hugegraph-server-1.0.0")) | .spec | has("systemAccounts")] | map(select(. == true)) | length' "${definition_render}" | tr -d '\n')" \
  "0" \
  "distributed CmpDs have no systemAccounts"

distributed_render=$(mktemp)
helm template hugegraph "${CLUSTER_DIR}" --namespace demo --set topology=distributed >"${distributed_render}"
assert_contains "${distributed_render}" 'topology: distributed'
assert_contains "${distributed_render}" 'name: pd'
assert_contains "${distributed_render}" 'name: store'
assert_equal \
  "$(yq '[select(.kind == "Cluster") | .spec.componentSpecs[].name] | join(",")' "${distributed_render}")" \
  "pd,store,server" \
  "distributed component names"
rm -f "${distributed_render}"
schema="${CLUSTER_DIR}/values.schema.json"
assert_file "${schema}"
assert_equal \
  "$(yq -oy '.properties.topology.enum | join(",")' "${schema}")" \
  "standalone,distributed" \
  "cluster schema topology enum"
assert_equal \
  "$(yq -oy '[.properties.distributed.properties.pdReplicas.default, .properties.distributed.properties.storeReplicas.default, .properties.distributed.properties.serverReplicas.default] | join("/")' "${schema}")" \
  "3/3/1" \
  "cluster schema claimed distributed defaults"
assert_contains "${ADDON_DIR}/.helmignore" '^exporter/'

package_dir=$(mktemp -d)
trap 'rm -f "${definition_render}" "${cluster_render}"; rm -rf "${package_dir}"' EXIT
helm package "${ADDON_DIR}" -d "${package_dir}" >/dev/null
package_tgz=$(echo "${package_dir}"/hugegraph-*.tgz)
[[ -f "${package_tgz}" ]] || fail "helm package missing"
if tar tzf "${package_tgz}" | grep -E '(^|/)exporter/'; then
  fail "packaged chart includes exporter/ source"
fi
package_bytes=$(wc -c < "${package_tgz}" | tr -d ' ')
[[ "${package_bytes}" -lt 100000 ]] || fail "packaged chart too large: ${package_bytes} bytes"

"${ADDON_DIR}/tests/scripts_test.sh"
"${ADDON_DIR}/tests/start_pd_test.sh"
"${ADDON_DIR}/tests/start_store_test.sh"
"${ADDON_DIR}/tests/start_server_test.sh"

echo "HugeGraph addon offline contracts passed"
