#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADDON_DIR=$(cd "${TEST_DIR}/.." && pwd)
WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hugegraph-scripts-test.XXXXXX")
DATA_ROOT="${WORK_ROOT}/data"
REPO_ROOT="${WORK_ROOT}/repo"
MOCK_BIN="${WORK_ROOT}/bin"
BACKUP_INFO="${WORK_ROOT}/backup-info.json"
BACKUP_NAME=hugegraph-test-backup

cleanup() {
  rm -rf -- "$WORK_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if [[ -x /opt/homebrew/bin/bash ]]; then
  PRODUCT_BASH=/opt/homebrew/bin/bash
elif (( BASH_VERSINFO[0] >= 4 )); then
  PRODUCT_BASH=$BASH
else
  fail "HugeGraph script tests require Bash 4 or newer"
fi

mkdir -p "$MOCK_BIN" "$REPO_ROOT"

cat >"${MOCK_BIN}/datasafed" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
: "${TEST_REPO_ROOT:?TEST_REPO_ROOT is required}"
command_name=$1
shift
case "$command_name" in
  push)
    source_path=$1
    destination=$2
    destination=${destination#/}
    mkdir -p "${TEST_REPO_ROOT}/$(dirname "$destination")"
    if [[ "$source_path" == "-" ]]; then
      cat >"${TEST_REPO_ROOT}/${destination}"
    else
      cp "$source_path" "${TEST_REPO_ROOT}/${destination}"
    fi
    ;;
  pull)
    source_path=${1#/}
    destination=$2
    if [[ "$destination" == "-" ]]; then
      cat "${TEST_REPO_ROOT}/${source_path}"
    else
      cp "${TEST_REPO_ROOT}/${source_path}" "$destination"
    fi
    ;;
  stat)
    printf 'TotalSize 4096\n'
    ;;
  *)
    echo "unsupported datasafed command: ${command_name}" >&2
    exit 2
    ;;
esac
MOCK

cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
: "${DATA_ROOT:?DATA_ROOT is required}"
url=${!#}
graph_name=${url##*/graphs/}
graph_name=${graph_name%%/*}
if [[ "${MOCK_CURL_FAIL_GRAPH:-}" == "$graph_name" ]]; then
  exit 22
fi
config="${DATA_ROOT}/graphs/${graph_name}.properties"
data_path=$(awk -F= '$1 == "rocksdb.data_path" {print substr($0, index($0, "=") + 1); exit}' "$config")
snapshot="${DATA_ROOT}/snapshot_$(basename "$data_path")"
for store in g m s; do
  mkdir -p "${snapshot}/${store}"
  printf '%s-%s\n' "$graph_name" "$store" >"${snapshot}/${store}/CURRENT"
done
MOCK

chmod +x "${MOCK_BIN}/datasafed" "${MOCK_BIN}/curl"

write_graph_config() {
  local root=$1
  local graph=$2
  local suffix=$3

  mkdir -p "${root}/graphs"
  cat >"${root}/graphs/${graph}.properties" <<EOF_CONFIG
gremlin.graph=org.apache.hugegraph.auth.HugeFactoryAuthProxy
backend=rocksdb
serializer=binary
store=${graph}
rocksdb.data_path=${root}/rocksdb${suffix}
rocksdb.wal_path=${root}/wal${suffix}
EOF_CONFIG
}

run_backup() {
  env \
    PATH="${MOCK_BIN}:${PATH}" \
    TEST_REPO_ROOT="$REPO_ROOT" \
    DATA_ROOT="$DATA_ROOT" \
    DP_DATASAFED_BIN_PATH="$MOCK_BIN" \
    DP_BACKUP_BASE_PATH=/test \
    DP_BACKUP_NAME="$BACKUP_NAME" \
    DP_BACKUP_INFO_FILE="$BACKUP_INFO" \
    DP_DB_HOST=hugegraph \
    DP_DB_USER=admin \
    DP_DB_PASSWORD=secret \
    "$PRODUCT_BASH" "${ADDON_DIR}/scripts/backup.sh"
}

run_restore() {
  env \
    PATH="${MOCK_BIN}:${PATH}" \
    TEST_REPO_ROOT="$REPO_ROOT" \
    DATA_ROOT="$DATA_ROOT" \
    DP_DATASAFED_BIN_PATH="$MOCK_BIN" \
    DP_BACKUP_BASE_PATH=/test \
    DP_BACKUP_NAME="$BACKUP_NAME" \
    "$PRODUCT_BASH" "${ADDON_DIR}/scripts/restore.sh"
}

write_graph_config "$DATA_ROOT" hugegraph ""
write_graph_config "$DATA_ROOT" analytics "_analytics"
run_backup

[[ -f "${REPO_ROOT}/manifest.properties" ]] || fail "backup manifest was not uploaded"
[[ -f "${REPO_ROOT}/checksums.sha256" ]] || fail "backup checksums were not uploaded"
[[ -f "${REPO_ROOT}/payload.tar.gz" ]] || fail "backup payload was not uploaded"
[[ -f "$BACKUP_INFO" ]] || fail "backup info was not written"
[[ -z "$(find "$DATA_ROOT" -maxdepth 1 -type d -name 'snapshot_*' -print -quit)" ]] || fail "backup left checkpoint directories behind"

rm -rf -- "$DATA_ROOT"
mkdir -p "$DATA_ROOT"
run_restore

[[ -f "${DATA_ROOT}/graphs/hugegraph.properties" ]] || fail "restore missed the graph config"
[[ -f "${DATA_ROOT}/graphs/analytics.properties" ]] || fail "restore missed the second graph config"
[[ -f "${DATA_ROOT}/rocksdb/g/CURRENT" ]] || fail "restore missed checkpoint data"
[[ -f "${DATA_ROOT}/rocksdb_analytics/g/CURRENT" ]] || fail "restore missed the second graph checkpoint"
[[ -f "${DATA_ROOT}/docker/init_complete" ]] || fail "restore missed the HugeGraph init marker"
[[ "$(<"${DATA_ROOT}/.kb-restored-backup")" == "$BACKUP_NAME" ]] || fail "restore completion marker is wrong"

run_restore

printf 'corrupt\n' >"${DATA_ROOT}/rocksdb/g/CURRENT"
if run_restore >/dev/null 2>&1; then
  fail "idempotent restore accepted corrupted completed data"
fi

rm -f -- "${DATA_ROOT}/.kb-restored-backup"
printf '%s\n' "$BACKUP_NAME" >"${DATA_ROOT}/.kb-restore-in-progress"
run_restore
[[ "$(<"${DATA_ROOT}/rocksdb/g/CURRENT")" == "hugegraph-g" ]] || fail "retry did not replace partial checkpoint data"
[[ "$(<"${DATA_ROOT}/rocksdb_analytics/g/CURRENT")" == "analytics-g" ]] || fail "retry lost the second graph checkpoint"

FAIL_DATA_ROOT="${WORK_ROOT}/failed-backup-data"
write_graph_config "$FAIL_DATA_ROOT" hugegraph ""
write_graph_config "$FAIL_DATA_ROOT" analytics "_analytics"
if env \
  PATH="${MOCK_BIN}:${PATH}" \
  TEST_REPO_ROOT="$REPO_ROOT" \
  DATA_ROOT="$FAIL_DATA_ROOT" \
  MOCK_CURL_FAIL_GRAPH=hugegraph \
  DP_DATASAFED_BIN_PATH="$MOCK_BIN" \
  DP_BACKUP_BASE_PATH=/test-failure \
  DP_BACKUP_NAME=failed-backup \
  DP_BACKUP_INFO_FILE="${WORK_ROOT}/failed-backup-info.json" \
  DP_DB_HOST=hugegraph \
  DP_DB_USER=admin \
  DP_DB_PASSWORD=secret \
  "$PRODUCT_BASH" "${ADDON_DIR}/scripts/backup.sh" >/dev/null 2>&1; then
  fail "backup unexpectedly succeeded after checkpoint API failure"
fi
[[ -z "$(find "$FAIL_DATA_ROOT" -maxdepth 1 -type d -name 'snapshot_*' -print -quit)" ]] || fail "failed backup left checkpoint directories behind"

PREEXIST_DATA_ROOT="${WORK_ROOT}/preexisting-backup-data"
write_graph_config "$PREEXIST_DATA_ROOT" hugegraph ""
mkdir -p "${PREEXIST_DATA_ROOT}/snapshot_manual"
printf 'preserve\n' >"${PREEXIST_DATA_ROOT}/snapshot_manual/CURRENT"
if env \
  PATH="${MOCK_BIN}:${PATH}" \
  TEST_REPO_ROOT="$REPO_ROOT" \
  DATA_ROOT="$PREEXIST_DATA_ROOT" \
  DP_DATASAFED_BIN_PATH="$MOCK_BIN" \
  DP_BACKUP_BASE_PATH=/test-preexisting \
  DP_BACKUP_NAME=preexisting-backup \
  DP_BACKUP_INFO_FILE="${WORK_ROOT}/preexisting-backup-info.json" \
  DP_DB_HOST=hugegraph \
  DP_DB_USER=admin \
  DP_DB_PASSWORD=secret \
  "$PRODUCT_BASH" "${ADDON_DIR}/scripts/backup.sh" >/dev/null 2>&1; then
  fail "backup unexpectedly accepted a pre-existing checkpoint"
fi
[[ "$(<"${PREEXIST_DATA_ROOT}/snapshot_manual/CURRENT")" == "preserve" ]] || fail "backup removed a pre-existing checkpoint"

echo "HugeGraph backup/restore script tests passed"
