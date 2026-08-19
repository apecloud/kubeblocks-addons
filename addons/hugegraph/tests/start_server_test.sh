#!/usr/bin/env bash
set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADDON_DIR=$(cd "${TEST_DIR}/.." && pwd)
WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hugegraph-start-server-test.XXXXXX")
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

export PATH="${MOCK_BIN}:/usr/bin:/bin"
export PD_POD_FQDNS=pd-0.pd-headless
export STORE_POD_FQDNS=store-0.store-headless
export HG_SERVER_HEALTH_ATTEMPTS=2
export HG_SERVER_HEALTH_SLEEP=0

set +e
(
  cd "$WORK_ROOT"
  bash "${ADDON_DIR}/scripts/start-server.sh"
) >"${WORK_ROOT}/out" 2>"${WORK_ROOT}/err"
rc=$?
set -e

[[ "$rc" -ne 0 ]] || fail "start-server.sh continued after Store health never succeeded"
if grep -q 'should not run' "${WORK_ROOT}/out" "${WORK_ROOT}/err"; then
  fail "start-server.sh reached entrypoint after Store health failed"
fi
grep -q 'Store is not healthy' "${WORK_ROOT}/err" \
  || fail "start-server.sh did not report Store health failure"

echo "HugeGraph start-server Store wait tests passed"
