# shellcheck shell=sh

Describe "Galera Parallel startup plus ordered shutdown template contract"
  ADDON_ROOT="${SHELLSPEC_CWD:?}/addons/mariadb"
  CMPD_GALERA="${ADDON_ROOT}/templates/cmpd-galera.yaml"
  SCRIPT_CM="${ADDON_ROOT}/templates/configmap-scripts-galera.yaml"

  It "keeps Galera pod management policy Parallel"
    When call grep -F "podManagementPolicy: Parallel" "${CMPD_GALERA}"
    The status should be success
    The output should include "podManagementPolicy: Parallel"
  End

  It "wires preStop to the mounted galera-prestop script"
    When call grep -F "/scripts/galera-prestop.sh" "${CMPD_GALERA}"
    The status should be success
    The output should include "/scripts/galera-prestop.sh"
  End

  It "keeps enough termination budget for bounded peer wait plus local shutdown"
    When call grep -F "terminationGracePeriodSeconds: 120" "${CMPD_GALERA}"
    The status should be success
    The output should include "terminationGracePeriodSeconds: 120"
  End

  It "mounts galera-prestop.sh in the Galera script ConfigMap"
    When call grep -F 'galera-prestop.sh: |-' "${SCRIPT_CM}"
    The status should be success
    The output should include "galera-prestop.sh"
  End

  It "does not keep the old inline wsrep_on-only preStop block"
    When call grep -F 'SET GLOBAL wsrep_on=OFF;' "${CMPD_GALERA}"
    The status should be failure
  End
End
