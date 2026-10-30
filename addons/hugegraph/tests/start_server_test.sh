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

cat >"${MOCK_BIN}/dumb-init" <<'MOCK'
#!/usr/bin/env bash
echo "dumb-init should not run" >&2
exit 99
MOCK
chmod +x "${MOCK_BIN}/dumb-init"

export PATH="${MOCK_BIN}:/usr/bin:/bin"
export PD_POD_FQDNS=pd-0.pd-headless
export HG_SERVER_HEALTH_ATTEMPTS=2
export HG_SERVER_HEALTH_SLEEP=0

# 1) Every Store down — fail closed.
cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "${MOCK_BIN}/curl"

export STORE_POD_FQDNS=store-0.store-headless
unset HG_SERVER_DRY_RUN || true
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

# 2) Only the first Store is healthy — official 3-store compose waits for all.
cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
  case "$arg" in
    http://*) url=$arg ;;
  esac
done
case "$url" in
  *store-0.store-headless:8520*) exit 0 ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "${MOCK_BIN}/curl"

export STORE_POD_FQDNS=store-0.store-headless,store-1.store-headless,store-2.store-headless
set +e
(
  cd "$WORK_ROOT"
  bash "${ADDON_DIR}/scripts/start-server.sh"
) >"${WORK_ROOT}/out-partial" 2>"${WORK_ROOT}/err-partial"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "start-server.sh continued when only the first Store was healthy"
grep -q 'store-1.store-headless:8520' "${WORK_ROOT}/err-partial" \
  || fail "start-server.sh did not report the unhealthy later Store"

# 3) All Stores healthy — proceed (dry-run, do not exec the image entrypoint).
cat >"${MOCK_BIN}/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "${MOCK_BIN}/curl"

export HG_SERVER_DRY_RUN=1
(
  cd "$WORK_ROOT"
  bash "${ADDON_DIR}/scripts/start-server.sh"
) >"${WORK_ROOT}/out-ok" 2>"${WORK_ROOT}/err-ok"
grep -qx 'stores_healthy=3' "${WORK_ROOT}/out-ok" \
  || fail "all-Store wait did not report stores_healthy=3: $(cat "${WORK_ROOT}/out-ok" "${WORK_ROOT}/err-ok")"

# Empty Store FQDNs must fail closed before any health wait.
export HG_SERVER_DRY_RUN=1
export PD_POD_FQDNS=pd-0.pd-headless
export STORE_POD_FQDNS=
set +e
(
  cd "$WORK_ROOT"
  bash "${ADDON_DIR}/scripts/start-server.sh"
) >"${WORK_ROOT}/out-empty-store" 2>"${WORK_ROOT}/err-empty-store"
empty_store_rc=$?
set -e
[[ "$empty_store_rc" -ne 0 ]] || fail "start-server.sh continued with empty STORE_POD_FQDNS"
grep -q 'STORE_POD_FQDNS is required' "${WORK_ROOT}/err-empty-store" \
  || fail "start-server.sh did not refuse empty STORE_POD_FQDNS"

export STORE_POD_FQDNS=,
set +e
(
  cd "$WORK_ROOT"
  bash "${ADDON_DIR}/scripts/start-server.sh"
) >"${WORK_ROOT}/out-blank-store" 2>"${WORK_ROOT}/err-blank-store"
blank_store_rc=$?
set -e
[[ "$blank_store_rc" -ne 0 ]] || fail "start-server.sh continued with comma-only STORE_POD_FQDNS"
grep -q 'cannot derive Store list' "${WORK_ROOT}/err-blank-store" \
  || fail "start-server.sh did not report comma-only STORE_POD_FQDNS"

echo "HugeGraph start-server Store wait tests passed"
