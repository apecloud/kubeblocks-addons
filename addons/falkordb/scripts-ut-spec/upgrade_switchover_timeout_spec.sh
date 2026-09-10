# shellcheck shell=bash

Describe "FalkorDB switchover timeout upgrade verifier"
  setup_mock_kubectl() {
    chart_dir="$(cd "${SHELLSPEC_PROJECT_ROOT:-.}" && pwd)/addons/falkordb"
    mock_bin_dir="$(mktemp -d)"
    pod_read_count_file="$mock_bin_dir/pod-read-count"
    component_read_count_file="$mock_bin_dir/component-read-count"
    cluster_component_read_count_file="$mock_bin_dir/cluster-component-read-count"
    original_path="$PATH"

    cat >"$mock_bin_dir/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

sentinel_env='[
  {"name":"SENTINEL_COMPONENT_NAME","value":"cluster-falkordb-sent"},
  {"name":"SENTINEL_USER","valueFrom":{"secretKeyRef":{"name":"sentinel","key":"username"}}},
  {"name":"SENTINEL_PASSWORD","valueFrom":{"secretKeyRef":{"name":"sentinel","key":"password"}}},
  {"name":"SENTINEL_POD_NAME_LIST","value":"sentinel-0,sentinel-1,sentinel-2"},
  {"name":"SENTINEL_POD_FQDN_LIST","value":"sentinel-0.headless,sentinel-1.headless,sentinel-2.headless"},
  {"name":"SENTINEL_SERVICE_PORT","value":"26379"}
]'

if [[ "$*" == *"create --dry-run=client -o json"* ]]; then
  if [[ "${STALL_PREFLIGHT:-0}" == "1" ]]; then
    sleep 5
  fi
  cat <<'JSON'
{"kind":"OpsRequest","metadata":{"name":"upgrade","namespace":"demo"},"spec":{"clusterName":"cluster","type":"Upgrade","upgrade":{"components":[{"componentName":"falkordb","componentDefinitionName":"falkordb-4-1.2.0-alpha.1","serviceVersion":"4.12.5"}]}}}
JSON
elif [[ "$*" == *" create -f "* ]]; then
  printf 'opsrequest.operations.kubeblocks.io/upgrade created\n'
elif [[ "$*" == *"get opsrequest"* ]]; then
  printf 'Succeed'
elif [[ "$*" == *"get components.apps.kubeblocks.io"* && "$*" == *"apps.kubeblocks.io/component-name=falkordb"* ]]; then
  count=0
  if [[ -f "$COMPONENT_READ_COUNT_FILE" ]]; then
    count="$(cat "$COMPONENT_READ_COUNT_FILE")"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$COMPONENT_READ_COUNT_FILE"
  comp_def="falkordb-4-1.2.0-alpha.0"
  service_version="4.12.5"
  if ((count > 1)); then
    comp_def="falkordb-4-1.2.0-alpha.1"
    if [[ "${POST_VERSION_DRIFT:-0}" == "1" ]]; then
      service_version="4.14.12"
    fi
  elif [[ "${CURRENT_VERSION_MISMATCH:-0}" == "1" ]]; then
    service_version="4.14.12"
  fi
  printf '{"items":[{"metadata":{"labels":{"apps.kubeblocks.io/component-name":"falkordb"}},"spec":{"compDef":"%s","serviceVersion":"%s"}}]}\n' \
    "$comp_def" "$service_version"
elif [[ "$*" == *"get components.apps.kubeblocks.io"* ]]; then
  count=0
  if [[ -f "$CLUSTER_COMPONENT_READ_COUNT_FILE" ]]; then
    count="$(cat "$CLUSTER_COMPONENT_READ_COUNT_FILE")"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$CLUSTER_COMPONENT_READ_COUNT_FILE"
  if [[ "${STANDALONE:-0}" == "1" ]]; then
    cat <<'JSON'
{"items":[{"metadata":{"name":"cluster-falkordb","uid":"main-uid","labels":{"apps.kubeblocks.io/component-name":"falkordb"}},"spec":{"compDef":"falkordb-4-1.2.0-alpha.0","serviceVersion":"4.12.5"}}]}
JSON
  elif [[ "${SENTINEL_ABSENT:-0}" == "1" ]] ||
    [[ "${SENTINEL_DISAPPEARS:-0}" == "1" && "$count" -gt 1 ]]; then
    cat <<'JSON'
{"items":[{"metadata":{"name":"cluster-falkordb","uid":"main-uid","labels":{"apps.kubeblocks.io/component-name":"falkordb"}},"spec":{"compDef":"falkordb-4-1.2.0-alpha.0","serviceVersion":"4.12.5"}}]}
JSON
  else
    deletion_timestamp=null
    if [[ "${SENTINEL_TERMINATING:-0}" == "1" ]]; then
      deletion_timestamp='"2026-07-31T00:00:00Z"'
    fi
    jq -cn --argjson deletion_timestamp "$deletion_timestamp" '{
      items: [
        {
          metadata: {
            name: "cluster-falkordb",
            uid: "main-uid",
            labels: {"apps.kubeblocks.io/component-name": "falkordb"}
          },
          spec: {compDef: "falkordb-4-1.2.0-alpha.0", serviceVersion: "4.12.5"}
        },
        {
          metadata: {
            name: "cluster-falkordb-sent",
            uid: "sentinel-uid",
            deletionTimestamp: $deletion_timestamp,
            labels: {"apps.kubeblocks.io/component-name": "falkordb-sent"}
          },
          spec: {compDef: "falkordb-sent-4-1.2.0-alpha.0", serviceVersion: "4.12.5"}
        }
      ]
    }'
  fi
