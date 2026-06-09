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
  *'.persistent.cluster.routing.allocation.exclude._name'*)
    printf '%s' "$input" | sed -n 's/.*"_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    ;;
  *)
    echo "unsupported jq filter: $filter" >&2
    exit 2
    ;;
esac
FAKEJQ
chmod +x "$FAKEBIN/jq"

cat > "$FAKEBIN/seq" <<'FAKESEQ'
#!/usr/bin/env sh
echo 1
FAKESEQ
chmod +x "$FAKEBIN/seq"

cat > "$FAKEBIN/sleep" <<'FAKESLEEP'
#!/usr/bin/env sh
:
FAKESLEEP
chmod +x "$FAKEBIN/sleep"

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
  */_cluster/health\?local=true)
    if [ "${MOCK_LOCAL_API_READY:-1}" = "1" ]; then
      printf '{"status":"green"}\n'
    else
      exit 28
    fi
    ;;
  */_cluster/settings\?include_defaults=false)
    printf '%s\n' "${MOCK_CLUSTER_SETTINGS_JSON:-{\"persistent\":{\"cluster\":{\"routing\":{\"allocation\":{\"exclude\":{}}}}}}}"
    ;;
  */_cluster/settings)
    if [ -n "$data" ]; then
      printf '%s\n' "$data" >> "${CURL_SETTINGS_LOG:?}"
      printf '{"acknowledged":true}\n'
    else
      printf '{}\n'
    fi
    ;;
  *)
    printf '{}\n'
    ;;
esac
FAKECURL
chmod +x "$FAKEBIN/curl"

source_post_start_hook() {
  export ES_POST_START_UNIT_TEST=1
  if [ "${POD_NAME+x}" != "x" ]; then
    POD_NAME=es-ops-data-2
  fi
  if [ "${POD_IP+x}" != "x" ]; then
    POD_IP=127.0.0.1
  fi
  if [ "${TLS_ENABLED+x}" != "x" ]; then
    TLS_ENABLED=false
  fi
  if [ "${ELASTIC_PASSWORD+x}" != "x" ]; then
    ELASTIC_PASSWORD=secret
  fi
  PATH="$FAKEBIN:$PATH"
  export POD_NAME POD_IP TLS_ENABLED ELASTIC_PASSWORD PATH
  . "$ROOT_DIR/scripts/post-start-hook.sh"
}

assert_clears_stale_exclusion_when_it_matches_self() {
  CURL_SETTINGS_LOG="$TMP_DIR/post-start-clear-settings.log"
  : > "$CURL_SETTINGS_LOG"

  PATH="$FAKEBIN:$PATH"
  export PATH CURL_SETTINGS_LOG
  POD_NAME=es-ops-data-2
  MOCK_LOCAL_API_READY=1
  MOCK_CLUSTER_SETTINGS_JSON='{"persistent":{"cluster":{"routing":{"allocation":{"exclude":{"_name":"es-ops-data-2"}}}}}}'
  export POD_NAME MOCK_LOCAL_API_READY MOCK_CLUSTER_SETTINGS_JSON
  source_post_start_hook

  clear_stale_allocation_exclusion_for_self > "$TMP_DIR/post-start-clear.out"

  grep -q 'clearing stale shard allocation exclusion for es-ops-data-2' "$TMP_DIR/post-start-clear.out"
  grep -q '"cluster.routing.allocation.exclude._name":null' "$CURL_SETTINGS_LOG"
}

assert_does_not_clear_exclusion_for_another_pod() {
  CURL_SETTINGS_LOG="$TMP_DIR/post-start-other-settings.log"
  : > "$CURL_SETTINGS_LOG"

  PATH="$FAKEBIN:$PATH"
  export PATH CURL_SETTINGS_LOG
  POD_NAME=es-ops-data-2
  MOCK_LOCAL_API_READY=1
  MOCK_CLUSTER_SETTINGS_JSON='{"persistent":{"cluster":{"routing":{"allocation":{"exclude":{"_name":"es-ops-data-1"}}}}}}'
  export POD_NAME MOCK_LOCAL_API_READY MOCK_CLUSTER_SETTINGS_JSON
  source_post_start_hook

  clear_stale_allocation_exclusion_for_self > "$TMP_DIR/post-start-other.out"

  grep -q 'no stale shard allocation exclusion for es-ops-data-2' "$TMP_DIR/post-start-other.out"
  [ ! -s "$CURL_SETTINGS_LOG" ]
}

assert_leaves_settings_untouched_when_local_api_is_not_ready() {
  CURL_SETTINGS_LOG="$TMP_DIR/post-start-api-not-ready-settings.log"
  : > "$CURL_SETTINGS_LOG"

  PATH="$FAKEBIN:$PATH"
  export PATH CURL_SETTINGS_LOG
  POD_NAME=es-ops-data-2
  MOCK_LOCAL_API_READY=0
  MOCK_CLUSTER_SETTINGS_JSON='{"persistent":{"cluster":{"routing":{"allocation":{"exclude":{"_name":"es-ops-data-2"}}}}}}'
  export POD_NAME MOCK_LOCAL_API_READY MOCK_CLUSTER_SETTINGS_JSON
  source_post_start_hook

  clear_stale_allocation_exclusion_for_self > "$TMP_DIR/post-start-api-not-ready.out"

  grep -q 'local elasticsearch API is not ready, skip clearing stale shard allocation exclusion' "$TMP_DIR/post-start-api-not-ready.out"
  [ ! -s "$CURL_SETTINGS_LOG" ]
}

assert_skips_when_pod_name_is_empty() {
  CURL_SETTINGS_LOG="$TMP_DIR/post-start-empty-pod-settings.log"
  : > "$CURL_SETTINGS_LOG"

  PATH="$FAKEBIN:$PATH"
  export PATH CURL_SETTINGS_LOG
  POD_NAME=
  MOCK_LOCAL_API_READY=1
  export POD_NAME
  export MOCK_LOCAL_API_READY
  source_post_start_hook

  clear_stale_allocation_exclusion_for_self > "$TMP_DIR/post-start-empty-pod.out"

  grep -q 'POD_NAME is empty, skip clearing stale shard allocation exclusion' "$TMP_DIR/post-start-empty-pod.out"
  [ ! -s "$CURL_SETTINGS_LOG" ]
}

assert_clears_stale_exclusion_when_it_matches_self
assert_does_not_clear_exclusion_for_another_pod
assert_leaves_settings_untouched_when_local_api_is_not_ready
assert_skips_when_pod_name_is_empty

echo "post-start hook tests passed"
