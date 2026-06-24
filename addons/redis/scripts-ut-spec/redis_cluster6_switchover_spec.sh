# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_cluster6_switchover_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Cluster6 Switchover Script Tests"
  Include ../redis-cluster-scripts/redis-cluster6-switchover.sh
  Include ../redis-cluster-scripts/redis-cluster-common.sh
  Include $common_library_file

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "get_all_shards_master()"
    Context "when cluster has healthy masters only"
      It "returns all master addresses"
        redis-cli() {
          echo "node1-id 10.0.0.1:6379@16379 master - 0 1234567890 1 connected 0-5460
node2-id 10.0.0.2:6379@16379 master - 0 1234567890 2 connected 5461-10922
node3-id 10.0.0.3:6379@16379 master - 0 1234567890 3 connected 10923-16383
node4-id 10.0.0.4:6379@16379 slave node1-id 0 1234567890 1 connected"
        }
        When call get_all_shards_master "10.0.0.1" "6379"
        The status should be success
        The line 1 of output should equal "10.0.0.1:6379"
        The line 2 of output should equal "10.0.0.2:6379"
        The line 3 of output should equal "10.0.0.3:6379"
      End
    End

    Context "when cluster has a failed master"
      It "filters out failed masters"
        redis-cli() {
          echo "node1-id 10.0.0.1:6379@16379 master - 0 1234567890 1 connected 0-5460
node2-id 10.0.0.2:6379@16379 master,fail - 0 1234567890 2 connected 5461-10922
node3-id 10.0.0.3:6379@16379 master - 0 1234567890 3 connected 10923-16383
node4-id 10.0.0.4:6379@16379 slave node1-id 0 1234567890 1 connected"
        }
        When call get_all_shards_master "10.0.0.1" "6379"
        The status should be success
        The line 1 of output should equal "10.0.0.1:6379"
        The line 2 of output should equal "10.0.0.3:6379"
      End

      It "regression: reverting grep -v fail causes failed masters to appear"
        redis-cli() {
          echo "node1-id 10.0.0.1:6379@16379 master - 0 1234567890 1 connected 0-5460
node2-id 10.0.0.2:6379@16379 master,fail - 0 1234567890 2 connected 5461-10922
node3-id 10.0.0.3:6379@16379 master - 0 1234567890 3 connected 10923-16383"
        }
        When call get_all_shards_master "10.0.0.1" "6379"
        The status should be success
        The output should not include "10.0.0.2:6379"
      End
    End

    Context "when cluster has a fail? (pfail) master"
      It "filters out pfail masters"
        redis-cli() {
          echo "node1-id 10.0.0.1:6379@16379 master - 0 1234567890 1 connected 0-5460
node2-id 10.0.0.2:6379@16379 master,fail? - 0 1234567890 2 connected 5461-10922
node3-id 10.0.0.3:6379@16379 master - 0 1234567890 3 connected 10923-16383"
        }
        When call get_all_shards_master "10.0.0.1" "6379"
        The status should be success
        The output should not include "10.0.0.2:6379"
        The line 1 of output should equal "10.0.0.1:6379"
        The line 2 of output should equal "10.0.0.3:6379"
      End
    End

    Context "when all masters are healthy"
      It "returns all masters when none are failed"
        redis-cli() {
          echo "node1-id 10.0.0.1:6379@16379 myself,master - 0 1234567890 1 connected 0-5460
node2-id 10.0.0.2:6379@16379 master - 0 1234567890 2 connected 5461-10922"
        }
        When call get_all_shards_master "10.0.0.1" "6379"
        The status should be success
        The line 1 of output should equal "10.0.0.1:6379"
        The line 2 of output should equal "10.0.0.2:6379"
      End
    End
  End

  Describe "switchover_without_candidate()"
    setup() {
      export CURRENT_SHARD_POD_NAME_LIST="pod-0,pod-1,pod-2"
      export CURRENT_SHARD_POD_FQDN_LIST="pod-0.svc:pod-0.svc.cluster.local,pod-1.svc:pod-1.svc.cluster.local,pod-2.svc:pod-2.svc.cluster.local"
      export CURRENT_POD_IP="10.0.0.1"
      service_port=6379
    }
    Before 'setup'

    cleanup() {
      unset CURRENT_SHARD_POD_NAME_LIST
      unset CURRENT_SHARD_POD_FQDN_LIST
      unset CURRENT_POD_IP
    }
    After 'cleanup'

    Context "when do_switchover succeeds"
      It "should propagate success"
        get_cluster_nodes_info() {
          echo "node1 10.0.0.1:6379 master
node2 10.0.0.2:6379 slave"
        }
        check_redis_role() {
          echo "secondary"
        }
        get_target_pod_fqdn_from_pod_fqdn_vars() {
          echo "$2.svc.cluster.local"
        }
        do_switchover() { return 0; }
        When call switchover_without_candidate
        The status should be success
      End
    End

    Context "when do_switchover fails"
      It "should propagate failure"
        get_cluster_nodes_info() {
          echo "node1 10.0.0.1:6379 master
node2 10.0.0.2:6379 slave"
        }
        check_redis_role() {
          echo "secondary"
        }
        get_target_pod_fqdn_from_pod_fqdn_vars() {
          echo "$2.svc.cluster.local"
        }
        do_switchover() { return 1; }
        When call switchover_without_candidate
        The status should be failure
      End
    End

    Context "when no eligible secondary found"
      It "should fail with error"
        get_cluster_nodes_info() {
          echo "node1 10.0.0.1:6379 master
node2 10.0.0.2:6379 slave"
        }
        check_redis_role() {
          echo "primary"
        }
        get_target_pod_fqdn_from_pod_fqdn_vars() {
          echo "$2.svc.cluster.local"
        }
        When call switchover_without_candidate
        The status should be failure
        The stderr should include "No eligible secondary"
      End
    End

    Context "when pod already removed from cluster"
      It "should return success with message"
        get_cluster_nodes_info() {
          echo "myself,master 10.0.0.1:6379"
        }
        When call switchover_without_candidate
        The status should be success
        The stdout should include "no need to perform switch over"
      End
    End

    Context "when cluster nodes info fails"
      It "should fail with error"
        get_cluster_nodes_info() { return 1; }
        When call switchover_without_candidate
        The status should be failure
        The stderr should include "Failed to get cluster nodes info"
      End
    End
  End

  Describe "switchover_with_candidate()"
    setup() {
      service_port=6379
    }
    Before 'setup'

    Context "when KB_SWITCHOVER_CANDIDATE_FQDN is empty"
      It "should fail with error"
        export KB_SWITCHOVER_CANDIDATE_FQDN=""
        export KB_SWITCHOVER_CANDIDATE_NAME="pod-1"
        When call switchover_with_candidate
        The status should be failure
        The stderr should include "KB_SWITCHOVER_CANDIDATE_NAME or KB_SWITCHOVER_CANDIDATE_FQDN is empty"
        unset KB_SWITCHOVER_CANDIDATE_FQDN KB_SWITCHOVER_CANDIDATE_NAME
      End
    End

    Context "when do_switchover succeeds"
      It "should propagate success"
        export KB_SWITCHOVER_CANDIDATE_FQDN="pod-1.svc.cluster.local"
        export KB_SWITCHOVER_CANDIDATE_NAME="pod-1"
        do_switchover() { return 0; }
        When call switchover_with_candidate
        The status should be success
        unset KB_SWITCHOVER_CANDIDATE_FQDN KB_SWITCHOVER_CANDIDATE_NAME
      End
    End

    Context "when do_switchover fails"
      It "should propagate failure"
        export KB_SWITCHOVER_CANDIDATE_FQDN="pod-1.svc.cluster.local"
        export KB_SWITCHOVER_CANDIDATE_NAME="pod-1"
        do_switchover() { return 1; }
        When call switchover_with_candidate
        The status should be failure
        unset KB_SWITCHOVER_CANDIDATE_FQDN KB_SWITCHOVER_CANDIDATE_NAME
      End
    End
  End
End
