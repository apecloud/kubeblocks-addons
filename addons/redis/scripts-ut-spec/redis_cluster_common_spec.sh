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

  Describe "parse_advertised_svc_and_port()"
    It "parses advertised port from pod name and advertised ports"
      When call parse_advertised_svc_and_port "redis-shard-98x-0" "redis-shard-98x-advertised-0:6379,redis-shard-98x-advertised-1:6380"
      The status should be success
      The output should eq "6379"
    End

    It "returns 1 when advertised port not found"
      When call parse_advertised_svc_and_port "redis-shard-98x-2" "redis-shard-98x-advertised-0:6379,redis-shard-98x-advertised-1:6380"
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

  Describe "fix_cluster_slots()"
    setup() {
      export REDIS_DEFAULT_PASSWORD=""
      export REDIS_CLI_TLS_CMD=""
    }
    Before "setup"

    un_setup() {
      unset REDIS_DEFAULT_PASSWORD
      unset REDIS_CLI_TLS_CMD
    }
    After "un_setup"

    It "answers redis-cli cluster fix confirmation non-interactively"
      redis-cli() {
        local answer=""
        read -r answer || true
        [ "$answer" = "yes" ]
      }

      When call fix_cluster_slots "redis-0:6379" "6379"
      The status should be success
      The error should include "printf yes... | redis-cli"
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

    Context "returns 1 when cluster_node_list or cluster_pod_name_list is empty"
      setup() {
        export KB_CLUSTER_POD_FQDN_LIST=""
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_FQDN_LIST
      }
      After "un_setup"

      It "returns 1 when cluster_node_list or cluster_pod_name_list is empty"
        When run check_cluster_initialized "$KB_CLUSTER_POD_FQDN_LIST"
        The status should be failure
        The stderr should include "Error: Required environment variable cluster_pod_fqdn_list is not set."
      End
    End
  End

  Describe "build_redis_cluster_create_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      It "builds Redis cluster create command without password"
        primary_nodes="172.0.0.1:6379 172.0.0.2:6379"

        When call build_redis_cluster_create_command "$primary_nodes"
        The output should eq "redis-cli  --cluster create 172.0.0.1:6379 172.0.0.2:6379 --cluster-yes"
        The stderr should include "initialize cluster command: redis-cli  --cluster create 172.0.0.1:6379 172.0.0.2:6379 --cluster-yes"
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
        The output should eq "redis-cli  --cluster create 172.0.0.1:6379 172.0.0.2:6379 -a password --cluster-yes"
        The stderr should include "initialize cluster command: redis-cli  --cluster create 172.0.0.1:6379 172.0.0.2:6379 -a ******** --cluster-yes"
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
        The output should eq "redis-cli  --cluster add-node 172.0.0.3:6379 172.0.0.1:6379 --cluster-slave --cluster-master-id node1"
        The stderr should include "initialize cluster secondary add-node command: redis-cli  --cluster add-node 172.0.0.3:6379 172.0.0.1:6379 --cluster-slave --cluster-master-id node1"
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
        The output should eq "redis-cli  --cluster add-node 172.0.0.3:6379 172.0.0.1:6379 --cluster-slave --cluster-master-id node1 -a password"
        The stderr should include "initialize cluster secondary add-node command: redis-cli  --cluster add-node 172.0.0.3:6379 172.0.0.1:6379 --cluster-slave --cluster-master-id node1 -a ********"
      End
    End
  End

  Describe "build_scale_out_shard_primary_join_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      It "builds scale out shard primary join command without password"
        scale_out_shard_default_primary_endpoint_with_port="172.0.0.4:6379"
        exist_available_node="172.0.0.2:6379"

        When call build_scale_out_shard_primary_join_command "$scale_out_shard_default_primary_endpoint_with_port" "$exist_available_node"
        The output should eq "redis-cli  --cluster add-node 172.0.0.4:6379 172.0.0.2:6379"
        The stderr should include "scale out shard primary add-node command: redis-cli  --cluster add-node 172.0.0.4:6379 172.0.0.2:6379"
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
        The output should eq "redis-cli  --cluster add-node 172.0.0.4:6379 172.0.0.2:6379 -a password"
        The stderr should include "scale out shard primary add-node command: redis-cli  --cluster add-node 172.0.0.4:6379 172.0.0.2:6379 -a ********"
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
        The output should eq "redis-cli  --cluster reshard 172.0.0.1:6379 --cluster-from all --cluster-to node1 --cluster-slots 5461 --cluster-yes"
        The stderr should include "scale out shard reshard command: redis-cli  --cluster reshard 172.0.0.1:6379 --cluster-from all --cluster-to node1 --cluster-slots 5461 --cluster-yes"
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
        The output should eq "redis-cli  --cluster reshard 172.0.0.1:6379 --cluster-from all --cluster-to node1 --cluster-slots 5461 -a password --cluster-yes"
        The stderr should include "scale out shard reshard command: redis-cli  --cluster reshard 172.0.0.1:6379 --cluster-from all --cluster-to node1 --cluster-slots 5461 -a ******** --cluster-yes"
      End
    End
  End

  Describe "build_rebalance_to_zero_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      It "builds rebalance to zero command without password"
        node_with_port="172.0.0.1:6379"
        node_cluster_id="node1"

        When call build_rebalance_to_zero_command "$node_with_port" "$node_cluster_id"
        The output should eq "redis-cli  --cluster rebalance 172.0.0.1:6379 --cluster-weight node1=0 --cluster-yes "
        The stderr should include "set current component slot to 0 by rebalance command: redis-cli  --cluster rebalance 172.0.0.1:6379 --cluster-weight node1=0 --cluster-yes"
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
        The output should eq "redis-cli  --cluster rebalance 172.0.0.1:6379 --cluster-weight node1=0 --cluster-yes -a password"
        The stderr should include "set current component slot to 0 by rebalance command: redis-cli  --cluster rebalance 172.0.0.1:6379 --cluster-weight node1=0 --cluster-yes -a ********"
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
        The output should eq "redis-cli  --cluster del-node 172.0.0.2:6379 node1 -p 6379"
        The stderr should include "del node command: redis-cli  --cluster del-node 172.0.0.2:6379 node1 -p 6379"
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
        The output should eq "redis-cli  --cluster del-node 172.0.0.2:6379 node1 -p 6379 -a password"
        The stderr should include "del node command: redis-cli  --cluster del-node 172.0.0.2:6379 node1 -p 6379 -a ********"
      End
    End
  End

  Describe "build_acl_save_command()"
    Context "when REDIS_DEFAULT_PASSWORD is not set"
      setup() {
        export SERVICE_PORT="1000"
      }
      Before "setup"

      un_setup() {
        unset SERVICE_PORT
      }
      It "builds acl save command without password"
        When call build_acl_save_command $SERVICE_PORT
        The output should eq "redis-cli  -h localhost -p 1000 acl save"
        The stderr should include "acl save command: redis-cli  -h localhost -p 1000 acl save"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is set"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password"
        export SERVICE_PORT="1000"
      }
      Before "setup"

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
        unset SERVICE_PORT
      }
      After "un_setup"

      It "builds acl save command with password"
        When call build_acl_save_command $SERVICE_PORT
        The output should eq "redis-cli  -h localhost -p 1000 -a password acl save"
        The stderr should include "acl save command: redis-cli  -h localhost -p 1000 -a ******** acl save"
      End
    End
  End

  Describe "classify_current_node_replication_view()"
    It "classifies a slotless replica with the wrong upstream as repairable"
      cluster_nodes_info="self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 myself,slave stale-primary-id 0 1 1 connected
primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 0-16383"

      When call classify_current_node_replication_view "$cluster_nodes_info" "primary-id"
      The status should be success
      The output should equal "repairable"
      The stderr should be blank
    End
  End

  Describe "get_consistent_current_node_replication_state()"
    setup_replication_views() {
      service_port=6379
      retry_delay_second=0
      current_shard_node_ids="primary-id,self-id"
      expected_replication_view_calls=$(printf '%s\n' \
        "127.0.0.1:6379" \
        "primary:6379" \
        "127.0.0.1:6379" \
        "primary:6379")
      rm -f ./replication-view-calls ./replication-view-count
    }
    Before "setup_replication_views"

    cleanup_replication_views() {
      unset service_port retry_delay_second current_shard_node_ids expected_replication_view_calls
      rm -f ./replication-view-calls ./replication-view-count
    }
    After "cleanup_replication_views"

    Context "when both observers agree for two rounds on a correct replica"
      get_cluster_nodes_info() {
        printf '%s:%s\n' "$1" "$2" >> ./replication-view-calls
        if [ "$1" = "127.0.0.1" ]; then
          echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 myself,slave primary-id 0 1 1 connected"
        else
          echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 slave primary-id 0 1 1 connected"
        fi
        echo "primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 0-16383"
      }

      It "returns replica_ok after four successful reads"
        When call get_consistent_current_node_replication_state "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be success
        The output should equal "replica_ok"
        The stderr should be blank
        The contents of file "./replication-view-calls" should equal "$expected_replication_view_calls"
      End
    End

    Context "when both observers agree for two rounds on a slotless master"
      get_cluster_nodes_info() {
        printf '%s:%s\n' "$1" "$2" >> ./replication-view-calls
        if [ "$1" = "127.0.0.1" ]; then
          echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 myself,master - 0 1 1 connected"
        else
          echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 master - 0 1 1 connected"
        fi
        echo "primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 0-16383"
      }

      It "returns repairable"
        When call get_consistent_current_node_replication_state "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be success
        The output should equal "repairable"
        The stderr should be blank
        The contents of file "./replication-view-calls" should equal "$expected_replication_view_calls"
      End
    End

    Context "when the two observers disagree"
      get_cluster_nodes_info() {
        if [ "$1" = "127.0.0.1" ]; then
          echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 myself,master - 0 1 1 connected"
        else
          echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 slave stale-primary-id 0 1 1 connected"
        fi
        echo "primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 0-16383"
      }

      It "fails closed"
        When call get_consistent_current_node_replication_state "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be failure
        The stderr should include "Cluster replication views disagree"
      End
    End

    Context "when the second round changes node identity"
      setup_changing_views() { echo 0 > ./replication-view-count; }
      Before "setup_changing_views"

      get_cluster_nodes_info() {
        count=$(cat ./replication-view-count)
        count=$((count + 1))
        echo "$count" > ./replication-view-count
        self_id="self-id"
        if [ "$count" -gt 2 ]; then self_id="replacement-id"; fi
        flags="slave"
        if [ "$1" = "127.0.0.1" ]; then flags="myself,slave"; fi
        echo "$self_id 10.42.0.228:6379@16379,redis-shard-sxj-1 $flags primary-id 0 1 1 connected"
        echo "primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 0-16383"
      }

      It "fails closed across rounds"
        When call get_consistent_current_node_replication_state "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be failure
        The stderr should include "Cluster replication view changed before mutation"
      End
    End

    Context "when the second round changes the replica upstream"
      setup_changing_upstream() { echo 0 > ./replication-view-count; }
      Before "setup_changing_upstream"

      get_cluster_nodes_info() {
        count=$(cat ./replication-view-count)
        count=$((count + 1))
        echo "$count" > ./replication-view-count
        printf '%s:%s\n' "$1" "$2" >> ./replication-view-calls
        upstream_id="primary-id"
        if [ "$count" -gt 2 ]; then upstream_id="stale-primary-id"; fi
        flags="slave"
        if [ "$1" = "127.0.0.1" ]; then flags="myself,slave"; fi
        echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 $flags $upstream_id 0 1 1 connected"
        echo "primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 0-16383"
      }

      It "fails closed across rounds without mutating"
        When call get_consistent_current_node_replication_state "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be failure
        The stderr should include "Cluster replication view changed before mutation"
        The contents of file "./replication-view-calls" should equal "$expected_replication_view_calls"
      End
    End

    Context "when no unique slot owner exists"
      get_cluster_nodes_info() {
        flags="master"
        if [ "$1" = "127.0.0.1" ]; then flags="myself,master"; fi
        echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 $flags - 0 1 1 connected 0-5460"
        echo "primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 5461-16383"
      }

      It "fails closed"
        When call get_consistent_current_node_replication_state "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be failure
        The stderr should include "Expected exactly one slot-owning primary"
      End
    End
  End

  Describe "repair_current_node_replication()"
    setup_repair_command() {
      export REDIS_DEFAULT_PASSWORD="generated-secret-78431"
      export REDIS_CLI_TLS_CMD="--tls --insecure"
      service_port=6379
      rm -f ./repair-command-argv
    }
    Before "setup_repair_command"

    cleanup_repair_command() {
      unset REDIS_DEFAULT_PASSWORD REDIS_CLI_TLS_CMD service_port
      rm -f ./repair-command-argv
    }
    After "cleanup_repair_command"

    redis-cli() {
      printf '%s\n' "$*" >> ./repair-command-argv
      echo OK
    }

    It "executes exactly once without leaking the generated password"
      When call repair_current_node_replication "primary-id"
      The status should be success
      The stdout should not include "generated-secret-78431"
      The stderr should not include "generated-secret-78431"
      The stderr should include "-a ******** CLUSTER REPLICATE primary-id"
      The contents of file "./repair-command-argv" should equal "--tls --insecure -h 127.0.0.1 -p 6379 -a generated-secret-78431 CLUSTER REPLICATE primary-id"
    End
  End

  Describe "verify_current_node_replication() dual-view convergence"
    setup_replication_verification() {
      service_port=6379
      check_ready_times=2
      retry_delay_second=0
      current_shard_node_ids="primary-id,self-id"
      expected_replication_view_calls=$(printf '%s\n' \
        "127.0.0.1:6379" \
        "primary:6379" \
        "127.0.0.1:6379" \
        "primary:6379")
      rm -f ./replication-verify-calls ./replication-view-count ./unexpected-verify-repair
    }
    Before "setup_replication_verification"

    cleanup_replication_verification() {
      unset service_port check_ready_times retry_delay_second current_shard_node_ids expected_replication_view_calls
      rm -f ./replication-verify-calls ./replication-view-count ./unexpected-verify-repair
    }
    After "cleanup_replication_verification"

    repair_current_node_replication() { echo repair >> ./unexpected-verify-repair; }

    Context "when both observers agree for two rounds on the repaired replica"
      get_cluster_nodes_info() {
        printf '%s:%s\n' "$1" "$2" >> ./replication-verify-calls
        flags="slave"
        if [ "$1" = "127.0.0.1" ]; then flags="myself,slave"; fi
        echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 $flags primary-id 0 1 1 connected"
        echo "primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 0-16383"
      }

      It "accepts exactly local owner local owner and performs no mutation"
        When call verify_current_node_replication "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be success
        The stderr should be blank
        The contents of file "./replication-verify-calls" should equal "$expected_replication_view_calls"
        The path "./unexpected-verify-repair" should not be exist
      End
    End

    Context "when observers disagree after repair"
      get_cluster_nodes_info() {
        printf '%s:%s\n' "$1" "$2" >> ./replication-verify-calls
        if [ "$1" = "127.0.0.1" ]; then
          echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 myself,slave primary-id 0 1 1 connected"
        else
          echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 slave stale-primary-id 0 1 1 connected"
        fi
        echo "primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 0-16383"
      }

      It "classifies disagreement as failure with zero mutation"
        When call verify_current_node_replication "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be failure
        The stderr should include "Post-repair cluster replication views disagree"
        The path "./unexpected-verify-repair" should not be exist
      End
    End

    Context "when the second verification round changes upstream"
      setup_verify_drift() { echo 0 > ./replication-view-count; }
      Before "setup_verify_drift"

      get_cluster_nodes_info() {
        count=$(cat ./replication-view-count)
        count=$((count + 1))
        echo "$count" > ./replication-view-count
        printf '%s:%s\n' "$1" "$2" >> ./replication-verify-calls
        upstream_id="primary-id"
        if [ "$count" -gt 2 ]; then upstream_id="stale-primary-id"; fi
        flags="slave"
        if [ "$1" = "127.0.0.1" ]; then flags="myself,slave"; fi
        echo "self-id 10.42.0.228:6379@16379,redis-shard-sxj-1 $flags $upstream_id 0 1 1 connected"
        echo "primary-id 10.42.0.227:6379@16379,redis-shard-sxj-0 master - 0 1 1 connected 0-16383"
      }

      It "classifies drift as failure with zero mutation"
        When call verify_current_node_replication "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be failure
        The stderr should include "Post-repair cluster replication view changed"
        The contents of file "./replication-verify-calls" should equal "$expected_replication_view_calls"
        The path "./unexpected-verify-repair" should not be exist
      End
    End

    Context "when stable views never converge to a replica"
      get_consistent_current_node_replication_state() {
        printf '%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >> ./replication-verify-calls
        echo repairable
      }

      It "times out after the bounded attempts with zero mutation"
        When call verify_current_node_replication "primary" "6379" "primary-id" "$current_shard_node_ids"
        The status should be failure
        The stderr should include "Replication repair verification timeout"
        The contents of file "./replication-verify-calls" should equal "primary:6379:primary-id:primary-id,self-id
