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

if ! jq -e '
  .kind == "OpsRequest" and
  .spec.type == "Upgrade" and
  (.spec.force // false) == false and
  (.spec.upgrade.components | length) == 1 and
  (.spec.upgrade.components[0].serviceVersion | type == "string" and length > 0)
' <<<"$ops_json" >/dev/null; then
  printf 'Upgrade manifest must contain one non-forced component with an explicit serviceVersion\n' >&2
  exit 1
fi
target_service_version="$(jq -er '.spec.upgrade.components[0].serviceVersion' <<<"$ops_json")"

selector="app.kubernetes.io/instance=${cluster_name},apps.kubeblocks.io/component-name=${component_name}"
cluster_selector="app.kubernetes.io/instance=${cluster_name}"
sentinel_env_names='[
  "SENTINEL_COMPONENT_NAME",
  "SENTINEL_USER",
  "SENTINEL_PASSWORD",
  "SENTINEL_POD_NAME_LIST",
  "SENTINEL_POD_FQDN_LIST",
  "SENTINEL_SERVICE_PORT"
]'
current_components_json="$(kubectl "$kubectl_timeout" get components.apps.kubeblocks.io -n "$namespace" -l "$selector" -o json)"
current_service_version="$(jq -er '
  if (.items | length) == 1 then
    .items[0].spec.serviceVersion
  else
    error("expected exactly one live Component")
  end
' <<<"$current_components_json")"
if [[ "$current_service_version" != "$target_service_version" ]]; then
  printf 'manifest serviceVersion %s does not match live Component serviceVersion %s\n' \
    "$target_service_version" "$current_service_version" >&2
  exit 1
fi

old_pods_json="$(kubectl "$kubectl_timeout" get pods -n "$namespace" -l "$selector" -o json)"
old_pod_count="$(jq -er '.items | length' <<<"$old_pods_json")"
if ((old_pod_count == 0)); then
  printf 'no existing Pods match %s\n' "$selector" >&2
  exit 1
fi
old_pod_uids="$(jq -c '[.items[].metadata.uid]' <<<"$old_pods_json")"

pod_image_contract() {
  jq -c '
    [
      .items[]
      | {
          name: .metadata.name,
          spec: (
            (
              [.spec.initContainers[]? | {kind: "init", name, image}] +
              [.spec.containers[]? | {kind: "container", name, image}]
            ) | sort_by(.kind, .name)
          ),
          status: (
            (
              [.status.initContainerStatuses[]? | {kind: "init", name, image, imageID}] +
              [.status.containerStatuses[]? | {kind: "container", name, image, imageID}]
            ) | sort_by(.kind, .name)
          )
        }
    ] | sort_by(.name)
  '
}

