# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_cluster_replica_member_leave_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Cluster Replica Member Leave Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file
  Include ../redis-cluster-scripts/redis-cluster-common.sh
  Include ../redis-cluster-scripts/redis-cluster-replica-member-leave.sh

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "remove_replica_from_shard_if_need()"
    Context "when failed to get current pod fqdn from current shard pod fqdn list"
      setup() {
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local"
        export CURRENT_POD_NAME="redis-shard-98x-2"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset CURRENT_POD_NAME
      }
      After "un_setup"

      It "exits with status 1 when failed to get current pod fqdn from current shard pod fqdn list"
        When run remove_replica_from_shard_if_need
        The status should be failure
        The stderr should include "Error: Failed to get current pod: redis-shard-98x-2 fqdn from current shard pod fqdn list: redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local. Exiting."
      End
    End

    Context "when failed to get cluster nodes info"
      get_cluster_nodes_info_with_retry() {
        return 1
      }

      setup() {
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local"
        export CURRENT_POD_NAME="redis-shard-98x-1"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset CURRENT_POD_NAME
      }
      After "un_setup"

      It "returns 1 when failed to get cluster nodes info"
        When call remove_replica_from_shard_if_need
        The status should be failure
        The stderr should include "Failed to get cluster nodes info in remove_replica_from_shard_if_need"
      End
    End

    Context "when cluster nodes info contains only one line or is empty"
      get_cluster_nodes_info_with_retry() {
        echo "f7ed4469f3b90c790e0b482ce3843b3ee9fe4523 172.42.0.5:6379@16379,redis-shard-98x-1.redis-shard-98x-headless.default.svc myself,master - 0 1681966481000 0 connected"
        return 0
      }

      setup() {
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local"
        export CURRENT_POD_NAME="redis-shard-98x-1"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset CURRENT_POD_NAME
      }
      After "un_setup"

      It "returns 0 when cluster nodes info contains only one line or is empty"
        When call remove_replica_from_shard_if_need
        The status should be success
        The output should include "Cluster nodes info contains only one line or is empty, returning..."
      End
    End

    Context "when current node is a slave"
      get_cluster_nodes_info_with_retry() {
        echo "f7ed4469f3b90c790e0b482ce3843b3ee9fe4523 172.42.0.5:6379@16379,redis-shard-98x-1.redis-shard-98x-headless.default.svc myself,slave 172.42.0.4:6379 0 1681966481000 1 connected"$'\n'"c1ed4469f3b90c790e0b482ce3843b3ee9fe4524 172.42.0.4:6379@16379,redis-shard-98x-0.redis-shard-98x-headless.default.svc master - 0 1681966481000 2 connected 5461-10922"
        return 0
      }

      secondary_member_leave_del_node_with_retry() {
        return 0
      }

      get_cluster_nodes_info() {
        echo "c1ed4469f3b90c790e0b482ce3843b3ee9fe4524 172.42.0.4:6379@16379,redis-shard-98x-0.redis-shard-98x-headless.default.svc master - 0 1681966481000 2 connected 5461-10922"
        return 0
      }

      setup() {
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local"
        export CURRENT_POD_NAME="redis-shard-98x-1"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset CURRENT_POD_NAME
      }
      After "un_setup"

      It "returns 0 when successfully removed replica from the cluster"
        When call remove_replica_from_shard_if_need
        The status should be success
        The output should include "Current node redis-shard-98x-1 is a slave, removing it from the cluster..."
        The output should include "Successfully removed replica from shard."
      End
    End

    Context "when current node is a slave and failed to remove it from the cluster"
      get_cluster_nodes_info_with_retry() {
        echo "f7ed4469f3b90c790e0b482ce3843b3ee9fe4523 172.42.0.5:6379@16379,redis-shard-98x-1.redis-shard-98x-headless.default.svc myself,slave 172.42.0.4:6379 0 1681966481000 1 connected"$'\n'"c1ed4469f3b90c790e0b482ce3843b3ee9fe4524 172.42.0.4:6379@16379,redis-shard-98x-0.redis-shard-98x-headless.default.svc master - 0 1681966481000 2 connected 5461-10922"
        return 0
      }

      secondary_member_leave_del_node_with_retry() {
        return 1
      }

      setup() {
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local"
        export CURRENT_POD_NAME="redis-shard-98x-1"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset CURRENT_POD_NAME
      }
      After "un_setup"

      It "returns 1 when failed to remove current node from the cluster"
        When call remove_replica_from_shard_if_need
        The status should be failure
        The output should include "Current node redis-shard-98x-1 is a slave, removing it from the cluster..."
        The stderr should include "Failed to remove replica from shard."
      End
    End

    Context "when current node is a slave and failed to get cluster nodes info after removing it from the cluster"
      get_cluster_nodes_info_with_retry() {
        echo "f7ed4469f3b90c790e0b482ce3843b3ee9fe4523 172.42.0.5:6379@16379,redis-shard-98x-1.redis-shard-98x-headless.default.svc myself,slave 172.42.0.4:6379 0 1681966481000 1 connected"$'\n'"c1ed4469f3b90c790e0b482ce3843b3ee9fe4524 172.42.0.4:6379@16379,redis-shard-98x-0.redis-shard-98x-headless.default.svc master - 0 1681966481000 2 connected 5461-10922"
        return 0
      }

      secondary_member_leave_del_node_with_retry() {
        return 0
      }

      get_cluster_nodes_info() {
        return 1
      }

      setup() {
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local"
        export CURRENT_POD_NAME="redis-shard-98x-1"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset CURRENT_POD_NAME
      }
      After "un_setup"

      It "returns 1 when failed to get cluster nodes info after removing current node from the cluster"
        When call remove_replica_from_shard_if_need
        The status should be failure
        The output should include "Current node redis-shard-98x-1 is a slave, removing it from the cluster..."
        The output should include "Successfully removed replica from shard."
        The stderr should include "Failed to get cluster nodes info in remove_replica_from_shard_if_need"
      End
    End

    Context "when current node is a slave and still exists in the cluster after removing it"
      get_cluster_nodes_info_with_retry() {
        echo "f7ed4469f3b90c790e0b482ce3843b3ee9fe4523 172.42.0.5:6379@16379,redis-shard-98x-1.redis-shard-98x-headless.default.svc myself,slave 172.42.0.4:6379 0 1681966481000 1 connected"$'\n'"c1ed4469f3b90c790e0b482ce3843b3ee9fe4524 172.42.0.4:6379@16379,redis-shard-98x-0.redis-shard-98x-headless.default.svc master - 0 1681966481000 2 connected 5461-10922"
        return 0
      }

      secondary_member_leave_del_node_with_retry() {
        return 0
      }

      get_cluster_nodes_info() {
        echo "f7ed4469f3b90c790e0b482ce3843b3ee9fe4523 172.42.0.5:6379@16379,redis-shard-98x-1.redis-shard-98x-headless.default.svc myself,slave 172.42.0.4:6379 0 1681966481000 1 connected"$'\n'"c1ed4469f3b90c790e0b482ce3843b3ee9fe4524 172.42.0.4:6379@16379,redis-shard-98x-0.redis-shard-98x-headless.default.svc master - 0 1681966481000 2 connected 5461-10922"
        return 0
      }

      setup() {
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local"
        export CURRENT_POD_NAME="redis-shard-98x-1"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset CURRENT_POD_NAME
      }
      After "un_setup"

      It "returns 1 when current node still exists in the cluster after removing it"
        When call remove_replica_from_shard_if_need
        The status should be failure
        The output should include "Current node redis-shard-98x-1 is a slave, removing it from the cluster..."
        The output should include "Successfully removed replica from shard."
        The stderr should include "Failed to remove replica from shard."
      End
    End

    Context "when current node is a master"
      get_cluster_nodes_info_with_retry() {
        echo "f7ed4469f3b90c790e0b482ce3843b3ee9fe4523 172.42.0.5:6379@16379,redis-shard-98x-1.redis-shard-98x-headless.default.svc myself,slave 172.42.0.4:6379 0 1681966481000 1 connected"$'\n'"c1ed4469f3b90c790e0b482ce3843b3ee9fe4524 172.42.0.4:6379@16379,redis-shard-98x-0.redis-shard-98x-headless.default.svc master - 0 1681966481000 2 connected 5461-10922"
        return 0
      }

      setup() {
        export CURRENT_SHARD_POD_FQDN_LIST="redis-shard-98x-0.namespace.svc.cluster.local,redis-shard-98x-1.namespace.svc.cluster.local"
        export CURRENT_POD_NAME="redis-shard-98x-0"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_POD_FQDN_LIST
        unset CURRENT_POD_NAME
      }
      After "un_setup"

      It "returns 0 and does not remove current node from the cluster when it is a master"
        When call remove_replica_from_shard_if_need
        The status should be success
        The output should include "Current node redis-shard-98x-0 is a master, no need to remove it from the cluster."
      End
    End
  End
End