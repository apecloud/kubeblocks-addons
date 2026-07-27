# shellcheck shell=bash

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_cluster5_server_start_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library "$common_library_file"

Describe "Redis 5 Cluster server start Bash script tests"
  Include "$common_library_file"
  Include ../redis-cluster-scripts/redis-cluster-common.sh
  Include ../redis-cluster-scripts/redis-cluster5-server-start.sh

  export getent_calls="./redis5-getent-calls"
  ensure_calls="./redis5-ensure-calls"

  setup_ip_only_cluster() {
    unset CURRENT_SHARD_ADVERTISED_PORT
    unset REDIS_CLUSTER_ALL_SHARDS_HOST_NETWORK_PORT
    export ALL_SHARDS_COMPONENT_SHORT_NAMES="shard-a,shard-b,shard-c"
    export CURRENT_SHARD_COMPONENT_NAME="redis-shard-a"
    export CURRENT_SHARD_POD_NAME_LIST="redis-shard-a-0,redis-shard-a-1"
    export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-a-0.redis-shard-a-headless.default.svc.cluster.local,redis-shard-a-1.redis-shard-a-headless.default.svc.cluster.local"
    export CLUSTER_NAMESPACE="default"

    current_comp_primary_node=()
    current_comp_primary_fail_node=()
    current_comp_other_nodes=()
    other_comp_primary_nodes=()
    other_comp_primary_fail_nodes=()
    other_comp_other_nodes=()
    rm -f "$getent_calls" "$ensure_calls"
  }

  get_cluster_nodes_info() {
    printf '%s\n' \
      "primary-a 10.42.0.227:6379@16379 master - 0 1 1 connected 0-5460" \
      "replica-a 10.42.0.228:6379@16379 slave primary-a 0 1 1 connected" \
      "primary-b 10.42.0.229:6379@16379 master - 0 1 2 connected 5461-10922"
  }

  Mock getent
    echo "$2" >> "$getent_calls"
    case "$2" in
      redis-shard-a-0.*) echo "10.42.0.227 $2" ;;
      redis-shard-a-1.*) echo "10.42.0.228 $2" ;;
      *) return 2 ;;
    esac
  End

  cleanup() {
    rm -f "$common_library_file" "$getent_calls" "$ensure_calls"
  }
  AfterAll "cleanup"

  Describe "get_current_comp_nodes_for_scale_out_replica()"
    Before "setup_ip_only_cluster"

    It "classifies IP-only Redis 5 nodes by the current shard Pod list"
      When call get_current_comp_nodes_for_scale_out_replica \
        "redis-shard-a-0.redis-shard-a-headless.default.svc.cluster.local" \
        "6379"
      The status should be success
      The variable current_comp_primary_node should equal "10.42.0.227#10.42.0.227:6379@16379"
      The variable current_comp_other_nodes should equal "10.42.0.228#10.42.0.228:6379@16379"
      The variable other_comp_primary_nodes should equal "10.42.0.229#10.42.0.229:6379@16379"
      The variable other_comp_other_nodes should be blank
      The stdout should include "current_comp_primary_node: 10.42.0.227#10.42.0.227:6379@16379"
      The contents of file "$getent_calls" should equal "redis-shard-a-0.redis-shard-a-headless.default.svc.cluster.local
redis-shard-a-1.redis-shard-a-headless.default.svc.cluster.local"
    End
  End

  Describe "scale_redis_cluster_replica()"
    setup_membership_route() {
      setup_ip_only_cluster
      export CURRENT_POD_NAME="redis-shard-a-1"
      export service_port="6379"
      export redis_announce_host_value="10.42.0.228"
    }
    Before "setup_membership_route"

    check_redis_server_ready_with_retry() { return 0; }
    check_node_in_cluster_with_retry() { return 0; }
    get_cluster_id_with_retry() { echo "primary-a"; }
    get_current_shard_node_ids() { echo "primary-a,replica-a"; }
    ensure_current_node_replication() {
      printf '%s\n' "$*" >> "$ensure_calls"
      return 0
    }
    check_and_meet_current_primary_node() { return 0; }

    It "routes an existing Redis 5 member through replication convergence"
      When run scale_redis_cluster_replica
      The status should be success
      The stdout should not include "current_comp_primary_node is empty, skip scale out replica"
      The stdout should include "Current pod redis-shard-a-1 is a secondary node"
      The contents of file "$ensure_calls" should equal "10.42.0.227 6379 primary-a primary-a,replica-a"
    End
  End
End
