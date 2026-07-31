# shellcheck shell=bash

Describe "FalkorDB switchover timeout upgrade verifier"
  setup_mock_kubectl() {
    chart_dir="$(cd "${SHELLSPEC_PROJECT_ROOT:-.}" && pwd)/addons/falkordb"
    mock_bin_dir="$(mktemp -d)"
    pod_read_count_file="$mock_bin_dir/pod-read-count"
    original_path="$PATH"

    cat >"$mock_bin_dir/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"create --dry-run=client -o json"* ]]; then
  if [[ "${STALL_PREFLIGHT:-0}" == "1" ]]; then
    sleep 5
  fi
  cat <<'JSON'
{"kind":"OpsRequest","metadata":{"name":"upgrade","namespace":"demo"},"spec":{"clusterName":"cluster","type":"Upgrade","upgrade":{"components":[{"componentName":"falkordb","componentDefinitionName":"falkordb-4-1.2.0-alpha.1"}]}}}
JSON
elif [[ "$*" == *" create -f "* ]]; then
  printf 'opsrequest.operations.kubeblocks.io/upgrade created\n'
elif [[ "$*" == *"get opsrequest"* ]]; then
  printf 'Succeed'
elif [[ "$*" == *"get components.apps.kubeblocks.io"* ]]; then
  cat <<'JSON'
{"items":[{"spec":{"compDef":"falkordb-4-1.2.0-alpha.1"}}]}
JSON
elif [[ "$*" == *"get pods"* ]]; then
  count=0
  if [[ -f "$POD_READ_COUNT_FILE" ]]; then
    count="$(cat "$POD_READ_COUNT_FILE")"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$POD_READ_COUNT_FILE"
  if ((count == 1 || ${KEEP_OLD_POD:-0} == 1)); then
    cat <<'JSON'
{"items":[{"metadata":{"uid":"old-uid"},"status":{"conditions":[{"type":"Ready","status":"True"}]},"spec":{"containers":[{"name":"kbagent","env":[{"name":"KB_AGENT_ACTION","value":"[{\"name\":\"switchover\",\"timeoutSeconds\":0}]"}]}]}}]}
JSON
  elif [[ "${CONFLICTING_ACTION:-0}" == "1" ]]; then
    cat <<'JSON'
{"items":[{"metadata":{"uid":"new-uid"},"status":{"conditions":[{"type":"Ready","status":"True"}]},"spec":{"containers":[{"name":"kbagent","env":[{"name":"KB_AGENT_ACTION","value":"[{\"name\":\"switchover\",\"timeoutSeconds\":-1},{\"name\":\"switchover\",\"timeoutSeconds\":0}]"}]}]}}]}
JSON
  elif [[ "${TERMINATING_POD:-0}" == "1" ]]; then
    cat <<'JSON'
{"items":[{"metadata":{"uid":"new-uid","deletionTimestamp":"2026-07-31T00:00:00Z"},"status":{"conditions":[{"type":"Ready","status":"True"}]},"spec":{"containers":[{"name":"kbagent","env":[{"name":"KB_AGENT_ACTION","value":"[{\"name\":\"switchover\",\"timeoutSeconds\":-1}]"}]}]}}]}
JSON
  else
    cat <<'JSON'
{"items":[{"metadata":{"uid":"new-uid"},"status":{"conditions":[{"type":"Ready","status":"True"}]},"spec":{"containers":[{"name":"kbagent","env":[{"name":"KB_AGENT_ACTION","value":"[{\"name\":\"switchover\",\"timeoutSeconds\":-1}]"}]}]}}]}
JSON
  fi
else
  printf 'unexpected kubectl call: %s\n' "$*" >&2
  exit 1
fi
MOCK
    chmod +x "$mock_bin_dir/kubectl"
    export PATH="$mock_bin_dir:$PATH"
    export POD_READ_COUNT_FILE="$pod_read_count_file"
    export UPGRADE_VERIFY_TIMEOUT_SECONDS=2
    export UPGRADE_VERIFY_POLL_SECONDS=1
    export UPGRADE_VERIFY_API_TIMEOUT_SECONDS=1
  }

  cleanup_mock_kubectl() {
    PATH="$original_path"
    rm -rf "$mock_bin_dir"
    unset chart_dir mock_bin_dir pod_read_count_file original_path
    unset POD_READ_COUNT_FILE KEEP_OLD_POD CONFLICTING_ACTION TERMINATING_POD STALL_PREFLIGHT
    unset UPGRADE_VERIFY_TIMEOUT_SECONDS UPGRADE_VERIFY_POLL_SECONDS
    unset UPGRADE_VERIFY_API_TIMEOUT_SECONDS FALKORDB_UPGRADE_VERIFY_SUPERVISED
  }

  BeforeEach "setup_mock_kubectl"
  AfterEach "cleanup_mock_kubectl"

  It "accepts only a new ready Pod with the target kbagent timeout"
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be success
    The stdout should include "Upgrade verified"
    The stdout should include "recreatedPods=1"
  End

  It "fails closed when the old Pod UID remains"
    export KEEP_OLD_POD=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "opsrequest.operations.kubeblocks.io/upgrade created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "fails closed when switchover actions conflict"
    export CONFLICTING_ACTION=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "opsrequest.operations.kubeblocks.io/upgrade created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "fails closed when the replacement Pod is terminating"
    export TERMINATING_POD=1
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "opsrequest.operations.kubeblocks.io/upgrade created"
    The stderr should include "timed out verifying ComponentDefinition and recreated kbagent Pods"
  End

  It "caps an oversized poll interval with the wall-clock deadline"
    export KEEP_OLD_POD=1
    export UPGRADE_VERIFY_TIMEOUT_SECONDS=1
    export UPGRADE_VERIFY_POLL_SECONDS=99
    When run command bash "$chart_dir/examples/upgrade-switchover-timeout.sh" \
      "$chart_dir/examples/upgrade-switchover-timeout.yaml"
    The status should be failure
    The stdout should include "opsrequest.operations.kubeblocks.io/upgrade created"
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
