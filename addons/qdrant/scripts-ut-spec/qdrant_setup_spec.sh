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
    unset QDRANT_COMPONENT_SERVICE_HOST
  }
  After "cleanup"

  Describe "qdrant_current_pod_fqdn()"
    setup() {
      qdrant_runtime_pod_fqdn() {
        printf "%s" "qdrant-rollout-replace-qdrant-6.qdrant-rollout-replace-qdrant-headless.default.svc.cluster.local"
      }
    }
    Before "setup"

    It "uses the runtime pod FQDN for the advertised peer URI"
      When call qdrant_current_pod_fqdn
      The status should be success
      The output should eq "qdrant-rollout-replace-qdrant-6.qdrant-rollout-replace-qdrant-headless.default.svc.cluster.local"
    End

    It "fails when the runtime pod FQDN is empty"
      qdrant_runtime_pod_fqdn() {
        printf "%s" ""
      }

      When call qdrant_current_pod_fqdn
      The status should be failure
      The stderr should include "empty current pod FQDN"
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
      export CURRENT_POD_UID="pod-uid-initial"
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
      unset CURRENT_POD_UID QDRANT_BOOTSTRAP_OWNER_FILE
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
      The contents of file "$QDRANT_STORAGE_PATH/.kubeblocks-bootstrap-owner" should eq "bootstrap-attempt:pod-uid-initial"
    End

    It "does not repeat bootstrap after a container restart of the same pod"
      CURRENT_POD_NAME="qdrant-provision-qdrant-0"
      BOOTSTRAP_SERVICE_AVAILABLE=false
      QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_ATTEMPTS=1
      printf 'bootstrap-attempt:%s\n' "$CURRENT_POD_UID" > "$QDRANT_STORAGE_PATH/.kubeblocks-bootstrap-owner"
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "join"
      The stderr should include "initial bootstrap was already claimed"
    End

    It "does not bootstrap a recreated ordinal zero during a service outage"
      CURRENT_POD_NAME="qdrant-provision-qdrant-0"
      CURRENT_POD_UID="pod-uid-recreated"
      BOOTSTRAP_SERVICE_AVAILABLE=false
      QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_ATTEMPTS=1
      printf '%s\n' "bootstrap-attempt:pod-uid-original" > "$QDRANT_STORAGE_PATH/.kubeblocks-bootstrap-owner"
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "join"
      The stderr should include "initial bootstrap was already claimed"
    End

    It "fails closed when the pod UID needed for an initial bootstrap claim is missing"
      CURRENT_POD_NAME="qdrant-provision-qdrant-0"
      unset CURRENT_POD_UID
      BOOTSTRAP_SERVICE_AVAILABLE=false
      QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_ATTEMPTS=1
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "join"
      The stderr should include "CURRENT_POD_UID is required"
    End

    It "fails closed for legacy non-empty storage without raft state or a bootstrap marker"
      CURRENT_POD_NAME="qdrant-provision-qdrant-0"
      BOOTSTRAP_SERVICE_AVAILABLE=false
      QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_ATTEMPTS=1
      mkdir -p "$QDRANT_STORAGE_PATH/collections"
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "join"
      The stderr should include "storage is not empty"
    End

    It "fails closed when the initial bootstrap claim cannot be persisted"
      CURRENT_POD_NAME="qdrant-provision-qdrant-0"
      QDRANT_BOOTSTRAP_OWNER_FILE="$QDRANT_STORAGE_PATH/missing/owner"
      BOOTSTRAP_SERVICE_AVAILABLE=false
      QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_ATTEMPTS=1
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "join"
      The stderr should include "cannot persist the initial bootstrap claim"
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
      The contents of file "$QDRANT_STORAGE_PATH/.kubeblocks-bootstrap-owner" should eq "existing-cluster"
    End

    It "joins an existing cluster even when KubeBlocks reuses ordinal zero"
      CURRENT_POD_NAME="qdrant-rollout-replace-qdrant-0"
      BOOTSTRAP_SERVICE_AVAILABLE=true
      When call qdrant_start_mode "http://qdrant-rollout-replace-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "join"
      The contents of file "$QDRANT_STORAGE_PATH/.kubeblocks-bootstrap-owner" should eq "existing-cluster"
    End

    It "fails closed when an observed existing cluster cannot be recorded"
      CURRENT_POD_NAME="qdrant-rollout-replace-qdrant-0"
      QDRANT_BOOTSTRAP_OWNER_FILE="$QDRANT_STORAGE_PATH/missing/owner"
      BOOTSTRAP_SERVICE_AVAILABLE=true
      When call qdrant_start_mode "http://qdrant-rollout-replace-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be failure
      The output should eq ""
      The stderr should include "cannot persist the existing-cluster bootstrap marker"
    End

    It "restarts from durable raft state instead of rejoining"
      CURRENT_POD_NAME="qdrant-provision-qdrant-0"
      BOOTSTRAP_SERVICE_AVAILABLE=true
      echo '{"peer_id":1}' > "$QDRANT_STORAGE_PATH/raft_state.json"
      When call qdrant_start_mode "http://qdrant-provision-qdrant-qdrant.default.svc.cluster.local:6333"
      The status should be success
      The output should eq "restart"
      The contents of file "$QDRANT_STORAGE_PATH/.kubeblocks-bootstrap-owner" should eq "existing-cluster"
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
