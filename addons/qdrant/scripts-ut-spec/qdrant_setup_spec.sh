# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "qdrant_setup_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Qdrant Setup Bash Script Tests"
  export QDRANT_SETUP_UNIT_TEST=true
  Include ../scripts/qdrant-common.sh
  Include ../scripts/qdrant-setup.sh

  cleanup() {
    unset QDRANT_SETUP_UNIT_TEST CURRENT_POD_NAME
    unset QDRANT_COMPONENT_SERVICE_HOST QDRANT_HEADLESS_SERVICE_HOST
  }
  After "cleanup"

  Describe "qdrant_current_pod_fqdn()"
    setup() {
      export CURRENT_POD_NAME="qdrant-rollout-replace-qdrant-6"
      export QDRANT_HEADLESS_SERVICE_HOST="qdrant-rollout-replace-qdrant-headless.default.svc.cluster.local"
    }
    Before "setup"

    It "uses the KubeBlocks-resolved headless service host for the current pod FQDN"
      When call qdrant_current_pod_fqdn
      The status should be success
      The output should eq "qdrant-rollout-replace-qdrant-6.qdrant-rollout-replace-qdrant-headless.default.svc.cluster.local"
    End
  End

  Describe "qdrant_bootstrap_service_host()"
    setup() {
      export CURRENT_POD_NAME="qdrant-rollout-replace-qdrant-6"
      export QDRANT_COMPONENT_SERVICE_HOST="qdrant-rollout-replace-qdrant-qdrant.default.svc.cluster.local"
    }
    Before "setup"

    It "uses the KubeBlocks-resolved ComponentService host for joining replacement or scale-out pods"
      When call qdrant_bootstrap_service_host
      The status should be success
      The output should eq "qdrant-rollout-replace-qdrant-qdrant.default.svc.cluster.local"
    End
  End

  Describe "qdrant_start_mode()"
    setup() {
      export QDRANT_STORAGE_PATH="./qdrant-test-storage"
      rm -rf "$QDRANT_STORAGE_PATH"
      mkdir -p "$QDRANT_STORAGE_PATH"
      qdrant_curl_call_count=0
      qdrant_curl() {
        qdrant_curl_call_count=$((qdrant_curl_call_count + 1))
        if [ -n "${BOOTSTRAP_SERVICE_SUCCEEDS_ON_ATTEMPT:-}" ] &&
          [ "$qdrant_curl_call_count" -ge "$BOOTSTRAP_SERVICE_SUCCEEDS_ON_ATTEMPT" ]; then
          return 0
        fi
        [ "${BOOTSTRAP_SERVICE_AVAILABLE:-false}" = "true" ]
      }
    }
    Before "setup"

    cleanup_storage() {
      rm -rf "$QDRANT_STORAGE_PATH"
      unset BOOTSTRAP_SERVICE_AVAILABLE BOOTSTRAP_SERVICE_SUCCEEDS_ON_ATTEMPT QDRANT_STORAGE_PATH
      unset QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_ATTEMPTS QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_SLEEP_SECONDS
    }
    After "cleanup_storage"

    It "bootstraps the initial empty ordinal zero pod only after discovery attempts are exhausted"
      CURRENT_POD_NAME="qdrant-provision-qdrant-0"
      BOOTSTRAP_SERVICE_AVAILABLE=false
      QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_ATTEMPTS=1
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "bootstrap"
    End

    It "joins when a reused empty ordinal zero observes an existing service during discovery"
      CURRENT_POD_NAME="qdrant-rollout-replace-qdrant-0"
      BOOTSTRAP_SERVICE_AVAILABLE=false
      BOOTSTRAP_SERVICE_SUCCEEDS_ON_ATTEMPT=2
      QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_ATTEMPTS=3
      QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_SLEEP_SECONDS=0
      When call qdrant_start_mode "http://qdrant-rollout-replace-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "join"
    End

    It "joins an existing cluster even when KubeBlocks reuses ordinal zero"
      CURRENT_POD_NAME="qdrant-rollout-replace-qdrant-0"
      BOOTSTRAP_SERVICE_AVAILABLE=true
      When call qdrant_start_mode "http://qdrant-rollout-replace-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "join"
    End

    It "restarts from durable raft state instead of rejoining"
      CURRENT_POD_NAME="qdrant-provision-qdrant-0"
      BOOTSTRAP_SERVICE_AVAILABLE=true
      echo '{"peer_id":1}' > "$QDRANT_STORAGE_PATH/raft_state.json"
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "restart"
    End

    It "waits to join for non-zero pods when the bootstrap service is not ready"
      CURRENT_POD_NAME="qdrant-provision-qdrant-1"
      BOOTSTRAP_SERVICE_AVAILABLE=false
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "join"
    End
  End
End
