# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_cluster_manage_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Cluster Manage Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file
  Include ../redis-cluster-scripts/redis-cluster-common.sh
  Include ../redis-cluster-scripts/redis-cluster-manage.sh

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "init_other_components_and_pods_info()"
    It "initializes other components and pods info correctly"
      export KB_CLUSTER_COMPONENT_LIST="component1,component2,component3"
      export KB_CLUSTER_COMPONENT_DELETING_LIST="component2"
      export KB_CLUSTER_COMPONENT_UNDELETED_LIST="component1,component3"
      export KB_CLUSTER_POD_IP_LIST="10.0.0.1,10.0.0.2,10.0.0.3,10.0.0.4"
      export KB_CLUSTER_POD_NAME_LIST="component1-0,component2-0,component3-0,component3-1"
      export SERVICE_PORT="6379"

      When call init_other_components_and_pods_info "component1" "$KB_CLUSTER_POD_IP_LIST" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_LIST" "$KB_CLUSTER_COMPONENT_DELETING_LIST" "$KB_CLUSTER_COMPONENT_UNDELETED_LIST"
      The status should be success
      The output should include "other_components: component2 component3"
      The output should include "other_deleting_components: component2"
      The output should include "other_undeleted_components: component3"
      The output should include "other_undeleted_component_pod_ips: 10.0.0.3 10.0.0.4"
      The output should include "other_undeleted_component_pod_names: component3-0 component3-1"
      The output should include "other_undeleted_component_nodes: component3-0.component3-headless:6379 component3-1.component3-headless:6379"
    End
  End

  Describe "find_exist_available_node()"
    It "finds an available node from other undeleted components"
      check_slots_covered() { %text
        if [ "$1" = "node1:6379" ]; then
          return 0
        else
          return 1
        fi
      }
      get_cluster_nodes_info() { %text
        echo "node1 10.0.0.1:6379@16379 myself,master - 0 0 1 connected 0-5460"
      }
      export other_undeleted_component_nodes=("node1:6379" "node2:6379")
      export SERVICE_PORT="6379"
      When call find_exist_available_node
      The status should be success
      The output should eq "10.0.0.1:6379"
    End

    It "returns empty string when no available node found"
      check_slots_covered() { return 1; }
      get_cluster_nodes_info() { return 1; }
      export other_undeleted_component_nodes=("node1:6379" "node2:6379")
      export SERVICE_PORT="6379"
      When call find_exist_available_node
      The status should be success
      The output should be blank
    End
  End

  Describe "parse_host_ip_from_built_in_envs()"
    It "parses host IP from built-in environment variables"
      export KB_CLUSTER_POD_NAME_LIST="pod1,pod2,pod3"
      export KB_CLUSTER_POD_HOST_IP_LIST="10.0.0.1,10.0.0.2,10.0.0.3"
      When call parse_host_ip_from_built_in_envs "pod2" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_POD_HOST_IP_LIST"
      The status should be success
      The output should eq "10.0.0.2"
    End

    It "exits with error when pod name not found"
      export KB_CLUSTER_POD_NAME_LIST="pod1,pod2,pod3"
      export KB_CLUSTER_POD_HOST_IP_LIST="10.0.0.1,10.0.0.2,10.0.0.3"
      When call parse_host_ip_from_built_in_envs "pod4" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_POD_HOST_IP_LIST"
      The status should be failure
      The stderr should include "the given pod name pod4 not found"
    End
  End

  Describe "extract_pod_name_prefix()"
    It "extracts the prefix from the pod name"
      When call extract_pod_name_prefix "component1-0"
      The status should be success
      The output should eq "component1"
    End

    It "extracts the prefix from the pod name"
      When call extract_pod_name_prefix "component1-0-1"
      The status should be success
      The output should eq "component1-0"
    End
  End

  Describe "get_current_comp_nodes_for_scale_in()"
    Context "when cluster nodes info contains only one line"
      get_cluster_nodes_info() {
        cluster_nodes_info="4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287"
        echo "$cluster_nodes_info"
      }
      It "returns early when cluster nodes info contains only one line"
        When call get_current_comp_nodes_for_scale_in "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc" "6379"
        The status should be success
        The stdout should include "Cluster nodes info contains only one line, returning..."
      End
    End

    Context "when using advertised ports"
      get_cluster_nodes_info() {
        cluster_nodes_info="4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:31000@32000,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287"$'\n'"7381c6dca033cd1b321922508553fab869a29e 10.42.0.228:31001@32001,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc slave 4958e6dca033cd1b321922508553fab869a29d 0 1711958289570 4 connected"
        echo "$cluster_nodes_info"
      }

      setup() {
        export CURRENT_SHARD_ADVERTISED_PORT="redis-shard-sxj-0:31000,redis-shard-sxj-1:31001"
        export current_comp_primary_node=()
        export current_comp_other_nodes=()
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_ADVERTISED_PORT
        unset cluster_nodes_info
      }
      After "un_setup"

      It "parses current component nodes correctly when using advertised ports"
        When call get_current_comp_nodes_for_scale_in "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc" "6379"
        The status should be success
        The variable current_comp_primary_node should equal "10.42.0.227:31000"
        The variable current_comp_other_nodes should equal "10.42.0.228:31001"
        The stdout should include "current_comp_primary_node: 10.42.0.227:31000"
      End
    End

    Context "when not using advertised ports"
      get_cluster_nodes_info() {
        cluster_nodes_info="4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287"$'\n'"7381c6dca033cd1b321922508553fab869a29e 10.42.0.228:6379@16379,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc slave 4958e6dca033cd1b321922508553fab869a29d 0 1711958289570 4 connected"
        echo "$cluster_nodes_info"
      }
      setup() {
        unset CURRENT_SHARD_ADVERTISED_PORT
        export KB_CLUSTER_COMP_NAME="redis-shard-sxj"
        export SERVICE_PORT="6379"
        export current_comp_primary_node=()
        export current_comp_other_nodes=()
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMP_NAME
        unset SERVICE_PORT
        unset cluster_nodes_info
      }
      After "un_setup"

      It "parses current component nodes correctly when not using advertised ports"
        When call get_current_comp_nodes_for_scale_in "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc" "6379"
        The status should be success
        The variable current_comp_primary_node should equal "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc:6379"
        The variable current_comp_other_nodes should equal "redis-shard-sxj-1.redis-shard-sxj-headless.default.svc:6379"
        The stdout should include "current_comp_primary_node: redis-shard-sxj-0.redis-shard-sxj-headless.default.svc:6379"
      End
    End

    Context "when failed to get cluster nodes info"
      get_cluster_nodes_info() {
        return 1
      }

      It "returns error when failed to get cluster nodes info"
        When call get_current_comp_nodes_for_scale_in "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc" "6379"
        The status should be failure
        The stderr should include "Failed to get cluster nodes info in get_current_comp_nodes_for_scale_in"
      End
    End
  End

  Describe "init_current_comp_default_nodes_for_scale_out()"
    Context "when using advertised ports"
      min_lexicographical_order_pod() {
        echo "redis-shard-sxj-0"
      }

      parse_host_ip_from_built_in_envs() {
        case "$1" in
          "redis-shard-sxj-0")
            echo "10.42.0.1"
            ;;
          "redis-shard-sxj-1")
            echo "10.42.0.2"
            ;;
        esac
      }

      setup() {
        declare -gA scale_out_shard_default_primary_node
        declare -gA scale_out_shard_default_other_nodes
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-sxj-0,redis-shard-sxj-1"
        export CURRENT_SHARD_ADVERTISED_PORT="redis-shard-sxj-0:31000,redis-shard-sxj-1:31001"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset CURRENT_SHARD_ADVERTISED_PORT
      }
      After "un_setup"

      It "initializes default nodes correctly when using advertised ports"
        When call init_current_comp_default_nodes_for_scale_out
        The status should be success
        The variable scale_out_shard_default_primary_node['redis-shard-sxj-0'] should equal "10.42.0.1:31000"
        The variable scale_out_shard_default_other_nodes['redis-shard-sxj-1'] should equal "10.42.0.2:31001"
      End
    End

    Context "when not using advertised ports"
      min_lexicographical_order_pod() {
        echo "redis-shard-sxj-0"
      }

      get_target_pod_fqdn_from_pod_fqdn_vars() {
        case "$1" in
          "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local")
            case "$2" in
              "redis-shard-sxj-0")
                echo "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local"
                ;;
              "redis-shard-sxj-1")
                echo "redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local"
                ;;
            esac
            ;;
        esac
      }

      setup() {
        declare -gA scale_out_shard_default_primary_node
        declare -gA scale_out_shard_default_other_nodes
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-sxj-0,redis-shard-sxj-1"
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "initializes default nodes correctly when not using advertised ports"
        When call init_current_comp_default_nodes_for_scale_out
        The status should be success
        The variable scale_out_shard_default_primary_node['redis-shard-sxj-0'] should equal "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local:6379"
        The variable scale_out_shard_default_other_nodes['redis-shard-sxj-1'] should equal "redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local:6379"
      End
    End

    Context "when failed to get ordinal of min lexicographical pod"
      min_lexicographical_order_pod() {
        echo "redis-shard-sxj-0"
      }

      extract_obj_ordinal() {
        return 1
      }

      setup() {
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-sxj-0,redis-shard-sxj-1"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
      }
      After "un_setup"

      It "exits with error when failed to get ordinal of min lexicographical pod"
        When run init_current_comp_default_nodes_for_scale_out
        The status should be failure
        The stderr should include "Failed to get the ordinal of the min lexicographical pod redis-shard-sxj-0 in init_current_comp_default_nodes_for_scale_out"
      End
    End

    Context "when failed to get host ip of pod"
      min_lexicographical_order_pod() {
        echo "redis-shard-sxj-0"
      }

      extract_obj_ordinal() {
        case "$1" in
          "redis-shard-sxj-0")
            echo "0"
            ;;
          "redis-shard-sxj-1")
            echo "1"
            ;;
        esac
      }

      parse_host_ip_from_built_in_envs() {
        return 1
      }

      setup() {
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-sxj-0,redis-shard-sxj-1"
        export CURRENT_SHARD_ADVERTISED_PORT="redis-shard-sxj-0:31000,redis-shard-sxj-1:31001"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset CURRENT_SHARD_ADVERTISED_PORT
      }
      After "un_setup"

      It "exits with error when failed to get host ip of pod"
        When run init_current_comp_default_nodes_for_scale_out
        The status should be failure
        The stderr should include "Failed to get the host ip of the pod redis-shard-sxj-0"
      End
    End

    Context "when advertised port not found for pod"
      min_lexicographical_order_pod() {
        echo "redis-shard-sxj-0"
      }

      extract_obj_ordinal() {
        case "$1" in
          "redis-shard-sxj-0")
            echo "0"
            ;;
          "redis-shard-sxj-1")
            echo "1"
            ;;
        esac
      }

      parse_host_ip_from_built_in_envs() {
        case "$1" in
          "redis-shard-sxj-0")
            echo "10.42.0.1"
            ;;
          "redis-shard-sxj-1")
            echo "10.42.0.2"
            ;;
        esac
      }

      setup() {
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-sxj-0,redis-shard-sxj-1"
        export CURRENT_SHARD_ADVERTISED_PORT="redis-shard-sxj-0:31000"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset CURRENT_SHARD_ADVERTISED_PORT
      }
      After "un_setup"

      It "exits with error when advertised port not found for pod"
        When run init_current_comp_default_nodes_for_scale_out
        The status should be failure
        The stderr should include "Advertised port not found for pod redis-shard-sxj-1"
      End
    End

    Context "when failed to get pod fqdn"
      min_lexicographical_order_pod() {
        echo "redis-shard-sxj-0"
      }

      extract_obj_ordinal() {
        case "$1" in
          "redis-shard-sxj-0")
            echo "0"
            ;;
          "redis-shard-sxj-1")
            echo "1"
            ;;
        esac
      }

      get_target_pod_fqdn_from_pod_fqdn_vars() {
        return 1
      }

      setup() {
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-sxj-0,redis-shard-sxj-1"
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "exits with error when failed to get pod fqdn"
        When run init_current_comp_default_nodes_for_scale_out
        The status should be failure
        The stderr should include "Error: Failed to get current pod: redis-shard-sxj-0 fqdn from current shard pod fqdn list: redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local. Exiting."
      End
    End
  End

  Describe "gen_initialize_redis_cluster_node()"
    Context "when is_primary is true and using advertised ports"
      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
        export ALL_SHARDS_ADVERTISED_PORT="shard-98x@redis-shard-98x-redis-advertised-0:32024,redis-shard-98x-redis-advertised-1:31318.shard-7hy@redis-shard-7hy-redis-advertised-0:32025,redis-shard-7hy-redis-advertised-1:31319.shard-jwl@redis-shard-jwl-redis-advertised-0:32026,redis-shard-jwl-redis-advertised-1:31320"
        declare -gA initialize_redis_cluster_primary_nodes
        declare -gA initialize_redis_cluster_secondary_nodes
        declare -gA initialize_pod_name_to_advertise_host_port_map
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset ALL_SHARDS_ADVERTISED_PORT
      }
      After "un_setup"

      It "initializes primary nodes correctly when using advertised ports"
        When call gen_initialize_redis_cluster_node "true"
        The status should be success
        The variable initialize_redis_cluster_primary_nodes["redis-shard-98x-0"] should equal "10.42.0.1:32024"
        The variable initialize_redis_cluster_primary_nodes["redis-shard-7hy-0"] should equal "10.42.0.3:32025"
        The variable initialize_redis_cluster_primary_nodes["redis-shard-jwl-0"] should equal "10.42.0.5:32026"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-98x-0"] should equal "10.42.0.1:32024"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-7hy-0"] should equal "10.42.0.3:32025"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-jwl-0"] should equal "10.42.0.5:32026"
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-98x-1"] should be blank
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-7hy-1"] should be blank
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-jwl-1"] should be blank
      End
    End

    Context "when is_primary is false and using advertised ports"
      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
        export ALL_SHARDS_ADVERTISED_PORT="shard-98x@redis-shard-98x-redis-advertised-0:32024,redis-shard-98x-redis-advertised-1:31318.shard-7hy@redis-shard-7hy-redis-advertised-0:32025,redis-shard-7hy-redis-advertised-1:31319.shard-jwl@redis-shard-jwl-redis-advertised-0:32026,redis-shard-jwl-redis-advertised-1:31320"
        declare -gA initialize_redis_cluster_primary_nodes
        declare -gA initialize_redis_cluster_secondary_nodes
        declare -gA initialize_pod_name_to_advertise_host_port_map
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset ALL_SHARDS_ADVERTISED_PORT
      }
      After "un_setup"

      It "initializes secondary nodes correctly when using advertised ports"
        When call gen_initialize_redis_cluster_node "false"
        The status should be success
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-98x-1"] should equal "10.42.0.2:31318"
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-7hy-1"] should equal "10.42.0.4:31319"
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-jwl-1"] should equal "10.42.0.6:31320"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-98x-1"] should equal "10.42.0.2:31318"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-7hy-1"] should equal "10.42.0.4:31319"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-jwl-1"] should equal "10.42.0.6:31320"
        The variable initialize_redis_cluster_primary_nodes['redis-shard-98x-0'] should be blank
        The variable initialize_redis_cluster_primary_nodes['redis-shard-7hy-0'] should be blank
        The variable initialize_redis_cluster_primary_nodes['redis-shard-jwl-0'] should be blank
      End
    End

    Context "when is_primary is true and not using advertised ports"
      get_all_shards_pod_fqdns() {
        echo "redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local,redis-shard-7hy-0.namespace.svc.cluster.local,redis-shard-7hy-1.namespace.svc.cluster.local,redis-shard-jwl-0.namespace.svc.cluster.local,redis-shard-jwl-1.namespace.svc.cluster.local"
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export SERVICE_PORT="6379"
        declare -gA initialize_redis_cluster_primary_nodes
        declare -gA initialize_redis_cluster_secondary_nodes
        declare -gA initialize_pod_name_to_advertise_host_port_map
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "initializes primary nodes correctly when not using advertised ports"
        When call gen_initialize_redis_cluster_node "true"
        The status should be success
        The variable initialize_redis_cluster_primary_nodes["redis-shard-98x-0"] should equal "redis-shard-98x-0.namespace.svc.cluster.local:6379"
        The variable initialize_redis_cluster_primary_nodes["redis-shard-7hy-0"] should equal "redis-shard-7hy-0.namespace.svc.cluster.local:6379"
        The variable initialize_redis_cluster_primary_nodes["redis-shard-jwl-0"] should equal "redis-shard-jwl-0.namespace.svc.cluster.local:6379"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-98x-0"] should equal "redis-shard-98x-0.namespace.svc.cluster.local:6379"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-7hy-0"] should equal "redis-shard-7hy-0.namespace.svc.cluster.local:6379"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-jwl-0"] should equal "redis-shard-jwl-0.namespace.svc.cluster.local:6379"
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-98x-1"] should be blank
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-7hy-1"] should be blank
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-jwl-1"] should be blank
      End
    End

    Context "when is_primary is false and not using advertised ports"
      get_all_shards_pod_fqdns() {
        echo "redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local,redis-shard-7hy-0.namespace.svc.cluster.local,redis-shard-7hy-1.namespace.svc.cluster.local,redis-shard-jwl-0.namespace.svc.cluster.local,redis-shard-jwl-1.namespace.svc.cluster.local"
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export SERVICE_PORT="6379"
        declare -gA initialize_redis_cluster_primary_nodes
        declare -gA initialize_redis_cluster_secondary_nodes
        declare -gA initialize_pod_name_to_advertise_host_port_map
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "initializes secondary nodes correctly when not using advertised ports"
        When call gen_initialize_redis_cluster_node "false"
        The status should be success
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-98x-1"] should equal "redis-shard-98x-1.namespace.svc.cluster.local:6379"
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-7hy-1"] should equal "redis-shard-7hy-1.namespace.svc.cluster.local:6379"
        The variable initialize_redis_cluster_secondary_nodes["redis-shard-jwl-1"] should equal "redis-shard-jwl-1.namespace.svc.cluster.local:6379"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-98x-1"] should equal "redis-shard-98x-1.namespace.svc.cluster.local:6379"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-7hy-1"] should equal "redis-shard-7hy-1.namespace.svc.cluster.local:6379"
        The variable initialize_pod_name_to_advertise_host_port_map["redis-shard-jwl-1"] should equal "redis-shard-jwl-1.namespace.svc.cluster.local:6379"
        The variable initialize_redis_cluster_primary_nodes['redis-shard-98x-0'] should be blank
        The variable initialize_redis_cluster_primary_nodes['redis-shard-7hy-0'] should be blank
        The variable initialize_redis_cluster_primary_nodes['redis-shard-jwl-0'] should be blank
      End
    End

    Context "when failed to get ordinal of min lexicographical pod"
      extract_obj_ordinal() {
        return 1
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
      }
      After "un_setup"

      It "returns error when failed to get ordinal of min lexicographical pod"
        When call gen_initialize_redis_cluster_node "true"
        The status should be failure
        The error should include "Failed to get the ordinal of the min lexicographical pod redis-shard-7hy-0 in gen_initialize_redis_cluster_node"
      End
    End

    Context "when failed to get host ip of pod"
      parse_host_ip_from_built_in_envs() {
        echo ""
        return 1
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
        export ALL_SHARDS_ADVERTISED_PORT="shard-98x@redis-shard-98x-redis-advertised-0:32024,redis-shar
d-98x-redis-advertised-1:31318.shard-7hy@redis-shard-7hy-redis-advertised-0:32025,redis-shard-7hy-redis-advertised-1:31319.shard-jwl@redis-shard-jwl-redis-advertised-0:32026,redis-shard-jwl-redis-advertised-1:31320"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset ALL_SHARDS_ADVERTISED_PORT
      }
      After "un_setup"

      It "exits with error when failed to get host ip of pod"
        When run gen_initialize_redis_cluster_node "true"
        The status should be failure
        The stderr should include "Failed to get the host ip of the pod redis-shard-98x-0"
      End
    End

    Context "when failed to get all shard pod fqdns"
      get_all_shards_pod_fqdns() {
        echo ""
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns error when failed to get all shard pod fqdns"
        When call gen_initialize_redis_cluster_node "true"
        The status should be failure
        The error should include "Failed to get all shard pod fqdns from vars env ALL_SHARDS_POD_FQDN_LIST"
      End
    End

    Context "when failed to get target pod fqdn"
      get_all_shards_pod_fqdns() {
        echo "redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local,redis-shard-7hy-0.namespace.svc.cluster.local,redis-shard-7hy-1.namespace.svc.cluster.local,redis-shard-jwl-0.namespace.svc.cluster.local,redis-shard-jwl-1.namespace.svc.cluster.local"
      }

      get_target_pod_fqdn_from_pod_fqdn_vars() {
        echo ""
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns error when failed to get target pod fqdn"
        When call gen_initialize_redis_cluster_node "true"
        The status should be failure
        The stderr should include "Error: Failed to get current pod: redis-shard-98x-0 fqdn from all shard pod fqdn list"
      End
    End
  End

  Describe "gen_initialize_redis_cluster_primary_node()"
    It "calls gen_initialize_redis_cluster_node with 'true'"
      gen_initialize_redis_cluster_node() {
        [ "$1" = "true" ]
      }
      When call gen_initialize_redis_cluster_primary_node
      The status should be success
    End
  End

  Describe "gen_initialize_redis_cluster_secondary_nodes()"
    It "calls gen_initialize_redis_cluster_node with 'false'"
      gen_initialize_redis_cluster_node() {
        [ "$1" = "false" ]
      }
      When call gen_initialize_redis_cluster_secondary_nodes
      The status should be success
    End
  End

  Describe "initialize_redis_cluster()"
    Context "when KB_CLUSTER_POD_NAME_LIST or KB_CLUSTER_POD_HOST_IP_LIST is empty"
      setup() {
        export KB_CLUSTER_POD_NAME_LIST=""
        export KB_CLUSTER_POD_HOST_IP_LIST=""
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
      }
      After "un_setup"

      It "exits with error when KB_CLUSTER_POD_NAME_LIST or KB_CLUSTER_POD_HOST_IP_LIST is empty"
        When run initialize_redis_cluster
        The status should be failure
        The stderr should include "Error: Required environment variable KB_CLUSTER_POD_NAME_LIST and KB_CLUSTER_POD_HOST_IP_LIST are not set when initializing redis cluster"
      End
    End

    Context "when failed to get primary nodes or primary nodes count is less than 3"
      gen_initialize_redis_cluster_primary_node() {
        declare -gA initialize_redis_cluster_primary_nodes
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
      }
      After "un_setup"

      It "exits with error when failed to get primary nodes or primary nodes count is less than 3"
        When run initialize_redis_cluster
        The status should be failure
        The stderr should include "Failed to get primary nodes or the primary nodes count is less than 3"
      End
    End

    Context "when failed to create redis cluster when initializing"
      gen_initialize_redis_cluster_primary_node() {
        declare -gA initialize_redis_cluster_primary_nodes
        initialize_redis_cluster_primary_nodes["redis-shard-98x-0"]="10.42.0.1:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-7hy-0"]="10.42.0.3:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-jwl-0"]="10.42.0.5:6379"
      }

      create_redis_cluster() {
        return 1
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
      }
      After "un_setup"

      It "exits with error when failed to create redis cluster when initializing"
        When run initialize_redis_cluster
        The status should be failure
        The stderr should include "Failed to create redis cluster when initializing"
      End
    End

    Context "when failed to check slots covered"
      gen_initialize_redis_cluster_primary_node() {
        declare -gA initialize_redis_cluster_primary_nodes
        initialize_redis_cluster_primary_nodes["redis-shard-98x-0"]="10.42.0.1:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-7hy-0"]="10.42.0.3:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-jwl-0"]="10.42.0.5:6379"
      }

      create_redis_cluster() {
        return 0
      }

      check_slots_covered() {
        return 1
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "exits with error when failed to check slots covered"
        When run initialize_redis_cluster
        The status should be failure
        The stderr should include "Failed to create redis cluster when checking slots covered"
        The stdout should include "Redis cluster initialized primary nodes successfully, cluster nodes: 10.42.0.1:6379 10.42.0.5:6379 10.42.0.3:6379"
      End
    End

    Context "when no secondary nodes to initialize"
      gen_initialize_redis_cluster_primary_node() {
        declare -gA initialize_redis_cluster_primary_nodes
        initialize_redis_cluster_primary_nodes["redis-shard-98x-0"]="10.42.0.1:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-7hy-0"]="10.42.0.3:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-jwl-0"]="10.42.0.5:6379"
      }

      create_redis_cluster() {
        return 0
      }

      check_slots_covered() {
        return 0
      }

      gen_initialize_redis_cluster_secondary_nodes() {
        declare -gA initialize_redis_cluster_secondary_nodes
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns when no secondary nodes to initialize"
        When run initialize_redis_cluster
        The status should be success
        The output should include "No secondary nodes to initialize"
      End
    End

    Context "when failed to find the mapping primary node for secondary node"
      gen_initialize_redis_cluster_primary_node() {
        declare -gA initialize_redis_cluster_primary_nodes
        initialize_redis_cluster_primary_nodes["redis-shard-98x-0"]="10.42.0.1:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-7hy-0"]="10.42.0.3:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-jwl-0"]="10.42.0.5:6379"
      }

      create_redis_cluster() {
        return 0
      }

      check_slots_covered() {
        return 0
      }

      gen_initialize_redis_cluster_secondary_nodes() {
        declare -gA initialize_redis_cluster_secondary_nodes
        initialize_redis_cluster_secondary_nodes["redis-shard-98x-1"]="10.42.0.2:6379"
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      declare -gA initialize_pod_name_to_advertise_host_port_map
      initialize_pod_name_to_advertise_host_port_map=()

      It "exits with error when failed to find the mapping primary node for secondary node"
        When run initialize_redis_cluster
        The status should be failure
        The stderr should include "Failed to find the mapping primary node for secondary node: redis-shard-98x-1"
        The stdout should include "Redis cluster initialized primary nodes successfully, cluster nodes: 10.42.0.1:6379 10.42.0.5:6379 10.42.0.3:6379"
        The stdout should include "Redis cluster check primary nodes slots covered successfully"
      End
    End

    Context "when failed to get the cluster id from cluster nodes of the mapping primary node"
      gen_initialize_redis_cluster_primary_node() {
        declare -gA initialize_redis_cluster_primary_nodes
        initialize_redis_cluster_primary_nodes["redis-shard-98x-0"]="10.42.0.1:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-7hy-0"]="10.42.0.3:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-jwl-0"]="10.42.0.5:6379"
      }

      create_redis_cluster() {
        return 0
      }

      check_slots_covered() {
        return 0
      }

      gen_initialize_redis_cluster_secondary_nodes() {
        declare -gA initialize_redis_cluster_secondary_nodes
        initialize_redis_cluster_secondary_nodes["redis-shard-98x-1"]="10.42.0.2:6379"
      }

      declare -gA initialize_pod_name_to_advertise_host_port_map
      initialize_pod_name_to_advertise_host_port_map["redis-shard-98x-0"]="10.42.0.1:6379"

      get_cluster_id() {
        echo ""
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "exits with error when failed to get the cluster id from cluster nodes of the mapping primary node"
        When run initialize_redis_cluster
        The status should be failure
        The stderr should include "Failed to get the cluster id from cluster nodes of the mapping primary node: 10.42.0.1:6379"
        The stdout should include "mapping_primary_fqdn: 10.42.0.1, mapping_primary_endpoint_with_port: 10.42.0.1:6379, mapping_primary_cluster_id: "
      End
    End

    Context "when failed to initialize the secondary node"
      gen_initialize_redis_cluster_primary_node() {
        declare -gA initialize_redis_cluster_primary_nodes
        initialize_redis_cluster_primary_nodes["redis-shard-98x-0"]="10.42.0.1:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-7hy-0"]="10.42.0.3:6379"
        initialize_redis_cluster_primary_nodes["redis-shard-jwl-0"]="10.42.0.5:6379"
      }

      create_redis_cluster() {
        return 0
      }

      check_slots_covered() {
        return 0
      }

      gen_initialize_redis_cluster_secondary_nodes() {
        declare -gA initialize_redis_cluster_secondary_nodes
        initialize_redis_cluster_secondary_nodes["redis-shard-98x-1"]="10.42.0.2:6379"
      }

      declare -gA initialize_pod_name_to_advertise_host_port_map
      initialize_pod_name_to_advertise_host_port_map["redis-shard-98x-0"]="10.42.0.1:6379"

      get_cluster_id() {
        echo "cluster_id_123"
      }

      secondary_replicated_to_primary() {
        return 1
      }

      setup() {
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "exits with error when failed to initialize the secondary node"
        When run initialize_redis_cluster
        The status should be failure
        The stderr should include "Failed to initialize the secondary node redis-shard-98x-1, secondary replicated output:"
        The stdout should include "mapping_primary_fqdn: 10.42.0.1, mapping_primary_endpoint_with_port: 10.42.0.1:6379, mapping_primary_cluster_id: cluster_id_123"
      End
    End
  End

  Describe "scale_out_redis_cluster_shard()"
    Context "when required environment variables are not set"
      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME=""
        export KB_CLUSTER_POD_NAME_LIST=""
        export KB_CLUSTER_POD_HOST_IP_LIST=""
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST=""
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST=""
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
      }
      After "un_setup"

      It "returns error when required environment variables are not set"
        When call scale_out_redis_cluster_shard
        The status should be failure
        The error should include "Error: Required environment variable CURRENT_SHARD_COMPONENT_SHORT_NAME, KB_CLUSTER_POD_NAME_LIST, KB_CLUSTER_POD_HOST_IP_LIST, KB_CLUSTER_COMPONENT_POD_NAME_LIST and KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are not set when scale out redis cluster shard"
      End
    End

    Context "when failed to initialize the default primary and secondary nodes for scale out"
      init_current_comp_default_nodes_for_scale_out() {
        return 1
      }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
      }
      After "un_setup"

      It "returns error when failed to initialize the default primary and secondary nodes for scale out"
        When call scale_out_redis_cluster_shard
        The status should be failure
        The error should include "Failed to initialize the default primary and secondary nodes for scale out"
        The stdout should include "skip the pod redis-shard-98x-1 as it belongs the component shard-98x"
      End
    End

    Context "when failed to generate primary nodes when scaling out"
      init_current_comp_default_nodes_for_scale_out() {
        declare -gA scale_out_shard_default_primary_node
        scale_out_shard_default_primary_node=()
      }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
      }
      After "un_setup"

      It "returns error when failed to generate primary nodes when scaling out"
        When call scale_out_redis_cluster_shard
        The status should be failure
        The error should include "Failed to generate primary nodes when scaling out"
        The stdout should include "Redis cluster scale out shard default primary and secondary nodes successfully"
      End
    End

    Context "when the current component shard is already scaled out"
      init_current_comp_default_nodes_for_scale_out() {
        declare -gA scale_out_shard_default_primary_node
        scale_out_shard_default_primary_node["redis-shard-98x-0"]="10.42.0.1:6379"
      }

      get_cluster_id() {
        echo "cluster_id_123"
      }

      check_slots_covered() {
        return 0
      }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns success when the current component shard is already scaled out"
        When call scale_out_redis_cluster_shard
        The status should be success
        The output should include "The current component shard is already scaled out, no need to scale out again."
      End
    End

    Context "when no exist available node found or cluster status is not ok"
      init_current_comp_default_nodes_for_scale_out() {
        declare -gA scale_out_shard_default_primary_node
        scale_out_shard_default_primary_node["redis-shard-98x-0"]="10.42.0.1:6379"
      }

      get_cluster_id() {
        echo "cluster_id_123"
      }

      check_slots_covered() {
        return 1
      }

      find_exist_available_node() {
        echo ""
      }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns error when no exist available node found or cluster status is not ok"
        When call scale_out_redis_cluster_shard
        The status should be failure
        The error should include "No exist available node found or cluster status is not ok"
        The stdout should include "Redis cluster scale out shard default primary and secondary nodes successfully"
      End
    End

    Context "when failed to scale out shard primary node"
      init_current_comp_default_nodes_for_scale_out() {
        declare -gA scale_out_shard_default_primary_node
        scale_out_shard_default_primary_node["redis-shard-98x-0"]="10.42.0.1:6379"
      }

      get_cluster_id() {
        echo "cluster_id_123"
      }

      check_slots_covered() {
        return 1
      }

      find_exist_available_node() {
        echo "10.42.0.2:6379"
      }

      scale_out_shard_primary_join_cluster() {
        return 1
      }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns error when failed to scale out shard primary node"
        When call scale_out_redis_cluster_shard
        The status should be failure
        The error should include "Failed to scale out shard primary node redis-shard-98x-0"
        The stdout should include "Redis cluster scale out shard default primary and secondary nodes successfully"
      End
    End

    Context "when failed to scale out shard secondary node"
      init_current_comp_default_nodes_for_scale_out() {
        declare -gA scale_out_shard_default_primary_node
        scale_out_shard_default_primary_node["redis-shard-98x-0"]="10.42.0.1:6379"
        declare -gA scale_out_shard_default_other_nodes
        scale_out_shard_default_other_nodes["redis-shard-98x-1"]="10.42.0.2:6379"
      }

      get_cluster_id() {
        echo "cluster_id_123"
      }

      check_slots_covered() {
        return 1
      }

      find_exist_available_node() {
        echo "10.42.0.3:6379"
      }

      scale_out_shard_primary_join_cluster() {
        return 0
      }

      secondary_replicated_to_primary() {
        return 1
      }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns error when failed to scale out shard secondary node"
        When call scale_out_redis_cluster_shard
        The status should be failure
        The error should include "Failed to scale out shard secondary node redis-shard-98x-1"
        The stdout should include "Redis cluster scale out shard primary node redis-shard-98x-0 successfully"
        The stdout should include "primary_node_with_port: 10.42.0.1:6379, primary_node_fqdn: 10.42.0.1, mapping_primary_cluster_id: cluster_id_123"
      End
    End

    Context "when failed to scale out shard reshard"
      init_current_comp_default_nodes_for_scale_out() {
        declare -gA scale_out_shard_default_primary_node
        scale_out_shard_default_primary_node["redis-shard-98x-0"]="10.42.0.1:6379"
        declare -gA scale_out_shard_default_other_nodes
        scale_out_shard_default_other_nodes["redis-shard-98x-1"]="10.42.0.2:6379"
      }

      get_cluster_id() {
        echo "cluster_id_123"
      }

      check_slots_covered() {
        return 1
      }

      find_exist_available_node() {
        echo "10.42.0.3:6379"
      }

      scale_out_shard_primary_join_cluster() {
        return 0
      }

      secondary_replicated_to_primary() {
        return 0
      }

      scale_out_shard_reshard() {
        return 1
      }

      setup() {
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="redis-shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x,redis-shard-7hy"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x,redis-shard-7hy"
        export KB_CLUSTER_COMP_NAME="redis-shard-98x"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
        unset KB_CLUSTER_COMP_NAME
        unset SERVICE_PORT
      }
      After "un_setup"

      It "returns error when failed to scale out shard reshard"
        When call scale_out_redis_cluster_shard
        The status should be failure
        The error should include "Failed to scale out shard reshard"
        The stdout should include "Redis cluster scale out shard secondary node redis-shard-98x-1 successfully"
      End
    End
  End

  Describe "scale_in_redis_cluster_shard()"
    Context "when KB_CLUSTER_COMPONENT_IS_SCALING_IN env is not set"
      setup() {
        export KB_CLUSTER_COMPONENT_IS_SCALING_IN=""
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_IS_SCALING_IN
      }
      After "un_setup"

      It "returns 0 when KB_CLUSTER_COMPONENT_IS_SCALING_IN env is not set"
        When call scale_in_redis_cluster_shard
        The status should be success
        The output should include "The KB_CLUSTER_COMPONENT_IS_SCALING_IN env is not set, skip scaling in"
      End
    End

    Context "when required environment variables are not set"
      setup() {
        export KB_CLUSTER_COMPONENT_IS_SCALING_IN="true"
        export CURRENT_SHARD_COMPONENT_SHORT_NAME=""
        export KB_CLUSTER_POD_NAME_LIST=""
        export KB_CLUSTER_POD_HOST_IP_LIST=""
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST=""
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST=""
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_IS_SCALING_IN
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
      }
      After "un_setup"

      It "returns 1 when required environment variables are not set"
        When call scale_in_redis_cluster_shard
        The status should be failure
        The error should include "Error: Required environment variable CURRENT_SHARD_COMPONENT_SHORT_NAME, KB_CLUSTER_POD_NAME_LIST, KB_CLUSTER_POD_HOST_IP_LIST, KB_CLUSTER_COMPONENT_POD_NAME_LIST and KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are not set when scale in redis cluster shard"
      End
    End

    Context "when the number of shards in the cluster is less than 3 after scaling down"
      find_exist_available_node() {
        echo "redis-shard-98x-0.namespace.svc.cluster.local:6379"
      }

      get_current_comp_nodes_for_scale_in() {
        current_comp_primary_node=("redis-shard-98x-0.namespace.svc.cluster.local:6379")
        current_comp_other_nodes=("redis-shard-98x-1.namespace.svc.cluster.local:6379")
      }

      setup() {
        export KB_CLUSTER_COMPONENT_IS_SCALING_IN="true"
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="172.42.0.1,172.42.0.2,172.42.0.3,172.42.0.4,172.42.0.5"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x,redis-shard-7hy,redis-shard-jwl"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x,redis-shard-7hy,redis-shard-jwl"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_IS_SCALING_IN
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
      }
      After "un_setup"

      It "returns 1 when the number of shards in the cluster is less than 3 after scaling down"
        When call scale_in_redis_cluster_shard
        The status should be failure
        The error should include "The number of shards in the cluster is less than 3 after scaling in, please check."
        The stdout should include "other_undeleted_component_nodes: redis-shard-7hy-0.redis-shard-7hy-headless:6379 redis-shard-7hy-1.redis-shard-7hy-headless:6379 redis-shard-jwl-0.redis-shard-jwl-headless:6379"
      End
    End

    Context "when scaling in redis cluster shard successfully"
      find_exist_available_node() {
        echo "redis-shard-98x-0.namespace.svc.cluster.local:6379"
      }

      get_current_comp_nodes_for_scale_in() {
        current_comp_primary_node=("redis-shard-98x-0.namespace.svc.cluster.local:6379")
        current_comp_other_nodes=("redis-shard-98x-1.namespace.svc.cluster.local:6379")
      }

      get_cluster_id() {
        echo "cluster_id_123"
      }

      scale_in_shard_rebalance_to_zero() {
        return 0
      }

      scale_in_shard_del_node() {
        return 0
      }

      setup() {
        export KB_CLUSTER_COMPONENT_IS_SCALING_IN="true"
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1,redis-shard-kpl-0,redis-shard-kpl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6,10.42.0.7,10.42.0.8"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="172.42.0.1,172.42.0.2,172.42.0.3,172.42.0.4,172.42.0.5,172.42.0.6,172.42.0.7,172.42.0.8"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x,redis-shard-7hy,redis-shard-jwl,redis-shard-kpl"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x,redis-shard-7hy,redis-shard-jwl,redis-shard-kpl"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_IS_SCALING_IN
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
      }
      After "un_setup"

      It "returns 0 when scaling in redis cluster shard successfully"
        When call scale_in_redis_cluster_shard
        The status should be success
        The output should include "Redis cluster scale in shard rebalance to zero successfully"
        The output should include "Redis cluster scale in shard delete node redis-shard-98x-0.namespace.svc.cluster.local:6379 successfully"
        The output should include "Redis cluster scale in shard delete node redis-shard-98x-1.namespace.svc.cluster.local:6379 successfully"
      End
    End

    Context "when failed to rebalance the cluster for the current component when scaling in"
      find_exist_available_node() {
        echo "redis-shard-98x-0.namespace.svc.cluster.local:6379"
      }

      get_current_comp_nodes_for_scale_in() {
        current_comp_primary_node=("redis-shard-98x-0.namespace.svc.cluster.local:6379")
        current_comp_other_nodes=("redis-shard-98x-1.namespace.svc.cluster.local:6379")
      }

      get_cluster_id() {
        echo "cluster_id_123"
      }

      scale_in_shard_rebalance_to_zero() {
        return 1
      }

      setup() {
        export KB_CLUSTER_COMPONENT_IS_SCALING_IN="true"
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1,redis-shard-kpl-0,redis-shard-kpl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6,10.42.0.7,10.42.0.8"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="172.42.0.1,172.42.0.2,172.42.0.3,172.42.0.4,172.42.0.5,172.42.0.6,172.42.0.7,172.42.0.8"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x,redis-shard-7hy,redis-shard-jwl,redis-shard-kpl"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x,redis-shard-7hy,redis-shard-jwl,redis-shard-kpl"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_IS_SCALING_IN
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
      }
      After "un_setup"

      It "returns 1 when failed to rebalance the cluster for the current component when scaling in"
        When call scale_in_redis_cluster_shard
        The status should be failure
        The error should include "Failed to rebalance the cluster for the current component when scaling in"
        The stdout should include "other_undeleted_component_nodes: redis-shard-7hy-0.redis-shard-7hy-headless:6379 redis-shard-7hy-1.redis-shard-7hy-headless:6379 redis-shard-jwl-0.redis-shard-jwl-headless:6379 redis-shard-jwl-1.redis-shard-jwl-headless:6379 redis-shard-kpl-0.redis-shard-kpl-headless:6379 redis-shard-kpl-1.redis-shard-kpl-headless:637"
      End
    End

    Context "when failed to delete the node from the cluster when scaling in"
      find_exist_available_node() {
        echo "redis-shard-98x-0.namespace.svc.cluster.local:6379"
      }

      get_current_comp_nodes_for_scale_in() {
        current_comp_primary_node=("redis-shard-98x-0.namespace.svc.cluster.local:6379")
        current_comp_other_nodes=("redis-shard-98x-1.namespace.svc.cluster.local:6379")
      }

      get_cluster_id() {
        echo "cluster_id_123"
      }

      scale_in_shard_rebalance_to_zero() {
        return 0
      }

      scale_in_shard_del_node() {
        return 1
      }

      setup() {
        export KB_CLUSTER_COMPONENT_IS_SCALING_IN="true"
        export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-98x"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard-98x"
        export KB_CLUSTER_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1,redis-shard-7hy-0,redis-shard-7hy-1,redis-shard-jwl-0,redis-shard-jwl-1,redis-shard-kpl-0,redis-shard-kpl-1"
        export KB_CLUSTER_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2,10.42.0.3,10.42.0.4,10.42.0.5,10.42.0.6,10.42.0.7,10.42.0.8"
        export KB_CLUSTER_COMPONENT_POD_NAME_LIST="redis-shard-98x-0,redis-shard-98x-1"
        export KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST="10.42.0.1,10.42.0.2"
        export KB_CLUSTER_POD_IP_LIST="172.42.0.1,172.42.0.2,172.42.0.3,172.42.0.4,172.42.0.5,172.42.0.6,172.42.0.7,172.42.0.8"
        export KB_CLUSTER_COMPONENT_LIST="redis-shard-98x,redis-shard-7hy,redis-shard-jwl,redis-shard-kpl"
        export KB_CLUSTER_COMPONENT_DELETING_LIST=""
        export KB_CLUSTER_COMPONENT_UNDELETED_LIST="redis-shard-98x,redis-shard-7hy,redis-shard-jwl,redis-shard-kpl"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_COMPONENT_IS_SCALING_IN
        unset CURRENT_SHARD_COMPONENT_SHORT_NAME
        unset KB_CLUSTER_POD_NAME_LIST
        unset KB_CLUSTER_POD_HOST_IP_LIST
        unset KB_CLUSTER_COMPONENT_POD_NAME_LIST
        unset KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST
        unset KB_CLUSTER_POD_IP_LIST
        unset KB_CLUSTER_COMPONENT_LIST
        unset KB_CLUSTER_COMPONENT_DELETING_LIST
        unset KB_CLUSTER_COMPONENT_UNDELETED_LIST
      }
      After "un_setup"

      It "returns 1 when failed to delete the node from the cluster when scaling in"
        When call scale_in_redis_cluster_shard
        The status should be failure
        The error should include "Failed to delete the node redis-shard-98x-0.namespace.svc.cluster.local:6379 from the cluster when scaling in"
        The stdout should include "Redis cluster scale in shard rebalance to zero successfully"
      End
    End
  End

  Describe "initialize_or_scale_out_redis_cluster()"
    Context "when required environment variables are not set"
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

      It "exits with status 1 when required environment variables are not set"
        When run initialize_or_scale_out_redis_cluster
        The status should be failure
        The stderr should include "Error: Required environment variable KB_CLUSTER_POD_IP_LIST and SERVICE_PORT is not set."
      End
    End

    Context "when Redis Cluster is not initialized"
      check_cluster_initialized() {
        return 1
      }

      initialize_redis_cluster() {
        return 0
      }

      setup() {
        export KB_CLUSTER_POD_IP_LIST="172.42.0.1,172.42.0.2,172.42.0.3,172.42.0.4,172.42.0.5,172.42.0.6"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "initializes Redis Cluster successfully"
        When run initialize_or_scale_out_redis_cluster
        The status should be success
        The output should include "Redis Cluster not initialized, initializing..."
        The output should include "Redis Cluster initialized successfully"
      End
    End

    Context "when Redis Cluster is already initialized"
      check_cluster_initialized() {
        return 0
      }

      scale_out_redis_cluster_shard() {
        return 0
      }

      setup() {
        export KB_CLUSTER_POD_IP_LIST="172.42.0.1,172.42.0.2,172.42.0.3,172.42.0.4,172.42.0.5,172.42.0.6"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "scales out Redis Cluster shard successfully"
        When run initialize_or_scale_out_redis_cluster
        The status should be success
        The output should include "Redis Cluster already initialized, scaling out the shard..."
        The output should include "Redis Cluster scale out shard successfully"
      End
    End

    Context "when failed to initialize Redis Cluster"
      check_cluster_initialized() {
        return 1
      }

      initialize_redis_cluster() {
        return 1
      }

      setup() {
        export KB_CLUSTER_POD_IP_LIST="172.42.0.1,172.42.0.2,172.42.0.3,172.42.0.4,172.42.0.5,172.42.0.6"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "exits with status 1 when failed to initialize Redis Cluster"
        When run initialize_or_scale_out_redis_cluster
        The status should be failure
        The stderr should include "Failed to initialize Redis Cluster"
        The stdout should include "Redis Cluster not initialized, initializing.."
      End
    End

    Context "when failed to scale out Redis Cluster shard"
      check_cluster_initialized() {
        return 0
      }

      scale_out_redis_cluster_shard() {
        return 1
      }

      setup() {
        export KB_CLUSTER_POD_IP_LIST="172.42.0.1,172.42.0.2,172.42.0.3,172.42.0.4,172.42.0.5,172.42.0.6"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_CLUSTER_POD_IP_LIST
        unset SERVICE_PORT
      }
      After "un_setup"

      It "exits with status 1 when failed to scale out Redis Cluster shard"
        When run initialize_or_scale_out_redis_cluster
        The status should be failure
        The stderr should include "Failed to scale out Redis Cluster shard"
        The stdout should include "Redis Cluster already initialized, scaling out the shard..."
      End
    End
  End
End