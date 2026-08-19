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

cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "${MOCK_BIN}/curl"

cat >"${MOCK_BIN}/dumb-init" <<'MOCK'
#!/usr/bin/env bash
echo "dumb-init should not run" >&2
exit 99
MOCK
chmod +x "${MOCK_BIN}/dumb-init"

mkdir -p "${WORK_ROOT}/hugegraph-store"
printf '#!/usr/bin/env bash\necho entrypoint should not run\nexit 98\n' \
  >"${WORK_ROOT}/hugegraph-store/docker-entrypoint.sh"
chmod +x "${WORK_ROOT}/hugegraph-store/docker-entrypoint.sh"

export PATH="${MOCK_BIN}:/usr/bin:/bin"
export PD_POD_FQDNS=pd-0.pd-headless
export STORE_POD_FQDNS=store-0.store-headless
export POD_NAME=store-0
export HG_STORE_HEALTH_ATTEMPTS=2
export HG_STORE_HEALTH_SLEEP=0
export HG_STORE_DATA_PATH="${WORK_ROOT}/store-data"

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

echo "HugeGraph start-store PD wait tests passed"
