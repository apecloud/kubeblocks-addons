#!/usr/bin/env bash

set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local output="$1"
  local expected="$2"

  grep -Fq -- "$expected" <<<"$output" || fail "expected rendered Cluster to contain: $expected"
}

assert_not_contains() {
  local output="$1"
  local unexpected="$2"

  if grep -Fq -- "$unexpected" <<<"$output"; then
    fail "expected rendered Cluster not to contain: $unexpected"
  fi
}

render_cluster() {
  helm template restore-test "$chart_dir" \
    --namespace restore-test \
    --show-only templates/cluster.yaml \
    "$@"
}

helm dependency build --skip-refresh "$chart_dir" >/dev/null

default_render="$(render_cluster)"
assert_not_contains "$default_render" "  annotations:"
assert_not_contains "$default_render" "  restore:"

modern_render="$(render_cluster \
  --set-string restore.source.apiGroup=dataprotection.kubeblocks.io \
  --set-string restore.source.kind=Backup \
  --set-string restore.source.name=mssql-backup \
  --set-string restore.source.namespace=backup-ns \
  --set-string restore.pitr=2026-07-10T08:00:00Z \
  --set-string 'restore.parameters.dataprotection\.kubeblocks\.io/volume-restore-policy=Parallel')"
assert_contains "$modern_render" "  restore:"
assert_contains "$modern_render" "      dataprotection.kubeblocks.io/volume-restore-policy: Parallel"
assert_contains "$modern_render" "    pitr: \"2026-07-10T08:00:00Z\""
assert_contains "$modern_render" "      apiGroup: dataprotection.kubeblocks.io"
assert_contains "$modern_render" "      kind: Backup"
assert_contains "$modern_render" "      name: mssql-backup"
assert_contains "$modern_render" "      namespace: backup-ns"
assert_not_contains "$modern_render" "kubeblocks.io/restore-from-backup:"

legacy_render="$(render_cluster --set-string restoreFrom=legacy-backup)"
assert_contains "$legacy_render" "kubeblocks.io/restore-from-backup: 'legacy-backup'"
assert_not_contains "$legacy_render" "  restore:"

precedence_render="$(render_cluster \
  --set hostNetworkEnabled=true \
  --set-string restoreFrom=legacy-backup \
  --set-string restore.source.apiGroup=dataprotection.kubeblocks.io \
  --set-string restore.source.kind=Backup \
  --set-string restore.source.name=modern-backup)"
assert_contains "$precedence_render" "kubeblocks.io/host-network: \"mssql\""
assert_contains "$precedence_render" "  restore:"
assert_contains "$precedence_render" "      name: modern-backup"
assert_not_contains "$precedence_render" "kubeblocks.io/restore-from-backup:"

printf 'PASS: mssql restore render contract\n'