if ! jq -e '
  all(.items[];
    .metadata.deletionTimestamp == null and
    any(.status.conditions[]?; .type == "Ready" and .status == "True") and
    ([.spec.containers[]? | select(.name == "falkordb")] | length) == 1 and
    (
      (
        [.spec.initContainers[]? | ["init", .name]] +
        [.spec.containers[]? | ["container", .name]]
      ) | sort
    ) ==
    (
      (
        [.status.initContainerStatuses[]? | ["init", .name]] +
        [.status.containerStatuses[]? | ["container", .name]]
      ) | sort
    ) and
    all(
      (.status.initContainerStatuses[]?, .status.containerStatuses[]?);
      (.image // "") != "" and (.imageID // "") != ""
    )
  )
' <<<"$old_pods_json" >/dev/null; then
  printf 'existing Pods must be non-terminating, Ready, and expose resolved image IDs\n' >&2
  exit 1
fi
old_image_contract="$(pod_image_contract <<<"$old_pods_json")"

if ! jq -e --argjson names "$sentinel_env_names" '
  def sentinel_env_contract($pod):
    [
      $pod.spec.containers[]
      | select(.name == "falkordb")
      | .env[]?
      | select(.name as $name | ($names | index($name)) != null)
      | {
          name,
          value: (.value // null),
          valueFrom: (.valueFrom // null)
        }
    ] | sort_by(.name);

  [.items[] | sentinel_env_contract(.)] as $contracts |
  ($contracts | length) > 0 and
  all($contracts[];
    length == 0 or
    (
      length == ($names | length) and
      ([.[].name] | unique | length) == ($names | length) and
      all(.[];
        ((.value // "") != "") or
        (.valueFrom != null)
      )
    )
  ) and
  all($contracts[]; . == $contracts[0])
' <<<"$old_pods_json" >/dev/null; then
  printf 'existing Pods have incomplete, duplicate, empty, or inconsistent Sentinel environment contracts\n' >&2
  exit 1
fi
old_sentinel_env_contract="$(jq -c --argjson names "$sentinel_env_names" '
  [
    .items[0].spec.containers[]
    | select(.name == "falkordb")
    | .env[]?
    | select(.name as $name | ($names | index($name)) != null)
    | {
        name,
        value: (.value // null),
        valueFrom: (.valueFrom // null)
      }
  ] | sort_by(.name)
' <<<"$old_pods_json")"

cluster_components_json="$(kubectl "$kubectl_timeout" get components.apps.kubeblocks.io -n "$namespace" -l "$cluster_selector" -o json)"
sentinel_components="$(jq -c '
  [
    .items[]
    | select(
        (.metadata.labels["apps.kubeblocks.io/component-name"] // "") == "falkordb-sent" or
        (.spec.compDef // "" | startswith("falkordb-sent-4"))
      )
    | {
        name: .metadata.name,
        uid: .metadata.uid,
        terminating: (.metadata.deletionTimestamp != null)
      }
  ] | sort_by(.name)
' <<<"$cluster_components_json")"
if ! jq -e '
  length <= 1 and
  all(.[];
    .terminating == false and
    (.name | type == "string" and length > 0) and
    (.uid | type == "string" and length > 0)
  )
' <<<"$sentinel_components" >/dev/null; then
  printf 'expected at most one non-terminating FalkorDB Sentinel Component\n' >&2
  exit 1
fi

old_requires_sentinel="$(jq -r 'length > 0' <<<"$old_sentinel_env_contract")"
sentinel_component_count="$(jq -r 'length' <<<"$sentinel_components")"
if [[ "$old_requires_sentinel" == "true" && "$sentinel_component_count" != "1" ]]; then
  printf 'existing Pods require Sentinel but exactly one live Sentinel Component was not found\n' >&2
  exit 1
fi
if [[ "$old_requires_sentinel" == "false" && "$sentinel_component_count" != "0" ]]; then
  printf 'existing Pods are standalone but a Sentinel Component was found\n' >&2
  exit 1
fi
expected_sentinel_identity="$(jq -c '
  if length == 1 then
    .[0] | {name, uid}
  else
    null
  end
' <<<"$sentinel_components")"

kubectl "$kubectl_timeout" create -f "$manifest"

deadline=$((SECONDS + verify_timeout))
while ((SECONDS < deadline)); do
  ops_phase="$(kubectl "$kubectl_timeout" get opsrequest "$ops_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$ops_phase" == "Failed" || "$ops_phase" == "Aborted" || "$ops_phase" == "Cancelled" ]]; then
    printf 'Upgrade OpsRequest entered terminal phase %s\n' "$ops_phase" >&2
    exit 1
  fi

  components_json="$(kubectl "$kubectl_timeout" get components.apps.kubeblocks.io -n "$namespace" -l "$selector" -o json 2>/dev/null || true)"
  cluster_components_json="$(kubectl "$kubectl_timeout" get components.apps.kubeblocks.io -n "$namespace" -l "$cluster_selector" -o json 2>/dev/null || true)"
  pods_json="$(kubectl "$kubectl_timeout" get pods -n "$namespace" -l "$selector" -o json 2>/dev/null || true)"
  if [[ -z "$components_json" || -z "$cluster_components_json" || -z "$pods_json" ]]; then
    sleep "$poll_interval"
    continue
  fi

  if [[ "$ops_phase" == "Succeed" ]] &&
    jq -e --arg target "$target_comp_def" --arg service_version "$target_service_version" '
      (.items | length) == 1 and
      .items[0].spec.compDef == $target and
      .items[0].spec.serviceVersion == $service_version
    ' <<<"$components_json" >/dev/null &&
    jq -e --argjson expected "$expected_sentinel_identity" '
      [
        .items[]
        | select(
            (.metadata.labels["apps.kubeblocks.io/component-name"] // "") == "falkordb-sent" or
            (.spec.compDef // "" | startswith("falkordb-sent-4"))
          )
        | {
            name: .metadata.name,
            uid: .metadata.uid,
            terminating: (.metadata.deletionTimestamp != null)
          }
      ] as $sentinels |
      if $expected == null then
        ($sentinels | length) == 0
      else
        ($sentinels | length) == 1 and
        $sentinels[0].terminating == false and
        ($sentinels[0] | {name, uid}) == $expected
      end
    ' <<<"$cluster_components_json" >/dev/null &&
    jq -e \
      --argjson old_uids "$old_pod_uids" \
      --argjson expected_count "$old_pod_count" \
      --argjson sentinel_names "$sentinel_env_names" \
      --argjson expected_sentinel_env "$old_sentinel_env_contract" '
      def sentinel_env_contract($pod):
        [
          $pod.spec.containers[]
          | select(.name == "falkordb")
          | .env[]?
          | select(.name as $name | ($sentinel_names | index($name)) != null)
          | {
              name,
              value: (.value // null),
              valueFrom: (.valueFrom // null)
            }
        ] | sort_by(.name);

      (.items | length) == $expected_count and
      all(.items[];
        . as $pod |
        .metadata.deletionTimestamp == null and
        (.metadata.uid as $uid | ($old_uids | index($uid)) == null) and
        any(.status.conditions[]?; .type == "Ready" and .status == "True") and
        sentinel_env_contract($pod) == $expected_sentinel_env and
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
    ' <<<"$pods_json" >/dev/null &&
    [[ "$(pod_image_contract <<<"$pods_json")" == "$old_image_contract" ]]; then
    printf 'Upgrade verified: component=%s compDef=%s serviceVersion=%s recreatedPods=%s images=unchanged\n' \
      "$component_name" "$target_comp_def" "$target_service_version" "$old_pod_count"
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
