# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_cluster_switchover_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Cluster Switchover Script Tests"
  Include $common_library_file
  Include ../redis-cluster-scripts/redis-cluster-common.sh
  Include ../redis-cluster-scripts/redis-cluster-switchover.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "switchover_without_candidate()"
    setup() {
      export REDIS_DEFAULT_PASSWORD="password"
      export SERVICE_PORT="6379"
      export CURRENT_POD_IP="10.0.0.1"
      export CURRENT_SHARD_POD_NAME_LIST="pod-0,pod-1"
      export CURRENT_SHARD_POD_FQDN_LIST="pod-0.svc,pod-1.svc"
      service_port=6379
    }
    Before 'setup'

    cleanup() {
      unset REDIS_DEFAULT_PASSWORD SERVICE_PORT CURRENT_POD_IP
      unset CURRENT_SHARD_POD_NAME_LIST CURRENT_SHARD_POD_FQDN_LIST
    }
    After 'cleanup'

    It "should call do_switchover with need_check true"
      get_cluster_nodes_info() {
        echo "node1 10.0.0.1:6379@16379 myself,master - 0 0 1 connected 0-5460"
        echo "node2 10.0.0.2:6379@16379 slave abc123 0 0 1 connected"
      }
      get_target_pod_fqdn_from_pod_fqdn_vars() { echo "pod-1.svc"; }
      check_redis_role() { echo "secondary"; }
      do_switchover() {
        if [ "$3" != "true" ]; then
          echo "need_check was '$3', expected 'true'" >&2
          return 1
        fi
        return 0
      }

      When call switchover_without_candidate
      The status should be success
    End

    It "should propagate do_switchover failure"
      get_cluster_nodes_info() {
        echo "node1 10.0.0.1:6379@16379 myself,master - 0 0 1 connected 0-5460"
        echo "node2 10.0.0.2:6379@16379 slave abc123 0 0 1 connected"
      }
      get_target_pod_fqdn_from_pod_fqdn_vars() { echo "pod-1.svc"; }
      check_redis_role() { echo "secondary"; }
      do_switchover() { return 1; }

      When call switchover_without_candidate
      The status should be failure
    End

    It "should succeed when do_switchover succeeds"
      get_cluster_nodes_info() {
        echo "node1 10.0.0.1:6379@16379 myself,master - 0 0 1 connected 0-5460"
        echo "node2 10.0.0.2:6379@16379 slave abc123 0 0 1 connected"
      }
      get_target_pod_fqdn_from_pod_fqdn_vars() { echo "pod-1.svc"; }
      check_redis_role() { echo "secondary"; }
      do_switchover() { echo "Switchover successful"; return 0; }

      When call switchover_without_candidate
      The status should be success
      The stdout should include "Switchover successful"
    End

    It "should fail when no eligible secondary found"
      get_cluster_nodes_info() {
        echo "node1 10.0.0.1:6379@16379 myself,master - 0 0 1 connected 0-5460"
        echo "node2 10.0.0.2:6379@16379 slave abc123 0 0 1 connected"
      }
      get_target_pod_fqdn_from_pod_fqdn_vars() { echo "pod-1.svc"; }
      check_redis_role() { echo "primary"; }

      When call switchover_without_candidate
      The status should be failure
      The stderr should include "No eligible secondary found"
    End

    It "should skip switchover when pod already removed from cluster"
      get_cluster_nodes_info() {
        echo "node1 10.0.0.1:6379@16379 myself,master - 0 0 1 connected 0-5460"
      }

      When call switchover_without_candidate
      The status should be success
      The stdout should include "no need to perform switch over"
    End

    It "should fail when cluster nodes info fails"
      get_cluster_nodes_info() { return 1; }

      When call switchover_without_candidate
      The status should be failure
      The stderr should include "Failed to get cluster nodes info"
    End
  End

  Describe "switchover_with_candidate()"
    setup() {
      export REDIS_DEFAULT_PASSWORD="password"
      export SERVICE_PORT="6379"
      export KB_SWITCHOVER_CANDIDATE_FQDN="candidate.svc"
      export KB_SWITCHOVER_CANDIDATE_NAME="candidate-0"
      service_port=6379
    }
    Before 'setup'

    cleanup() {
      unset REDIS_DEFAULT_PASSWORD SERVICE_PORT
      unset KB_SWITCHOVER_CANDIDATE_FQDN KB_SWITCHOVER_CANDIDATE_NAME
    }
    After 'cleanup'

    It "should fail when candidate FQDN is empty"
      export KB_SWITCHOVER_CANDIDATE_FQDN=""
      When call switchover_with_candidate
      The status should be failure
      The stderr should include "KB_SWITCHOVER_CANDIDATE_NAME or KB_SWITCHOVER_CANDIDATE_FQDN is empty"
    End

    It "should propagate do_switchover failure"
      do_switchover() { return 1; }
      When call switchover_with_candidate
      The status should be failure
    End

    It "should succeed when do_switchover succeeds"
      do_switchover() { echo "Switchover successful"; return 0; }
      When call switchover_with_candidate
      The status should be success
      The stdout should include "Switchover successful"
    End
  End
End