elif [[ "$*" == *"get pods"* ]]; then
  count=0
  if [[ -f "$POD_READ_COUNT_FILE" ]]; then
    count="$(cat "$POD_READ_COUNT_FILE")"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$POD_READ_COUNT_FILE"
  if ((count == 1 || ${KEEP_OLD_POD:-0} == 1)); then
    if [[ "${STANDALONE:-0}" == "1" ]]; then
      sentinel_env='[]'
    fi
    jq -cn \
      --argjson sentinel_env "$sentinel_env" \
      '{
        items: [{
          metadata: {name: "cluster-falkordb-0", uid: "old-uid"},
          spec: {
            containers: [
              {name: "falkordb", image: "docker.io/falkordb/falkordb:v4.12.5", env: $sentinel_env},
              {name: "kbagent", image: "docker.io/apecloud/kbagent:v0", env: [
                {name: "KB_AGENT_ACTION", value: "[{\"name\":\"switchover\",\"timeoutSeconds\":0}]"}
              ]}
            ]
          },
          status: {
            conditions: [{type: "Ready", status: "True"}],
            containerStatuses: [
              {name: "falkordb", image: "docker.io/falkordb/falkordb:v4.12.5", imageID: "docker-pullable://falkordb@sha256:db"},
              {name: "kbagent", image: "docker.io/apecloud/kbagent:v0", imageID: "docker-pullable://kbagent@sha256:agent"}
            ]
          }
        }]
      }'
  else
    falkordb_image="docker.io/falkordb/falkordb:v4.12.5"
    falkordb_image_id="docker-pullable://falkordb@sha256:db"
    if [[ "${IMAGE_DRIFT:-0}" == "1" ]]; then
      falkordb_image="docker.io/falkordb/falkordb:v4.14.12"
      falkordb_image_id="docker-pullable://falkordb@sha256:new-db"
    fi
    if [[ "${IMAGE_ID_DRIFT:-0}" == "1" ]]; then
      falkordb_image_id="docker-pullable://falkordb@sha256:retagged-db"
    fi
    if [[ "${MISSING_SENTINEL_ENV:-0}" == "1" ]]; then
      sentinel_env='[]'
    fi
    if [[ "${DRIFT_SENTINEL_ENV:-0}" == "1" ]]; then
      sentinel_env="$(jq -c '
        map(
          if .name == "SENTINEL_COMPONENT_NAME" then
            .value = "cluster-other-sentinel"
          else
            .
          end
        )
      ' <<<"$sentinel_env")"
    fi
    switchover_actions='[{"name":"switchover","timeoutSeconds":-1}]'
    if [[ "${CONFLICTING_ACTION:-0}" == "1" ]]; then
      switchover_actions='[{"name":"switchover","timeoutSeconds":-1},{"name":"switchover","timeoutSeconds":0}]'
    fi
    deletion_timestamp=null
    if [[ "${TERMINATING_POD:-0}" == "1" ]]; then
      deletion_timestamp='"2026-07-31T00:00:00Z"'
    fi
    jq -cn \
      --arg falkordb_image "$falkordb_image" \
      --arg falkordb_image_id "$falkordb_image_id" \
      --arg actions "$switchover_actions" \
      --argjson deletion_timestamp "$deletion_timestamp" \
      --argjson sentinel_env "$sentinel_env" \
      '{
        items: [{
          metadata: {
            name: "cluster-falkordb-0",
            uid: "new-uid",
            deletionTimestamp: $deletion_timestamp
          },
          spec: {
            containers: [
              {name: "falkordb", image: $falkordb_image, env: $sentinel_env},
              {name: "kbagent", image: "docker.io/apecloud/kbagent:v0", env: [
                {name: "KB_AGENT_ACTION", value: $actions}
              ]}
            ]
          },
          status: {
            conditions: [{type: "Ready", status: "True"}],
            containerStatuses: [
              {name: "falkordb", image: $falkordb_image, imageID: $falkordb_image_id},
              {name: "kbagent", image: "docker.io/apecloud/kbagent:v0", imageID: "docker-pullable://kbagent@sha256:agent"}
            ]
          }
        }]
      }'
  fi
