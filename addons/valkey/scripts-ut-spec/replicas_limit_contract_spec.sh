# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey replicasLimit contract"
  data_cmpd="../templates/cmpd.yaml"
  sentinel_cmpd="../templates/cmpd-valkey-sentinel.yaml"

  It "keeps data component within the tested scale contract"
    When call bash -c "grep -A6 'replicasLimit:' '${data_cmpd}'"
    The status should be success
    The stdout should include "minReplicas: 1"
    The stdout should include "maxReplicas: 4"
  End

  It "keeps Sentinel fixed at the validated three-replica contract"
    When call bash -c "grep -A3 'replicasLimit:' '${sentinel_cmpd}'"
    The status should be success
    The stdout should include "minReplicas: 3"
    The stdout should include "maxReplicas: 3"
  End
End
