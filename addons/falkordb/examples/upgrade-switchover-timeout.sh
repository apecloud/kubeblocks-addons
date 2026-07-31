#!/usr/bin/env bash

set -euo pipefail

manifest="${1:-$(dirname "$0")/upgrade-switchover-timeout.yaml}"
verify_timeout="${UPGRADE_VERIFY_TIMEOUT_SECONDS:-600}"
poll_interval="${UPGRADE_VERIFY_POLL_SECONDS:-5}"
api_timeout="${UPGRADE_VERIFY_API_TIMEOUT_SECONDS:-10}"

for command in kubectl jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

if [[ ! "$verify_timeout" =~ ^[1-9][0-9]*$ ]] ||
  [[ ! "$poll_interval" =~ ^[1-9][0-9]*$ ]] ||
  [[ ! "$api_timeout" =~ ^[1-9][0-9]*$ ]]; then
  printf 'verification, polling, and API timeouts must be positive integers\n' >&2
  exit 1
fi

if [[ "${FALKORDB_UPGRADE_VERIFY_SUPERVISED:-0}" != "1" ]]; then
  timeout_command="$(command -v timeout || command -v gtimeout || true)"
  if [[ -z "$timeout_command" ]]; then
    printf 'required command not found: timeout or gtimeout\n' >&2
    exit 1
  fi
  export FALKORDB_UPGRADE_VERIFY_SUPERVISED=1
  set +e
  "$timeout_command" --signal=TERM --kill-after=10s "${verify_timeout}s" \
    "$BASH" "$0" "$@"
  status=$?
  set -e
  if ((status == 124 || status == 137)); then
    printf 'timed out verifying ComponentDefinition and recreated kbagent Pods\n' >&2
  fi
  exit "$status"
fi

kubectl_timeout="--request-timeout=${api_timeout}s"
ops_json="$(kubectl "$kubectl_timeout" create --dry-run=client -o json -f "$manifest")"
namespace="$(jq -er '.metadata.namespace // "default"' <<<"$ops_json")"
ops_name="$(jq -er '.metadata.name' <<<"$ops_json")"
cluster_name="$(jq -er '.spec.clusterName' <<<"$ops_json")"
component_name="$(jq -er '.spec.upgrade.components[0].componentName' <<<"$ops_json")"
target_comp_def="$(jq -er '.spec.upgrade.components[0].componentDefinitionName' <<<"$ops_json")"

jq -e '
  .kind == "OpsRequest" and
  .spec.type == "Upgrade" and
  (.spec.force // false) == false and
  (.spec.upgrade.components | length) == 1 and
  (.spec.upgrade.components[0] | has("serviceVersion") | not)
' <<<"$ops_json" >/dev/null

selector="app.kubernetes.io/instance=${cluster_name},apps.kubeblocks.io/component-name=${component_name}"
old_pods_json="$(kubectl "$kubectl_timeout" get pods -n "$namespace" -l "$selector" -o json)"
old_pod_count="$(jq -er '.items | length' <<<"$old_pods_json")"
if ((old_pod_count == 0)); then
  printf 'no existing Pods match %s\n' "$selector" >&2
  exit 1
fi
old_pod_uids="$(jq -c '[.items[].metadata.uid]' <<<"$old_pods_json")"

kubectl "$kubectl_timeout" create -f "$manifest"

deadline=$((SECONDS + verify_timeout))
while ((SECONDS < deadline)); do
  ops_phase="$(kubectl "$kubectl_timeout" get opsrequest "$ops_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$ops_phase" == "Failed" || "$ops_phase" == "Aborted" || "$ops_phase" == "Cancelled" ]]; then
    printf 'Upgrade OpsRequest entered terminal phase %s\n' "$ops_phase" >&2
    exit 1
  fi

  components_json="$(kubectl "$kubectl_timeout" get components.apps.kubeblocks.io -n "$namespace" -l "$selector" -o json 2>/dev/null || true)"
  pods_json="$(kubectl "$kubectl_timeout" get pods -n "$namespace" -l "$selector" -o json 2>/dev/null || true)"
  if [[ -z "$components_json" || -z "$pods_json" ]]; then
    sleep "$poll_interval"
    continue
  fi

  if [[ "$ops_phase" == "Succeed" ]] &&
    jq -e --arg target "$target_comp_def" '
      (.items | length) == 1 and
      .items[0].spec.compDef == $target
    ' <<<"$components_json" >/dev/null &&
    jq -e --argjson old_uids "$old_pod_uids" --argjson expected_count "$old_pod_count" '
      (.items | length) == $expected_count and
      all(.items[];
        .metadata.deletionTimestamp == null and
        (.metadata.uid as $uid | ($old_uids | index($uid)) == null) and
        any(.status.conditions[]?; .type == "Ready" and .status == "True") and
        ([
          .spec.containers[]
          | select(.name == "kbagent")
          | .env[]?
          | select(.name == "KB_AGENT_ACTION")
          | .value
        ] | length) == 1 and
        ([
          .spec.containers[]
          | select(.name == "kbagent")
          | .env[]?
          | select(.name == "KB_AGENT_ACTION")
          | .value
          | fromjson
          | .[]
          | select(.name == "switchover")
        ] | length) == 1 and
        all(
          .spec.containers[]
          | select(.name == "kbagent")
          | .env[]?
          | select(.name == "KB_AGENT_ACTION")
          | .value
          | fromjson
          | .[]
          | select(.name == "switchover");
          .timeoutSeconds == -1
        )
      )
    ' <<<"$pods_json" >/dev/null; then
    printf 'Upgrade verified: component=%s compDef=%s recreatedPods=%s\n' \
      "$component_name" "$target_comp_def" "$old_pod_count"
    exit 0
  fi

  remaining=$((deadline - SECONDS))
  if ((remaining <= 0)); then
    break
  fi
  sleep_interval="$poll_interval"
  if ((sleep_interval > remaining)); then
    sleep_interval="$remaining"
  fi
  sleep "$sleep_interval"
done

printf 'timed out verifying ComponentDefinition and recreated kbagent Pods\n' >&2
kubectl "$kubectl_timeout" get opsrequest "$ops_name" -n "$namespace" -o wide >&2 || true
kubectl "$kubectl_timeout" get components.apps.kubeblocks.io -n "$namespace" -l "$selector" -o wide >&2 || true
kubectl "$kubectl_timeout" get pods -n "$namespace" -l "$selector" -o wide >&2 || true
exit 1
