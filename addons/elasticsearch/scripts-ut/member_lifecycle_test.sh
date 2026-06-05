#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKEBIN="$TMP_DIR/bin"
mkdir -p "$FAKEBIN"

cat > "$FAKEBIN/jq" <<'FAKEJQ'
#!/usr/bin/env sh
filter="$*"
input="$(cat)"
case "$filter" in
  *'.version.number'*)
    echo "8.8.2"
    ;;
  *'.status'*)
    echo "green"
    ;;
  *'.acknowledged'*)
    echo "true"
    ;;
  *'contains(["master"])'*)
    echo "false"
    ;;
  *'cluster.routing.allocation.exclude._name'*)
    printf '%s' "$input" | sed -n 's/.*"cluster.routing.allocation.exclude._name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    ;;
  *)
    echo "unsupported jq filter: $filter" >&2
    exit 2
    ;;
esac
FAKEJQ
chmod +x "$FAKEBIN/jq"

cat > "$FAKEBIN/curl" <<'FAKECURL'
#!/usr/bin/env bash
set -euo pipefail

url=""
data=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d)
      data="$2"
      shift 2
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

case "$url" in
  */_cluster/settings*)
    if [ -n "$data" ]; then
      printf '%s\n' "$data" >> "${CURL_SETTINGS_LOG:?}"
      printf '{"acknowledged":true}\n'
    else
      if [ "${MOCK_CLUSTER_SETTINGS_FAIL:-0}" = "1" ]; then
        printf 'settings read failed\n' >&2
        exit 28
      fi
      printf '%s\n' "${MOCK_CLUSTER_SETTINGS_JSON:-{\"persistent\":{},\"transient\":{}}}"
    fi
    ;;
  */_cluster/health*)
    printf '{"status":"green"}\n'
    ;;
  */_cat/shards*)
    count_file="${SHARD_COUNT_FILE:?}"
    count="$(cat "$count_file")"
    if [ "$count" -gt 0 ]; then
      printf 'index shard prirep state docs store ip node\n'
      printf 'idx 0 p STARTED 1 5kb 10.0.0.1 %s\n' "${KB_LEAVE_MEMBER_POD_NAME:-es-data-2}"
      printf '%s' $((count - 1)) > "$count_file"
    fi
    ;;
  */_nodes/*)
    printf '{"nodes":{"n1":{"roles":["data"]}}}\n'
    ;;
  */_cluster/voting_config_exclusions*)
    printf '{"acknowledged":true}\n'
    ;;
  http://127.0.0.1:9200|https://127.0.0.1:9200)
    printf '{"version":{"number":"8.8.2"}}\n'
    ;;
  *)
    printf '{}\n'
    ;;
esac
FAKECURL
chmod +x "$FAKEBIN/curl"

assert_no_success_clear_on_member_leave() {
  CURL_SETTINGS_LOG="$TMP_DIR/leave-settings.log"
  SHARD_COUNT_FILE="$TMP_DIR/leave-shards.count"
  : > "$CURL_SETTINGS_LOG"
  printf '1' > "$SHARD_COUNT_FILE"

  PATH="$FAKEBIN:$PATH" \
  CURL_SETTINGS_LOG="$CURL_SETTINGS_LOG" \
  SHARD_COUNT_FILE="$SHARD_COUNT_FILE" \
  KB_LEAVE_MEMBER_POD_NAME=es-ops-data-2 \
  POD_IP=127.0.0.1 \
  ELASTIC_USER_PASSWORD=secret \
  HEALTH_CHECK_INTERVAL=0 \
  MAX_WAIT_TIME=10 \
  /bin/sh "$ROOT_DIR/scripts/member-leave.sh" > "$TMP_DIR/leave.out" 2> "$TMP_DIR/leave.err"

  grep -q '"cluster.routing.allocation.exclude._name": "es-ops-data-2"' "$CURL_SETTINGS_LOG"
  if grep -q '"cluster.routing.allocation.exclude._name": null' "$CURL_SETTINGS_LOG"; then
    echo "member-leave cleared shard exclusion on success" >&2
    cat "$CURL_SETTINGS_LOG" >&2
    exit 1
  fi
}

