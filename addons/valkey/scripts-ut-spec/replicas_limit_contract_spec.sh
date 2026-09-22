# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey replicasLimit contract"
  data_cmpd="../templates/cmpd.yaml"
  cluster_schema="../../../addons-cluster/valkey/values.schema.json"

  It "declares the data component scale contract as 1..5"
    When call bash -c "grep -A6 'replicasLimit:' '${data_cmpd}'"
    The status should be success
    The stdout should include "minReplicas: 1"
    The stdout should include "maxReplicas: 5"
  End

  It "keeps the Sentinel scale contract in the cluster chart schema (3..5)"
    # The sentinel CMPD no longer declares replicasLimit — the bound users scale
    # through lives in the cluster chart, so both ends are pinned there.  A
    # future change to the sentinel CMPD bound without touching the chart (or
    # the other way around) fails here.
    When call bash -c "grep -A6 '\"Sentinel replicas\"' '${cluster_schema}'"
    The status should be success
    The stdout should include '"minimum": 3'
    The stdout should include '"maximum": 5'
  End

  It "caps both cluster chart schema replica fields at the CMPD maximum (5)"
    # The chart schema must not accept replica counts the CMPD will reject.
    When call bash -c "grep -c '\"maximum\": 5' '${cluster_schema}'"
    The status should be success
    The stdout should eq "2"
  End

  It "keeps the sentinel schema minimum at the CMPD minimum (3)"
    When call grep -F '"minimum": 3' "${cluster_schema}"
    The status should be success
    The stdout should include '"minimum": 3'
  End
End
