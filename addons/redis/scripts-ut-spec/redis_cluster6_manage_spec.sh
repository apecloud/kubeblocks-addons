# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_cluster6_manage_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Cluster6 Manage Script Tests"
  Include $common_library_file
  Include ../redis-cluster-scripts/redis-cluster-common.sh
  Include ../redis-cluster-scripts/redis-cluster6-manage.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "scale_out_redis_cluster_shard() secondary membership detection"
    Context "when secondary is already in the cluster (Redis 6 IP-based detection)"
      init_current_comp_default_nodes_for_scale_out() {
        declare -gA scale_out_shard_default_primary_node
        scale_out_shard_default_primary_node["redis-shard-98x-0"]="10.42.0.1:6379"
        declare -gA scale_out_shard_default_other_nodes
        scale_out_shard_default_other_nodes["redis-shard-98x-1"]="10.42.0.2:6379"
      }

      get_cluster_id() { echo "cluster_id_123"; }

      check_slots_covered() {
        if [ "$1" = "10.42.0.1:6379" ]; then return 0; else return 1; fi
      }

      check_current_shard_other_nodes_are_joined() { return 0; }

      count_node_slots() { echo "16384"; }

      check_node_in_cluster() {
        local node_name="$3"
        if [ "$node_name" = "10.42.0.2:6379" ]; then
          return 0
        fi
        if [ "$node_name" = "redis-shard-98x-1" ]; then
          echo "BUG: check_node_in_cluster received pod name instead of IP:port" >&2
          return 1
        fi
        return 1
      }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard-98x"
        export CURRENT_SHARD_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_FQDN_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_LIST="shard-98x"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset CURRENT_SHARD_COMPONENT_NAME
        unset CURRENT_SHARD_POD_NAME_LIST
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_FQDN_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "detects already-joined secondary by IP:port and skips re-adding"
        When call scale_out_redis_cluster_shard
        The status should be success
        The output should include "Secondary node redis-shard-98x-1 already joined the cluster, skip replicating to primary"
        The stderr should not include "BUG: check_node_in_cluster received pod name instead of IP:port"
      End
    End

    Context "when secondary is NOT in the cluster and needs to be added"
      init_current_comp_default_nodes_for_scale_out() {
        declare -gA scale_out_shard_default_primary_node
        scale_out_shard_default_primary_node["redis-shard-98x-0"]="10.42.0.1:6379"
        declare -gA scale_out_shard_default_other_nodes
        scale_out_shard_default_other_nodes["redis-shard-98x-1"]="10.42.0.3:6379"
      }

      get_cluster_id() { echo "cluster_id_456"; }

      check_slots_covered() { return 0; }

      check_current_shard_other_nodes_are_joined() { return 1; }

      check_node_in_cluster() { return 1; }

      secondary_replicated_to_primary() {
        if [ "$1" = "10.42.0.3:6379" ]; then
          return 0
        fi
        return 1
      }

      count_node_slots() { echo "16384"; }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard-98x"
        export CURRENT_SHARD_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_FQDN_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_LIST="shard-98x"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset CURRENT_SHARD_COMPONENT_NAME
        unset CURRENT_SHARD_POD_NAME_LIST
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_FQDN_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "adds secondary when it is not yet in the cluster"
        When call scale_out_redis_cluster_shard
        The status should be success
        The output should include "Redis cluster scale out shard secondary node redis-shard-98x-1 successfully"
      End
    End

    Context "regression: reverting to pod name breaks Redis 6 IP-based detection"
      init_current_comp_default_nodes_for_scale_out() {
        declare -gA scale_out_shard_default_primary_node
        scale_out_shard_default_primary_node["redis-shard-98x-0"]="10.42.0.1:6379"
        declare -gA scale_out_shard_default_other_nodes
        scale_out_shard_default_other_nodes["redis-shard-98x-1"]="10.42.0.2:6379"
      }

      get_cluster_id() { echo "cluster_id_789"; }

      check_slots_covered() {
        if [ "$1" = "10.42.0.1:6379" ]; then return 0; else return 1; fi
      }

      check_current_shard_other_nodes_are_joined() { return 1; }

      count_node_slots() { echo "16384"; }

      captured_node_name=""
      check_node_in_cluster() {
        captured_node_name="$3"
        if [ "$3" = "10.42.0.2:6379" ]; then
          return 0
        fi
        return 1
      }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard-98x"
        export CURRENT_SHARD_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_FQDN_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_LIST="shard-98x"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset CURRENT_SHARD_COMPONENT_NAME
        unset CURRENT_SHARD_POD_NAME_LIST
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_FQDN_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "passes IP:port to check_node_in_cluster even when check_current_shard_other_nodes_are_joined fails"
        When call scale_out_redis_cluster_shard
        The status should be success
        The output should include "Secondary node redis-shard-98x-1 already joined the cluster, skip replicating to primary"
      End
    End
  End

  Describe "sync_acl_for_redis_cluster_shard() (Redis 6)"
    # Contract mirrors redis_cluster_manage_spec.sh: only a pod reporting
    # cluster_state "ok" with a successful ACL LIST may be trusted; otherwise
    # fail closed instead of silently skipping ACL sync (which would leave a
    # scaled-out Redis 6 shard without the cluster's custom ACL users).
    get_pod_service_port_by_network_mode() {
      echo "6379"
    }

    setup_sync_acl() {
      export KB_CLUSTER_POD_FQDN_LIST="src-0,src-1"
      export CURRENT_SHARD_POD_FQDN_LIST="dst-0"
      export SERVICE_PORT="6379"
      export REDIS_DEFAULT_PASSWORD=""
    }
    Before "setup_sync_acl"

    un_setup_sync_acl() {
      unset KB_CLUSTER_POD_FQDN_LIST CURRENT_SHARD_POD_FQDN_LIST SERVICE_PORT REDIS_DEFAULT_PASSWORD
    }
    After "un_setup_sync_acl"

    Context "when reachable pods never report cluster_state ok"
      get_cluster_info_with_retry() {
        echo ""
        return 0
      }

      It "fails closed instead of silently skipping ACL sync"
        When run sync_acl_for_redis_cluster_shard
        The status should be failure
        The stdout should include "Sync ACL rules for redis cluster shard..."
        The stderr should include "Failed to get ACL LIST from other shard pods"
      End
    End

    Context "when the source pod is ok but ACL LIST fails"
      get_cluster_info_with_retry() {
        printf 'cluster_state:ok\n'
        return 0
      }
      redis-cli() {
        case "$*" in
          *"ACL LIST"*) return 1 ;;
          *) echo "OK" ;;
        esac
      }

      It "does not treat a failed ACL LIST as 'no rules'; fails closed"
        When run sync_acl_for_redis_cluster_shard
        The status should be failure
        The stdout should include "Sync ACL rules for redis cluster shard..."
        The stderr should include "Failed to get ACL LIST from other shard pods"
      End
    End

    Context "when a source pod returns ACL rules (happy path)"
      get_cluster_info_with_retry() {
        printf 'cluster_state:ok\n'
        return 0
      }
      redis-cli() {
        case "$*" in
          *"ACL LIST"*) printf 'user default on nopass ~* +@all\nuser appuser on >secret ~* +@all\n' ;;
          *) echo "OK" ;;
        esac
      }

      It "syncs non-default ACL users without failing"
        When run sync_acl_for_redis_cluster_shard
        The status should be success
        The stdout should include "Sync ACL rules for redis cluster shard..."
        The stderr should not include "Failed to get ACL LIST from other shard pods"
      End
    End
  End
End
