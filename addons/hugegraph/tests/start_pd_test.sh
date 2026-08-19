#!/usr/bin/env bash
set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADDON_DIR=$(cd "${TEST_DIR}/.." && pwd)
WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hugegraph-start-pd-test.XXXXXX")

cleanup() {
  rm -rf -- "$WORK_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_start_pd() {
  local out=$1
  local err=$2
  (
    export HG_PD_DRY_RUN=1
    export HG_PD_DATA_PATH="${WORK_ROOT}/pd-data"
    export PD_POD_FQDNS STORE_POD_FQDNS POD_NAME
    if [ -n "${HG_PD_INITIAL_STORE_COUNT+x}" ]; then
      export HG_PD_INITIAL_STORE_COUNT
    fi
    bash "${ADDON_DIR}/scripts/start-pd.sh"
  ) >"${out}" 2>"${err}"
}

# 3-store list must set initial-store-count to 3 (official 3x3 bootstrap).
unset HG_PD_INITIAL_STORE_COUNT || true
PD_POD_FQDNS=pd-0.pd-headless,pd-1.pd-headless,pd-2.pd-headless \
STORE_POD_FQDNS=store-0.store-headless,store-1.store-headless,store-2.store-headless \
POD_NAME=pd-0 \
run_start_pd "${WORK_ROOT}/out3" "${WORK_ROOT}/err3"
grep -qx 'HG_PD_INITIAL_STORE_COUNT=3' "${WORK_ROOT}/out3" \
  || fail "3-store FQDNs did not yield HG_PD_INITIAL_STORE_COUNT=3: $(cat "${WORK_ROOT}/out3" "${WORK_ROOT}/err3")"
grep -q 'HG_PD_INITIAL_STORE_LIST=store-0.store-headless:8500,store-1.store-headless:8500,store-2.store-headless:8500' \
  "${WORK_ROOT}/out3" \
  || fail "3-store FQDNs did not build the store list"

# 1-store list must stay at 1.
PD_POD_FQDNS=pd-0.pd-headless \
STORE_POD_FQDNS=store-0.store-headless \
POD_NAME=pd-0 \
run_start_pd "${WORK_ROOT}/out1" "${WORK_ROOT}/err1"
grep -qx 'HG_PD_INITIAL_STORE_COUNT=1' "${WORK_ROOT}/out1" \
  || fail "1-store FQDNs did not yield HG_PD_INITIAL_STORE_COUNT=1"

# Explicit override wins.
PD_POD_FQDNS=pd-0.pd-headless,pd-1.pd-headless,pd-2.pd-headless \
STORE_POD_FQDNS=store-0.store-headless,store-1.store-headless,store-2.store-headless \
POD_NAME=pd-0 \
HG_PD_INITIAL_STORE_COUNT=5 \
run_start_pd "${WORK_ROOT}/out5" "${WORK_ROOT}/err5"
grep -qx 'HG_PD_INITIAL_STORE_COUNT=5' "${WORK_ROOT}/out5" \
  || fail "explicit HG_PD_INITIAL_STORE_COUNT=5 was not honored"

echo "HugeGraph start-pd initial store count tests passed"
