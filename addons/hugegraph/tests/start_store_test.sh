#!/usr/bin/env bash
set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADDON_DIR=$(cd "${TEST_DIR}/.." && pwd)
WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hugegraph-start-store-test.XXXXXX")
MOCK_BIN="${WORK_ROOT}/bin"

cleanup() {
  rm -rf -- "$WORK_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$MOCK_BIN"

cat >"${MOCK_BIN}/dumb-init" <<'MOCK'
#!/usr/bin/env bash
echo "dumb-init should not run" >&2
exit 99
MOCK
chmod +x "${MOCK_BIN}/dumb-init"

export PATH="${MOCK_BIN}:/usr/bin:/bin"
export STORE_POD_FQDNS=store-0.store-headless
export POD_NAME=store-0
export HG_STORE_HEALTH_ATTEMPTS=2
export HG_STORE_HEALTH_SLEEP=0
export HG_STORE_DATA_PATH="${WORK_ROOT}/store-data"

# 1) Every PD down — fail closed.
cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "${MOCK_BIN}/curl"

export PD_POD_FQDNS=pd-0.pd-headless
unset HG_STORE_DRY_RUN || true
set +e
(
  cd "$WORK_ROOT"
  bash "${ADDON_DIR}/scripts/start-store.sh"
) >"${WORK_ROOT}/out" 2>"${WORK_ROOT}/err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "start-store.sh continued after PD health never succeeded"
if grep -q 'should not run' "${WORK_ROOT}/out" "${WORK_ROOT}/err"; then
  fail "start-store.sh reached entrypoint after PD health failed"
fi
grep -q 'PD is not healthy' "${WORK_ROOT}/err" \
  || fail "start-store.sh did not report PD health failure"

# 2) Only the first PD is healthy — official 3-PD compose waits for all.
cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
  case "$arg" in
    http://*) url=$arg ;;
  esac
done
case "$url" in
  *pd-0.pd-headless:8620*) exit 0 ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "${MOCK_BIN}/curl"

export PD_POD_FQDNS=pd-0.pd-headless,pd-1.pd-headless,pd-2.pd-headless
set +e
(
  cd "$WORK_ROOT"
  bash "${ADDON_DIR}/scripts/start-store.sh"
) >"${WORK_ROOT}/out-partial" 2>"${WORK_ROOT}/err-partial"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "start-store.sh continued when only the first PD was healthy"
grep -q 'pd-1.pd-headless:8620' "${WORK_ROOT}/err-partial" \
  || fail "start-store.sh did not report the unhealthy later PD"

# 3) All PDs healthy — proceed (dry-run, do not exec the image entrypoint).
cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "${MOCK_BIN}/curl"

export HG_STORE_DRY_RUN=1
(
  cd "$WORK_ROOT"
  bash "${ADDON_DIR}/scripts/start-store.sh"
) >"${WORK_ROOT}/out-ok" 2>"${WORK_ROOT}/err-ok"
grep -qx 'pds_healthy=3' "${WORK_ROOT}/out-ok" \
  || fail "all-PD wait did not report pds_healthy=3: $(cat "${WORK_ROOT}/out-ok" "${WORK_ROOT}/err-ok")"

echo "HugeGraph start-store PD wait tests passed"
