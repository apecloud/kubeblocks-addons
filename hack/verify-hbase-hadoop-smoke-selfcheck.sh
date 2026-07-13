#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "missing expected content: $needle" >&2
    return 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq "$needle" "$file"; then
    echo "unexpected content found: $needle" >&2
    return 1
  fi
}

bash -n "${ROOT_DIR}/hack/verify-hbase-hadoop-smoke.sh"
bash "${ROOT_DIR}/hack/verify-hbase-hadoop-smoke.sh" --dry-run > "${TMP_DIR}/smoke.out"

assert_contains "${TMP_DIR}/smoke.out" "执行 HDFS standalone smoke"
assert_contains "${TMP_DIR}/smoke.out" "执行 HDFS HA smoke"
assert_contains "${TMP_DIR}/smoke.out" "执行 HBase standalone smoke"
assert_contains "${TMP_DIR}/smoke.out" "执行 HBase + HDFS smoke"
assert_contains "${TMP_DIR}/smoke.out" "getconf -confKey dfs.nameservices"
assert_contains "${TMP_DIR}/smoke.out" 'dfs.ha.namenodes.${ns}'
assert_contains "${TMP_DIR}/smoke.out" 'haadmin -getServiceState "${id}"'
assert_not_contains "${TMP_DIR}/smoke.out" "haadmin\\ -getServiceState\\ nn0"
assert_contains "${TMP_DIR}/smoke.out" "dfs\\ -mkdir\\ -p"
assert_contains "${TMP_DIR}/smoke.out" "status \\'simple\\'"
assert_contains "${TMP_DIR}/smoke.out" "org.apache.hadoop.fs.FsShell\\ -test\\ -d"

echo "smoke self-check passed"
