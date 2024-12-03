# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_cluster_common_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Cluster Common Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file
  Include ../redis-cluster-scripts/redis-cluster-common.sh

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "get_all_shards_components()"
    Context "when ALL_SHARDS_COMPONENT_SHORT_NAMES is not set"
      It "returns 1 when ALL_SHARDS_COMPONENT_SHORT_NAMES is not set"
        When call get_all_shards_components
        The status should be failure
        The stderr should include "Error: Required environment variable ALL_SHARDS_COMPONENT_SHORT_NAMES is not set."
      End
    End

    Context "when ALL_SHARDS_COMPONENT_SHORT_NAMES is set"
      setup() {
        export ALL_SHARDS_COMPONENT_SHORT_NAMES="shard-98x:shard-98x,shard-cq7:shard-cq7,shard-hy7:shard-hy7"
      }
      Before "setup"

      un_setup() {
        unset ALL_SHARDS_COMPONENT_SHORT_NAMES
      }
      After "un_setup"

      It "returns all shard components"
        When call get_all_shards_components
        The status should be success
        The output should eq "shard-98x,shard-cq7,shard-hy7"
      End
    End
  End

  Describe "get_all_shards_pods()"
    setup() {
      export ALL_SHARDS_POD_NAME_LIST_SHARD_98X="redis-shard-98x-0,redis-shard-98x-1"
      export ALL_SHARDS_POD_NAME_LIST_SHARD_CQ7="redis-shard-cq7-0,redis-shard-cq7-1"
      export ALL_SHARDS_POD_NAME_LIST_SHARD_HY7="redis-shard-hy7-0,redis-shard-hy7-1"
    }
    Before "setup"

    un_setup() {
      unset ALL_SHARDS_POD_NAME_LIST_SHARD_98X
      unset ALL_SHARDS_POD_NAME_LIST_SHARD_CQ7
      unset ALL_SHARDS_POD_NAME_LIST_SHARD_HY7
    }
    After "un_setup"

    It "returns all shard pods"
      When call get_all_shards_pods
      The status should be success
      The output should eq "redis-shard-98x-0,redis-shard-98x-1,redis-shard-cq7-0,redis-shard-cq7-1,redis-shard-hy7-0,redis-shard-hy7-1"
    End
  End

  Describe "get_all_shards_pod_fqdns()"
    setup() {
      export ALL_SHARDS_POD_FQDN_LIST_SHARD_98X="redis-shard-98x-0.redis-shard-98x-headless.default.cluster.local,redis-shard-98x-1.redis-shard-98x-headless.default.cluster.local"
      export ALL_SHARDS_POD_FQDN_LIST_SHARD_CQ7="redis-shard-cq7-0.redis-shard-cq7-headless.default.cluster.local,redis-shard-cq7-1.redis-shard-cq7-headless.default.cluster.local"
      export ALL_SHARDS_POD_FQDN_LIST_SHARD_HY7="redis-shard-hy7-0.redis-shard-hy7-headless.default.cluster.local,redis-shard-hy7-1.redis-shard-hy7-headless.default.cluster.local"
    }
    Before "setup"

    un_setup() {
      unset ALL_SHARDS_POD_FQDN_LIST_SHARD_98X
      unset ALL_SHARDS_POD_FQDN_LIST_SHARD_CQ7
      unset ALL_SHARDS_POD_FQDN_LIST_SHARD_HY7
    }
    After "un_setup"

    It "returns all shard pod FQDNs"
      When call get_all_shards_pod_fqdns
      The status should be success
      The output should eq "redis-shard-98x-0.redis-shard-98x-headless.default.cluster.local,redis-shard-98x-1.redis-shard-98x-headless.default.cluster.local,redis-shard-cq7-0.redis-shard-cq7-headless.default.cluster.local,redis-shard-cq7-1.redis-shard-cq7-headless.default.cluster.local,redis-shard-hy7-0.redis-shard-hy7-headless.default.cluster.local,redis-shard-hy7-1.redis-shard-hy7-headless.default.cluster.local"
    End
  End

  Describe "parse_advertised_port()"
    It "parses advertised port from pod name and advertised ports"
      When call parse_advertised_port "redis-shard-98x-0" "redis-shard-98x-advertised-0:6379,redis-shard-98x-advertised-1:6380"
      The status should be success
      The output should eq "6379"
    End

    It "returns 1 when advertised port not found"
      When call parse_advertised_port "redis-shard-98x-2" "redis-shard-98x-advertised-0:6379,redis-shard-98x-advertised-1:6380"
      The status should be failure
    End
  End

  Describe "get_cluster_id()"
    It "gets cluster ID successfully"
      get_cluster_nodes_info() {
        echo "node1 172.0.0.1:6379@16379 myself,master - 0 1590000000000 1 connected 0-5460"$'\n'"node2 172.0.0.2:6379@16379 master - 0 1590000000000 2 connected 5461-10922"
        return 0
      }

      When call get_cluster_id "172.0.0.1" "6379"
      The status should be success
      The output should eq "node1"
    End

    It "returns 1 when failed to get cluster nodes info"
      get_cluster_nodes_info() {
        echo "Error"
        return 1
      }

      When call get_cluster_id "172.0.0.1" "6379"
      The status should be failure
      The stderr should include "Failed to get cluster nodes info in get_cluster_id"
    End
  End

  Describe "get_cluster_announce_ip()"
    It "gets cluster announce IP successfully"
      get_cluster_nodes_info() {
        echo "node1 172.0.0.1:6379@16379 myself,master - 0 1590000000000 1 connected 0-5460"$'\n'"node2 172.0.0.2:6379@16379 master - 0 1590000000000 2 connected 5461-10922"
        return 0
      }

      When call get_cluster_announce_ip "172.0.0.1" "6379"
      The status should be success
      The output should eq "172.0.0.1"
    End

    It "returns 1 when failed to get cluster nodes info"
      get_cluster_nodes_info() {
        echo "Error"
        return 1
      }

      When call get_cluster_announce_ip "172.0.0.1" "6379"
      The status should be failure
      The stderr should include "Failed to get cluster nodes info in get_cluster_announce_ip"
    End
  End

  Describe "check_node_in_cluster()"
    It "returns 0 when node exists in the cluster"
      get_cluster_nodes_info() {
        echo "node1 172.0.0.1:6379@16379 myself,master - 0 1590000000000 1 connected 0-5460"$'\n'"node2 172.0.0.2:6379@16379 master - 0 1590000000000 2 connected 5461-10922"
        return 0
      }

      When call check_node_in_cluster "172.0.0.1" "6379" "node1"
      The status should be success
    End

    It "returns 1 when node does not exist in the cluster"
      get_cluster_nodes_info() {
        echo "node1 172.0.0.1:6379@16379 myself,master - 0 1590000000000 1 connected 0-5460"$'\n'"node2 172.0.0.2:6379@16379 master - 0 1590000000000 2 connected 5461-10922"
        return 0
      }

      When call check_node_in_cluster "172.0.0.1" "6379" "node3"
      The status should be failure
    End

    It "returns 1 when failed to get cluster nodes info"
      get_cluster_nodes_info() {
        echo "Error"
        return 1
      }

      When call check_node_in_cluster "172.0.0.1" "6379" "node1"
      The status should be failure
      The stderr should include "Failed to get cluster nodes info in check_node_in_cluster"
    End
  End

  Describe "check_cluster_initialized()"
    Context "returns 0 when cluster is initialized"
      get_cluster_info() {
        echo "cluster_state:ok"
        return 0
      }

      setup() {
        export KB_CLUSTER_POD_IP_LIST="172.0.0.1,172.0.0.2"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns 0 when cluster is initialized"
        When call check_cluster_initialized "$KB_CLUSTER_POD_IP_LIST" "$SERVICE_PORT"
        The status should be success
        The output should include "Redis Cluster already initialized"
      End
    End

    Context "returns 1 when cluster is not initialized"
      get_cluster_info() {
        echo "cluster_state:fail"
        return 0
      }

      setup() {
        export KB_CLUSTER_POD_IP_LIST="172.0.0.1,172.0.0.2"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns 1 when cluster is not initialized"
        When call check_cluster_initialized "$KB_CLUSTER_POD_IP_LIST" "$SERVICE_PORT"
        The status should be failure
        The stderr should include "Redis Cluster not initialized"
      End
    End

    Context "returns 1 when cluster_node_list or cluster_node_service_port is empty"
      setup() {
        export KB_CLUSTER_POD_IP_LIST=""
        export SERVICE_PORT=""
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns 1 when cluster_node_list or cluster_node_service_port is empty"
        When run check_cluster_initialized "$KB_CLUSTER_POD_IP_LIST" "$SERVICE_PORT"
        The status should be failure
        The stderr should include "Error: Required environment variable cluster_node_list or cluster_node_service_port  is not set."
      End
    End
  End

  Describe "build_redis_cluster_create_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      It "builds Redis cluster create command without password"
        primary_nodes="172.0.0.1:6379 172.0.0.2:6379"

        When call build_redis_cluster_create_command "$primary_nodes"
        The output should eq "redis-cli --cluster create 172.0.0.1:6379 172.0.0.2:6379 --cluster-yes"
        The stderr should include "initialize cluster command: redis-cli --cluster create 172.0.0.1:6379 172.0.0.2:6379 --cluster-yes"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is set"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password"
      }
      Before "setup"

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After "un_setup"

      It "builds Redis cluster create command with password"
        primary_nodes="172.0.0.1:6379 172.0.0.2:6379"

        When call build_redis_cluster_create_command "$primary_nodes"
        The output should eq "redis-cli --cluster create 172.0.0.1:6379 172.0.0.2:6379 -a password --cluster-yes"
        The stderr should include "initialize cluster command: redis-cli --cluster create 172.0.0.1:6379 172.0.0.2:6379 -a ******** --cluster-yes"
      End
    End
  End

  Describe "build_secondary_replicated_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      It "builds secondary replicated command without password"
        secondary_endpoint_with_port="172.0.0.3:6379"
        mapping_primary_endpoint_with_port="172.0.0.1:6379"
        mapping_primary_cluster_id="node1"

        When call build_secondary_replicated_command "$secondary_endpoint_with_port" "$mapping_primary_endpoint_with_port" "$mapping_primary_cluster_id"
        The output should eq "redis-cli --cluster add-node 172.0.0.3:6379 172.0.0.1:6379 --cluster-slave --cluster-master-id node1"
        The stderr should include "initialize cluster secondary add-node command: redis-cli --cluster add-node 172.0.0.3:6379 172.0.0.1:6379 --cluster-slave --cluster-master-id node1"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is set"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password"
      }
      Before "setup"

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After "un_setup"

      It "builds secondary replicated command with password"
        secondary_endpoint_with_port="172.0.0.3:6379"
        mapping_primary_endpoint_with_port="172.0.0.1:6379"
        mapping_primary_cluster_id="node1"

        When call build_secondary_replicated_command "$secondary_endpoint_with_port" "$mapping_primary_endpoint_with_port" "$mapping_primary_cluster_id"
        The output should eq "redis-cli --cluster add-node 172.0.0.3:6379 172.0.0.1:6379 --cluster-slave --cluster-master-id node1 -a password"
        The stderr should include "initialize cluster secondary add-node command: redis-cli --cluster add-node 172.0.0.3:6379 172.0.0.1:6379 --cluster-slave --cluster-master-id node1 -a ********"
      End
    End
  End

  Describe "build_scale_out_shard_primary_join_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      It "builds scale out shard primary join command without password"
        scale_out_shard_default_primary_endpoint_with_port="172.0.0.4:6379"
        exist_available_node="172.0.0.2:6379"

        When call build_scale_out_shard_primary_join_command "$scale_out_shard_default_primary_endpoint_with_port" "$exist_available_node"
        The output should eq "redis-cli --cluster add-node 172.0.0.4:6379 172.0.0.2:6379"
        The stderr should include "scale out shard primary add-node command: redis-cli --cluster add-node 172.0.0.4:6379 172.0.0.2:6379"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is set"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password"
      }
      Before "setup"

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After "un_setup"

      It "builds scale out shard primary join command with password"
        scale_out_shard_default_primary_endpoint_with_port="172.0.0.4:6379"
        exist_available_node="172.0.0.2:6379"

        When call build_scale_out_shard_primary_join_command "$scale_out_shard_default_primary_endpoint_with_port" "$exist_available_node"
        The output should eq "redis-cli --cluster add-node 172.0.0.4:6379 172.0.0.2:6379 -a password"
        The stderr should include "scale out shard primary add-node command: redis-cli --cluster add-node 172.0.0.4:6379 172.0.0.2:6379 -a ********"
      End
    End
  End

  Describe "build_reshard_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      It "builds reshard command without password"
        primary_node_with_port="172.0.0.1:6379"
        mapping_primary_cluster_id="node1"
        slots_per_shard="5461"

        When call build_reshard_command "$primary_node_with_port" "$mapping_primary_cluster_id" "$slots_per_shard"
        The output should eq "redis-cli --cluster reshard 172.0.0.1:6379 --cluster-from all --cluster-to node1 --cluster-slots 5461 --cluster-yes"
        The stderr should include "scale out shard reshard command: redis-cli --cluster reshard 172.0.0.1:6379 --cluster-from all --cluster-to node1 --cluster-slots 5461 --cluster-yes"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is set"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password"
      }
      Before "setup"

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After "un_setup"

      It "builds reshard command with password"
        primary_node_with_port="172.0.0.1:6379"
        mapping_primary_cluster_id="node1"
        slots_per_shard="5461"

        When call build_reshard_command "$primary_node_with_port" "$mapping_primary_cluster_id" "$slots_per_shard"
        The output should eq "redis-cli --cluster reshard 172.0.0.1:6379 --cluster-from all --cluster-to node1 --cluster-slots 5461 -a password --cluster-yes"
        The stderr should include "scale out shard reshard command: redis-cli --cluster reshard 172.0.0.1:6379 --cluster-from all --cluster-to node1 --cluster-slots 5461 -a ******** --cluster-yes"
      End
    End
  End

  Describe "build_rebalance_to_zero_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      It "builds rebalance to zero command without password"
        node_with_port="172.0.0.1:6379"
        node_cluster_id="node1"

        When call build_rebalance_to_zero_command "$node_with_port" "$node_cluster_id"
        The output should eq "redis-cli --cluster rebalance 172.0.0.1:6379 --cluster-weight node1=0 --cluster-yes "
        The stderr should include "set current component slot to 0 by rebalance command: redis-cli --cluster rebalance 172.0.0.1:6379 --cluster-weight node1=0 --cluster-yes"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is set"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password"
      }
      Before "setup"

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After "un_setup"

      It "builds rebalance to zero command with password"
        node_with_port="172.0.0.1:6379"
        node_cluster_id="node1"

        When call build_rebalance_to_zero_command "$node_with_port" "$node_cluster_id"
        The output should eq "redis-cli --cluster rebalance 172.0.0.1:6379 --cluster-weight node1=0 --cluster-yes -a password"
        The stderr should include "set current component slot to 0 by rebalance command: redis-cli --cluster rebalance 172.0.0.1:6379 --cluster-weight node1=0 --cluster-yes -a ********"
      End
    End
  End

  Describe "build_del_node_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      setup() {
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset SERVICE_PORT
      }
      After "un_setup"

      It "builds del node command without password"
        available_node="172.0.0.2:6379"
        node_to_del_cluster_id="node1"

        When call build_del_node_command "$available_node" "$node_to_del_cluster_id"
        The output should eq "redis-cli --cluster del-node 172.0.0.2:6379 node1 -p 6379"
        The stderr should include "del node command: redis-cli --cluster del-node 172.0.0.2:6379 node1 -p 6379"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is set"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
        unset SERVICE_PORT
      }
      After "un_setup"

      It "builds del node command with password"
        available_node="172.0.0.2:6379"
        node_to_del_cluster_id="node1"

        When call build_del_node_command "$available_node" "$node_to_del_cluster_id"
        The output should eq "redis-cli --cluster del-node 172.0.0.2:6379 node1 -p 6379 -a password"
        The stderr should include "del node command: redis-cli --cluster del-node 172.0.0.2:6379 node1 -p 6379 -a ********"
      End
    End
  End

  Describe "build_acl_save_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      It "builds acl save command without password"
        When call build_acl_save_command
        The output should eq "redis-cli -h 127.0.0.1 -p 6379 acl save"
        The stderr should include "acl save command: redis-cli -h 127.0.0.1 -p 6379 acl save"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is set"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password"
      }
      Before "setup"

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After "un_setup"

      It "builds acl save command with password"
        When call build_acl_save_command
        The output should eq "redis-cli -h 127.0.0.1 -p 6379 -a password acl save"
        The stderr should include "acl save command: redis-cli -h 127.0.0.1 -p 6379 -a ******** acl save"
      End
    End
  End
End