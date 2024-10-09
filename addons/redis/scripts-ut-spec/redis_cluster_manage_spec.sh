# shellcheck shell=bash
# shellcheck disable=SC2034

# we need bash 4 or higher to run this script in some cases
should_skip_when_shell_type_and_version_invalid() {
  # validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
  if validate_shell_type_and_version "bash" 4 &>/dev/null; then
    # should not skip
    return 1
  fi
  echo "redis_cluster_manage_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  return 0
}

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

      extract_ordinal_from_object_name() {
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

      extract_ordinal_from_object_name() {
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

      extract_ordinal_from_object_name() {
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

      extract_ordinal_from_object_name() {
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
      extract_ordinal_from_object_name() {
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
End