# shellcheck shell=bash
# shellcheck disable=SC2034


# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "monitor_master_node_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi


Describe "Opensearch Node Management Tests"
  Include ../scripts/monitor-master-node.sh
  
  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }
  BeforeAll "init"


  Describe "cleanup()"
    # Test scenario: When the node is not master
    Context "when this node is not master"
      setup() {
        export CLUSTER_NAME="opensearch-cluster"
        export OPENSEARCH_COMPONENT_SHORT_NAME="opensearch"
        export NODE_NAME="test-node"
      }
      Before "setup"
      It "exits the loop"
        # Mock returning a master node that is different from current node
        http() {
            echo "opensearch-cluster-opensearch-master"
        }
        When call cleanup
        The status should be success
        The stdout should include "This node is not master."
      End
    End
  End
End