else
  printf 'unexpected kubectl call: %s\n' "$*" >&2
  exit 1
fi
MOCK
    chmod +x "$mock_bin_dir/kubectl"
    export PATH="$mock_bin_dir:$PATH"
    export POD_READ_COUNT_FILE="$pod_read_count_file"
    export COMPONENT_READ_COUNT_FILE="$component_read_count_file"
    export CLUSTER_COMPONENT_READ_COUNT_FILE="$cluster_component_read_count_file"
    export UPGRADE_VERIFY_TIMEOUT_SECONDS=2
    export UPGRADE_VERIFY_POLL_SECONDS=1
    export UPGRADE_VERIFY_API_TIMEOUT_SECONDS=1
  }

  cleanup_mock_kubectl() {
    PATH="$original_path"
    rm -rf "$mock_bin_dir"
    unset chart_dir mock_bin_dir pod_read_count_file component_read_count_file
    unset cluster_component_read_count_file original_path
    unset POD_READ_COUNT_FILE COMPONENT_READ_COUNT_FILE CLUSTER_COMPONENT_READ_COUNT_FILE
    unset KEEP_OLD_POD CONFLICTING_ACTION TERMINATING_POD STALL_PREFLIGHT
    unset CURRENT_VERSION_MISMATCH POST_VERSION_DRIFT IMAGE_DRIFT IMAGE_ID_DRIFT
    unset MISSING_SENTINEL_ENV STANDALONE
    unset SENTINEL_ABSENT SENTINEL_TERMINATING SENTINEL_DISAPPEARS DRIFT_SENTINEL_ENV
    unset UPGRADE_VERIFY_TIMEOUT_SECONDS UPGRADE_VERIFY_POLL_SECONDS
    unset UPGRADE_VERIFY_API_TIMEOUT_SECONDS FALKORDB_UPGRADE_VERIFY_SUPERVISED
  }

  BeforeEach "setup_mock_kubectl"
  AfterEach "cleanup_mock_kubectl"

  It "accepts a replication replacement with stable version, images, Sentinel vars, and timeout"
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be success
    The stdout should include "Upgrade verified"
    The stdout should include "serviceVersion=4.12.5"
    The stdout should include "recreatedPods=1 images=unchanged"
  End

  It "accepts a standalone replacement without Sentinel vars"
    export STANDALONE=1
    export MISSING_SENTINEL_ENV=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be success
    The stdout should include "Upgrade verified"
  End

  It "rejects a manifest serviceVersion that differs from the live Component before creation"
    export CURRENT_VERSION_MISMATCH=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should not include "created"
    The stderr should include "does not match live Component serviceVersion 4.14.12"
  End

  It "fails closed when the replacement Component changes serviceVersion"
    export POST_VERSION_DRIFT=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "fails closed when replacement Pod image names or IDs drift"
    export IMAGE_DRIFT=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "fails closed when only a replacement Pod image ID drifts"
    export IMAGE_ID_DRIFT=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "fails closed when a replication replacement loses Sentinel variables"
    export MISSING_SENTINEL_ENV=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "rejects replication preflight when old Pods require an absent Sentinel sibling"
    export SENTINEL_ABSENT=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should not include "created"
    The stderr should include "existing Pods require Sentinel"
  End

  It "rejects replication preflight when the Sentinel sibling is terminating"
    export SENTINEL_TERMINATING=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should not include "created"
    The stderr should include "expected at most one non-terminating FalkorDB Sentinel Component"
  End

  It "fails closed when the Sentinel sibling disappears after creation"
    export SENTINEL_DISAPPEARS=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "fails closed when replacement Sentinel values drift"
    export DRIFT_SENTINEL_ENV=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "fails closed when the old Pod UID remains"
    export KEEP_OLD_POD=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "fails closed when switchover actions conflict"
    export CONFLICTING_ACTION=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "fails closed when the replacement Pod is terminating"
    export TERMINATING_POD=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "caps an oversized poll interval with the wall-clock deadline"
    export KEEP_OLD_POD=1
    export UPGRADE_VERIFY_TIMEOUT_SECONDS=1
    export UPGRADE_VERIFY_POLL_SECONDS=99
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "bounds a stalled preflight API call with the wall-clock deadline"
    export STALL_PREFLIGHT=1
    export UPGRADE_VERIFY_TIMEOUT_SECONDS=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End
End
