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

End