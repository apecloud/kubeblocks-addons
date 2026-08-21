# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329

Describe "ORC role probe script tests"
  Include ../scripts/orc-role-probe.sh

  setup_role_probe() {
    export KB_AGENT_POD_NAME="mysql-0"
  }

  cleanup_role_probe() {
    unset KB_AGENT_POD_NAME
  }

  Before 'setup_role_probe'
  After 'cleanup_role_probe'

  It "publishes primary when Orchestrator identifies the local pod as master"
    run_orc_role_probe() {
      printf 'mysql-0:3306\n'
    }

    When call probe_orchestrator_role
    The status should be success
    The output should equal "primary"
  End

  It "does not parse successful client stderr noise as the master name"
    run_orc_role_probe() {
      printf 'transient client warning\n' >&2
      printf 'mysql-0:3306\n'
    }

    When call probe_orchestrator_role
    The status should be success
    The output should equal "primary"
    The error should include "transient client warning"
  End

  It "publishes secondary when the local pod is in the replica list"
    run_orc_role_probe() {
      if [ "$2" = "which-cluster-master" ]; then
        printf 'mysql-1:3306\n'
      else
        printf 'mysql-0:3306\nmysql-2:3306\n'
      fi
    }

    When call probe_orchestrator_role
    The status should be success
    The output should equal "secondary"
  End

  It "fails instead of publishing an empty role when the master query fails"
    run_orc_role_probe() {
      printf 'orchestrator unavailable\n'
      return 1
    }

    When call probe_orchestrator_role
    The status should be failure
    The error should include "cannot determine master"
    The output should equal ""
  End

  It "fails instead of publishing an empty role when the master output is empty"
    run_orc_role_probe() {
      return 0
    }

    When call probe_orchestrator_role
    The status should be failure
    The error should include "master query returned empty output"
    The output should equal ""
  End

  It "fails instead of publishing an empty role when the replica query fails"
    run_orc_role_probe() {
      if [ "$2" = "which-cluster-master" ]; then
        printf 'mysql-1:3306\n'
        return 0
      fi
      printf 'replica query failed\n'
      return 1
    }

    When call probe_orchestrator_role
    The status should be failure
    The error should include "cannot list replicas"
    The output should equal ""
  End

  It "fails instead of publishing an empty role when the pod is absent from topology"
    run_orc_role_probe() {
      if [ "$2" = "which-cluster-master" ]; then
        printf 'mysql-1:3306\n'
      else
        printf 'mysql-2:3306\n'
      fi
    }

    When call probe_orchestrator_role
    The status should be failure
    The error should include "is absent from Orchestrator topology"
    The output should equal ""
  End
End
