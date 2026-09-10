# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey replicasLimit contract"
  data_cmpd="../templates/cmpd.yaml"
  sentinel_cmpd="../templates/cmpd-valkey-sentinel.yaml"
  cluster_schema="../../../addons-cluster/valkey/values.schema.json"

  It "declares the data component scale contract as 1..5"
    When call bash -c "grep -A6 'replicasLimit:' '${data_cmpd}'"
    The status should be success
    The stdout should include "minReplicas: 1"
    The stdout should include "maxReplicas: 5"
  End

  It "declares the Sentinel scale contract as 3..5"
    When call bash -c "grep -A6 'replicasLimit:' '${sentinel_cmpd}'"
    The status should be success
    The stdout should include "minReplicas: 3"
    The stdout should include "maxReplicas: 5"
  End

  It "caps all cluster chart schema replica fields at the CMPD maximum (5)"
    # The chart schema must not accept replica counts the CMPD will reject.
    # 3 capped fields: data replicas, sentinel replicas, and (since the
    # sharding topology landed) cluster.replicas per shard.
    When call bash -c "grep -c '\"maximum\": 5' '${cluster_schema}'"
    The status should be success
    The stdout should eq "3"
  End

  It "keeps the sentinel schema minimum at the CMPD minimum (3)"
    When call grep -F '"minimum": 3' "${cluster_schema}"
    The status should be success
    The stdout should include '"minimum": 3'
  End
End
