# shellcheck shell=bash
# shellcheck disable=SC2034

# Phase B behavioral tests for valkey-cluster-manage.sh (issue #3026):
# deterministic coordinator election (hard-fail on bad input), slot
# arithmetic, and the drain-then-prove shard-removal gate.

Describe "valkey-cluster-manage.sh"
  Include ../scripts/valkey-cluster-manage.sh

  base_env() {
    export CURRENT_POD_NAME="vk-shard-abc-0"
    export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-abc"
    export CURRENT_SHARD_POD_FQDN_LIST="vk-shard-abc-0.h.ns.svc,vk-shard-abc-1.h.ns.svc"
    export ALL_SHARDS_COMPONENT_SHORT_NAMES="shard-abc:shard-abc,shard-def:shard-def,shard-ghi:shard-ghi"
    export SERVICE_PORT="6379"
    unset VALKEY_DEFAULT_PASSWORD VALKEY_CLI_TLS_ARGS
  }
  base_cleanup() {
    unset CURRENT_POD_NAME CURRENT_SHARD_COMPONENT_SHORT_NAME CURRENT_SHARD_POD_FQDN_LIST \
          ALL_SHARDS_COMPONENT_SHORT_NAMES SERVICE_PORT
  }
  Before "base_env"
  After "base_cleanup"

  Describe "validate_manage_env()"
    It "hard-fails listing missing inputs"
      unset ALL_SHARDS_COMPONENT_SHORT_NAMES CURRENT_SHARD_COMPONENT_SHORT_NAME
      When call validate_manage_env
      The status should be failure
      The stderr should include "ALL_SHARDS_COMPONENT_SHORT_NAMES"
      The stderr should include "CURRENT_SHARD_COMPONENT_SHORT_NAME"
      The stderr should include "hard fail (no fallback)"
    End
  End

  Describe "coordinator_shard()"
    It "picks the lexicographically first shard deterministically"
      export ALL_SHARDS_COMPONENT_SHORT_NAMES="shard-zzz:shard-zzz,shard-aaa:shard-aaa,shard-mmm:shard-mmm"
      When call coordinator_shard
      The status should be success
      The stdout should equal "shard-aaa"
    End

    It "hard-fails on a duplicate shard name (unstable input, no fallback)"
      export ALL_SHARDS_COMPONENT_SHORT_NAMES="shard-aaa:shard-aaa,shard-aaa:shard-aaa"
      When call coordinator_shard
      The status should be failure
      The stderr should include "duplicate shard name"
    End

    It "hard-fails on an empty entry"
      export ALL_SHARDS_COMPONENT_SHORT_NAMES=":,shard-bbb:shard-bbb"
      When call coordinator_shard
      The status should be failure
      The stderr should include "empty shard name"
    End
  End

  Describe "self_is_coordinator_pod()"
    It "is true only for the first pod of the coordinator shard"
      export CURRENT_POD_NAME="vk-shard-abc-0"
      When call self_is_coordinator_pod "shard-abc"
      The status should be success
    End

    It "is false for a non-first pod of the coordinator shard"
      export CURRENT_POD_NAME="vk-shard-abc-1"
      When call self_is_coordinator_pod "shard-abc"
      The status should be failure
    End

    It "is false for pods of other shards"
      When call self_is_coordinator_pod "shard-def"
      The status should be failure
    End
  End

  Describe "slots_owned_by()"
    It "sums slot ranges and singles from the node line"
      build_cli() { _cli=(mock_nodes); }
      mock_nodes() {
        printf 'aaaa111 10.0.0.1:6379@16379 master - 0 0 1 connected 0-99 200 300-309\n'
        printf 'bbbb222 10.0.0.2:6379@16379 master - 0 0 2 connected 5461-10922\n'
      }
      When call slots_owned_by "any-host" "aaaa111"
      The status should be success
      The stdout should equal "111"
    End

    It "ignores migrating/importing markers"
      build_cli() { _cli=(mock_nodes2); }
      mock_nodes2() {
        printf 'cccc333 10.0.0.3:6379@16379 master - 0 0 3 connected 0-9 [123->-abcdef]\n'
      }
      When call slots_owned_by "any-host" "cccc333"
      The status should be success
      The stdout should equal "10"
    End

    It "returns -1 when the node id is not in the cluster view"
      build_cli() { _cli=(mock_nodes3); }
      mock_nodes3() { printf 'dddd444 10.0.0.4:6379@16379 master - 0 0 4 connected 0-16383\n'; }
      When call slots_owned_by "any-host" "absent-id"
      The status should be success
      The stdout should equal "-1"
    End
  End

  Describe "form_cluster() defer classification"
    It "defers (rc=1) when fewer than 3 shards are visible"
      each_shard_fqdn_list() {
        printf 'SHARD_ABC vk-shard-abc-0.h.ns.svc,vk-shard-abc-1.h.ns.svc\n'
        printf 'SHARD_DEF vk-shard-def-0.h.ns.svc\n'
      }
      build_cli() { _cli=(mock_pong); }
      mock_pong() { echo PONG; }
      When call form_cluster
      The status should be failure
      The stderr should include "needs >=3"
      The stderr should include "retry-safe"
      The stdout should include ""
    End

    It "defers when a designated primary does not answer"
      each_shard_fqdn_list() {
        printf 'SHARD_ABC vk-shard-abc-0.h.ns.svc\n'
        printf 'SHARD_DEF vk-shard-def-0.h.ns.svc\n'
        printf 'SHARD_GHI vk-shard-ghi-0.h.ns.svc\n'
      }
      build_cli() { _cli=(mock_silent); }
      mock_silent() { return 1; }
      When call form_cluster
      The status should be failure
      The stderr should include "not answering yet"
      The stderr should include "retry-safe"
    End
  End

  Describe "shard removal drain gate"
    It "refuses node deletion while slots remain (positive zero proof required)"
      # Simulate: drain issued but 5 slots still owned afterwards.
      validate_manage_env() { return 0; }
      each_shard_fqdn_list() {
        printf 'SHARD_DEF vk-shard-def-0.h.ns.svc\n'
      }
      cluster_state_of() { echo "ok"; }
      shard_master_id_via() { echo "master-id-1"; }
      slots_owned_by() { echo "5"; }
      build_cluster_cli() { _ccli=(mock_reb); }
      mock_reb() { echo "rebalanced"; }
      # shard_remove exits; run in subshell via run
      When run shard_remove
      The status should be failure
      The stderr should include "still owns 5 slots"
      The stderr should include "NOT removing nodes"
      The stdout should include ""
    End
  End
End
