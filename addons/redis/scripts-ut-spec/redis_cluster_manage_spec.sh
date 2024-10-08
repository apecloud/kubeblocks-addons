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

End