assert_member_join_clears_only_self_from_stale_exclusion() {
  CURL_SETTINGS_LOG="$TMP_DIR/join-settings.log"
  SHARD_COUNT_FILE="$TMP_DIR/join-shards.count"
  : > "$CURL_SETTINGS_LOG"
  printf '0' > "$SHARD_COUNT_FILE"

  PATH="$FAKEBIN:$PATH" \
  CURL_SETTINGS_LOG="$CURL_SETTINGS_LOG" \
  SHARD_COUNT_FILE="$SHARD_COUNT_FILE" \
  MOCK_CLUSTER_SETTINGS_JSON='{"persistent":{"cluster.routing.allocation.exclude._name":"es-ops-data-2,other-node"},"transient":{}}' \
  POD_NAME=es-ops-data-2 \
  POD_IP=127.0.0.1 \
  ELASTIC_USER_PASSWORD=secret \
  /bin/sh "$ROOT_DIR/scripts/member-join.sh" > "$TMP_DIR/join.out" 2> "$TMP_DIR/join.err"

  grep -q '"cluster.routing.allocation.exclude._name":"other-node"' "$CURL_SETTINGS_LOG"
  if grep -q 'es-ops-data-2' "$CURL_SETTINGS_LOG"; then
    echo "member-join did not remove only its own stale exclusion" >&2
    cat "$CURL_SETTINGS_LOG" >&2
    exit 1
  fi
}

assert_member_join_clears_self_only_stale_exclusion_to_null() {
  CURL_SETTINGS_LOG="$TMP_DIR/join-null-settings.log"
  SHARD_COUNT_FILE="$TMP_DIR/join-null-shards.count"
  : > "$CURL_SETTINGS_LOG"
  printf '0' > "$SHARD_COUNT_FILE"

  PATH="$FAKEBIN:$PATH" \
  CURL_SETTINGS_LOG="$CURL_SETTINGS_LOG" \
  SHARD_COUNT_FILE="$SHARD_COUNT_FILE" \
  MOCK_CLUSTER_SETTINGS_JSON='{"persistent":{"cluster.routing.allocation.exclude._name":"es-ops-data-2"},"transient":{}}' \
  POD_NAME=es-ops-data-2 \
  POD_IP=127.0.0.1 \
  ELASTIC_USER_PASSWORD=secret \
  /bin/sh "$ROOT_DIR/scripts/member-join.sh" > "$TMP_DIR/join-null.out" 2> "$TMP_DIR/join-null.err"

  grep -q '"cluster.routing.allocation.exclude._name":null' "$CURL_SETTINGS_LOG"
}

assert_member_join_uses_kbagent_pod_name_when_pod_name_missing() {
  CURL_SETTINGS_LOG="$TMP_DIR/join-kbagent-pod-settings.log"
  SHARD_COUNT_FILE="$TMP_DIR/join-kbagent-pod-shards.count"
  : > "$CURL_SETTINGS_LOG"
  printf '0' > "$SHARD_COUNT_FILE"

  PATH="$FAKEBIN:$PATH" \
  CURL_SETTINGS_LOG="$CURL_SETTINGS_LOG" \
  SHARD_COUNT_FILE="$SHARD_COUNT_FILE" \
  MOCK_CLUSTER_SETTINGS_JSON='{"persistent":{"cluster.routing.allocation.exclude._name":"es-ops-data-2,other-node"},"transient":{}}' \
  KB_AGENT_POD_NAME=es-ops-data-2 \
  HOSTNAME=wrong-hostname \
  POD_IP=127.0.0.1 \
  ELASTIC_USER_PASSWORD=secret \
  /bin/sh "$ROOT_DIR/scripts/member-join.sh" > "$TMP_DIR/join-kbagent-pod.out" 2> "$TMP_DIR/join-kbagent-pod.err"

  grep -q '"cluster.routing.allocation.exclude._name":"other-node"' "$CURL_SETTINGS_LOG"
  if grep -q 'es-ops-data-2' "$CURL_SETTINGS_LOG"; then
    echo "member-join did not remove only the KB_AGENT_POD_NAME stale exclusion" >&2
    cat "$CURL_SETTINGS_LOG" >&2
    exit 1
  fi
}