primary:6379:primary-id:primary-id,self-id"
        The path "./unexpected-verify-repair" should not be exist
      End
    End
  End

  Describe "ensure_current_node_replication() dual-view gate"
    It "rejects the removed one-argument API"
      When call ensure_current_node_replication "primary-id"
      The status should be failure
      The stderr should include "requires primary endpoint, port, ID, and shard node IDs"
    End

    Context "when pre-repair views are inconsistent"
      get_consistent_current_node_replication_state() {
        echo "Error: Cluster replication views disagree before mutation" >&2
        return 1
      }
      repair_current_node_replication() { echo called >> ./unexpected-repair; }

      cleanup_unexpected_repair() { rm -f ./unexpected-repair; }
      Before "cleanup_unexpected_repair"
      After "cleanup_unexpected_repair"

      It "performs zero mutations"
        When call ensure_current_node_replication "primary" "6379" "primary-id" "primary-id,self-id"
        The status should be failure
        The stderr should include "Cluster replication views disagree before mutation"
        The stderr should include "Failed to get consistent current node replication state"
        The path "./unexpected-repair" should not be exist
      End
    End

    Context "when the current node already replicates the expected primary"
      get_consistent_current_node_replication_state() { echo replica_ok; }
      repair_current_node_replication() { echo called >> ./unexpected-control-repair; }
      verify_current_node_replication() { echo called >> ./unexpected-control-verify; }

      cleanup_control_calls() { rm -f ./unexpected-control-repair ./unexpected-control-verify; }
      Before "cleanup_control_calls"
      After "cleanup_control_calls"

      It "performs zero mutations and zero post-repair verification calls"
        When call ensure_current_node_replication "primary" "6379" "primary-id" "primary-id,self-id"
        The status should be success
        The stdout should include "Current node already replicates expected primary primary-id"
        The stderr should be blank
        The path "./unexpected-control-repair" should not be exist
        The path "./unexpected-control-verify" should not be exist
      End
    End

    Context "when repair succeeds and dual-view verification converges"
      get_consistent_current_node_replication_state() { echo repairable; }
      repair_current_node_replication() { echo repair >> ./repair-count; }
      verify_current_node_replication() { echo verify >> ./verify-count; }

      setup_repair_counts() { rm -f ./repair-count ./verify-count; }
      Before "setup_repair_counts"
      After "setup_repair_counts"

      It "repairs and verifies exactly once"
        When call ensure_current_node_replication "primary" "6379" "primary-id" "primary-id,self-id"
        The status should be success
        The stderr should be blank
        The contents of file "./repair-count" should equal "repair"
        The contents of file "./verify-count" should equal "verify"
      End
    End
  End
End
