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
    unset QDRANT_SETUP_UNIT_TEST CURRENT_POD_NAME KB_NAMESPACE CLUSTER_DOMAIN CLUSTER_COMPONENT_NAME QDRANT_SERVICE_NAME
  }
  After "cleanup"

  Describe "qdrant_current_pod_fqdn()"
    setup() {
      export CURRENT_POD_NAME="qdrant-rollout-replace-qdrant-6"
      export KB_NAMESPACE="default"
      export CLUSTER_DOMAIN="cluster.local"
      export CLUSTER_COMPONENT_NAME="qdrant-rollout-replace-qdrant"
      export QDRANT_SERVICE_NAME="qdrant"
    }
    Before "setup"

    It "derives current pod FQDN from pod identity and cluster DNS settings"
      When call qdrant_current_pod_fqdn
      The status should be success
      The output should eq "qdrant-rollout-replace-qdrant-6.qdrant-rollout-replace-qdrant-headless.default.svc.cluster.local"
    End
  End

  Describe "qdrant_bootstrap_service_host()"
    setup() {
      export CURRENT_POD_NAME="qdrant-rollout-replace-qdrant-6"
      export KB_NAMESPACE="default"
      export CLUSTER_DOMAIN="cluster.local"
      export CLUSTER_COMPONENT_NAME="qdrant-rollout-replace-qdrant"
      export QDRANT_SERVICE_NAME="qdrant"
    }
    Before "setup"

    It "derives the component Service host used for joining replacement or scale-out pods"
      When call qdrant_bootstrap_service_host
      The status should be success
      The output should eq "qdrant-rollout-replace-qdrant-qdrant.default.svc.cluster.local"
    End
  End

  Describe "qdrant_start_mode()"
    setup() {
      export KB_NAMESPACE="default"
      export CLUSTER_DOMAIN="cluster.local"
      export QDRANT_STORAGE_PATH="./qdrant-test-storage"
      rm -rf "$QDRANT_STORAGE_PATH"
      mkdir -p "$QDRANT_STORAGE_PATH"
      qdrant_curl() {
        [ "${BOOTSTRAP_SERVICE_AVAILABLE:-false}" = "true" ]
      }
    }
    Before "setup"

    cleanup_storage() {
      rm -rf "$QDRANT_STORAGE_PATH"
      unset BOOTSTRAP_SERVICE_AVAILABLE QDRANT_STORAGE_PATH
    }
    After "cleanup_storage"

    It "bootstraps the initial empty ordinal zero pod when no service endpoint exists"
      CURRENT_POD_NAME="qdrant-provision-qdrant-0"
      BOOTSTRAP_SERVICE_AVAILABLE=false
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "bootstrap"
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