assert_member_join_uses_hostname_when_pod_name_envs_missing() {
  CURL_SETTINGS_LOG="$TMP_DIR/join-hostname-settings.log"
  SHARD_COUNT_FILE="$TMP_DIR/join-hostname-shards.count"
  : > "$CURL_SETTINGS_LOG"
  printf '0' > "$SHARD_COUNT_FILE"

  PATH="$FAKEBIN:$PATH" \
  CURL_SETTINGS_LOG="$CURL_SETTINGS_LOG" \
  SHARD_COUNT_FILE="$SHARD_COUNT_FILE" \
  MOCK_CLUSTER_SETTINGS_JSON='{"persistent":{"cluster.routing.allocation.exclude._name":"es-ops-data-2,other-node"},"transient":{}}' \
  HOSTNAME=es-ops-data-2 \
  POD_IP=127.0.0.1 \
  ELASTIC_USER_PASSWORD=secret \
  /bin/sh "$ROOT_DIR/scripts/member-join.sh" > "$TMP_DIR/join-hostname.out" 2> "$TMP_DIR/join-hostname.err"

  grep -q '"cluster.routing.allocation.exclude._name":"other-node"' "$CURL_SETTINGS_LOG"
  if grep -q 'es-ops-data-2' "$CURL_SETTINGS_LOG"; then
    echo "member-join did not remove only the HOSTNAME stale exclusion" >&2
    cat "$CURL_SETTINGS_LOG" >&2
    exit 1
  fi
}

assert_member_join_fails_closed_without_pod_identity() {
  CURL_SETTINGS_LOG="$TMP_DIR/join-missing-pod-settings.log"
  SHARD_COUNT_FILE="$TMP_DIR/join-missing-pod-shards.count"
  : > "$CURL_SETTINGS_LOG"
  printf '0' > "$SHARD_COUNT_FILE"

  set +e
  PATH="$FAKEBIN:$PATH" \
  CURL_SETTINGS_LOG="$CURL_SETTINGS_LOG" \
  SHARD_COUNT_FILE="$SHARD_COUNT_FILE" \
  MOCK_CLUSTER_SETTINGS_JSON='{"persistent":{"cluster.routing.allocation.exclude._name":"es-ops-data-2"},"transient":{}}' \
  POD_NAME= \
  KB_AGENT_POD_NAME= \
  HOSTNAME= \
  POD_IP=127.0.0.1 \
  ELASTIC_USER_PASSWORD=secret \
  /bin/sh "$ROOT_DIR/scripts/member-join.sh" > "$TMP_DIR/join-missing-pod.out" 2> "$TMP_DIR/join-missing-pod.err"
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "member-join succeeded without pod identity" >&2
    exit 1
  fi
  grep -q 'POD_NAME/KB_AGENT_POD_NAME/HOSTNAME are empty' "$TMP_DIR/join-missing-pod.err"
  [ ! -s "$CURL_SETTINGS_LOG" ]
}

assert_member_join_fails_closed_when_settings_read_fails() {
  CURL_SETTINGS_LOG="$TMP_DIR/join-settings-read-fail.log"
  SHARD_COUNT_FILE="$TMP_DIR/join-settings-read-fail-shards.count"
  : > "$CURL_SETTINGS_LOG"
  printf '0' > "$SHARD_COUNT_FILE"

  set +e
  PATH="$FAKEBIN:$PATH" \
  CURL_SETTINGS_LOG="$CURL_SETTINGS_LOG" \
  SHARD_COUNT_FILE="$SHARD_COUNT_FILE" \
  MOCK_CLUSTER_SETTINGS_FAIL=1 \
  POD_NAME=es-ops-data-2 \
  POD_IP=127.0.0.1 \
  ELASTIC_USER_PASSWORD=secret \
  /bin/sh "$ROOT_DIR/scripts/member-join.sh" > "$TMP_DIR/join-settings-read-fail.out" 2> "$TMP_DIR/join-settings-read-fail.err"
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "member-join succeeded after cluster settings read failure" >&2
    exit 1
  fi
  grep -q 'failed to read cluster settings' "$TMP_DIR/join-settings-read-fail.err"
  [ ! -s "$CURL_SETTINGS_LOG" ]
}

assert_no_success_clear_on_member_leave
assert_member_join_clears_only_self_from_stale_exclusion
assert_member_join_clears_self_only_stale_exclusion_to_null
assert_member_join_uses_kbagent_pod_name_when_pod_name_missing
assert_member_join_uses_hostname_when_pod_name_envs_missing
assert_member_join_fails_closed_without_pod_identity
assert_member_join_fails_closed_when_settings_read_fails

echo "member lifecycle tests passed"
