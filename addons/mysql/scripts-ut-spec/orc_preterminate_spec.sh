# shellcheck shell=bash

Describe "Orchestrator preTerminate contract"
  setup() {
    export __SOURCED__=1
    export CLUSTER_NAME="mysql-cluster"
  }
  Before "setup"
  Include ../scripts/orc-preterminate.sh

  It "fails closed when Orchestrator is unreachable"
    run_orchestrator_client() { return 124; }
    When run forget_cluster
    The status should be failure
    The stderr should include "Orchestrator unreachable"
  End

  It "forgets by cluster alias and verifies absence"
    run_orchestrator_client() {
      case "$*" in
        "-c clusters-alias") printf '%s\n' "other,other" ;;
        "-c forget-cluster -alias mysql-cluster") return 0 ;;
        *) return 1 ;;
      esac
    }
    sleep() { :; }
    When run forget_cluster
    The status should be success
    The output should include "successfully removed"
  End

  It "fails when the alias remains registered"
    run_orchestrator_client() {
      case "$*" in
        "-c clusters-alias") printf '%s\n' "mysql-cluster,mysql-cluster" ;;
        "-c forget-cluster -alias mysql-cluster") return 0 ;;
        *) return 1 ;;
      esac
    }
    sleep() { :; }
    When run forget_cluster
    The status should be failure
    The stderr should include "still exists"
  End
End
