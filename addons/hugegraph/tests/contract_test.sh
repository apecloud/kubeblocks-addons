#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ADDON_DIR="${ROOT_DIR}/addons/hugegraph"
CLUSTER_DIR="${ROOT_DIR}/addons-cluster/hugegraph"

fail() {
  echo "FAIL: $*" >&2
  exit 1
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

for kind in ClusterDefinition ComponentDefinition ComponentVersion BackupPolicyTemplate ActionSet; do
  rg -q "^kind: ${kind}$" "${definition_render}" || fail "render misses ${kind}"
done

assert_contains "${definition_render}" 'serviceVersion: [\"]?1\.7\.0[\"]?'
assert_contains "${definition_render}" 'image: docker.io/hugegraph/hugegraph:1.7.0'
assert_contains "${definition_render}" 'mountPath: /hugegraph-data'
assert_contains "${definition_render}" 'containerPort: 8080'
assert_contains "${definition_render}" 'containerPort: 8182'
assert_contains "${definition_render}" 'terminationGracePeriodSeconds: 30'
assert_contains "${definition_render}" 'preStop:'
assert_contains "${definition_render}" '/scripts/shutdown\.sh'
assert_contains "${cluster_render}" 'clusterDef: hugegraph'
assert_contains "${cluster_render}" 'topology: standalone'
assert_contains "${cluster_render}" 'replicas: 1'
assert_contains "${cluster_render}" 'serviceVersion: [\"]?1\.7\.0[\"]?'

"${ADDON_DIR}/tests/scripts_test.sh"

echo "HugeGraph addon offline contracts passed"
