# shellcheck shell=bash
# shellcheck disable=SC2034

# Phase C behavioral tests (issue #3037): cluster roleProbe contract,
# switchover candidate selection + confirmation, member leave safety.

Describe "valkey-cluster-check-role.sh"
  Include ../scripts/valkey-cluster-check-role.sh

  It "emits 'primary <epoch>' from a myself,master line"
    build_cli_cmd() { cli_cmd=(mock_nodes); }
    mock_nodes() {
      printf 'aaa 10.0.0.1:6379@16379 myself,master - 0 0 7 connected 0-5460\n'
      printf 'bbb 10.0.0.2:6379@16379 slave aaa 0 0 7 connected\n'
    }
    When call probe_cluster_role
    The status should be success
    The stdout should equal "primary 7"
  End

  It "emits 'secondary <epoch>' from a myself,slave line"
    build_cli_cmd() { cli_cmd=(mock_nodes); }
    mock_nodes() {
      printf 'bbb 10.0.0.2:6379@16379 myself,slave aaa 0 0 12 connected\n'
    }
    When call probe_cluster_role
    The status should be success
    The stdout should equal "secondary 12"
  End

  It "skips the sample (non-zero, no role token) when myself is absent"
    build_cli_cmd() { cli_cmd=(mock_nodes); }
    mock_nodes() { printf 'ccc 10.0.0.3:6379@16379 master - 0 0 3 connected\n'; }
    When call probe_cluster_role
    The status should be failure
    The stdout should equal ""
    The stderr should include "skip sample"
  End

  It "skips the sample on a non-numeric epoch (never emits a guessed role)"
    build_cli_cmd() { cli_cmd=(mock_nodes); }
    mock_nodes() { printf 'ddd 10.0.0.4:6379@16379 myself,master - 0 0 oops connected\n'; }
    When call probe_cluster_role
    The status should be failure
    The stdout should equal ""
    The stderr should include "non-numeric config-epoch"
  End
End

Describe "valkey-cluster-switchover.sh"
  Include ../scripts/valkey-cluster-switchover.sh

  sw_env() {
    export CURRENT_SHARD_POD_FQDN_LIST="vk-s-0.h.ns.svc,vk-s-1.h.ns.svc,vk-s-2.h.ns.svc"
    export KB_SWITCHOVER_CURRENT_FQDN="vk-s-0.h.ns.svc"
    unset KB_SWITCHOVER_CANDIDATE_FQDN
    ut_mode="true"
  }
  sw_clean() { unset CURRENT_SHARD_POD_FQDN_LIST KB_SWITCHOVER_CURRENT_FQDN KB_SWITCHOVER_CANDIDATE_FQDN; }
  Before "sw_env"
  After "sw_clean"

  It "deterministically picks the first sorted in-shard replica"
    role_of() {
      case "$1" in
        vk-s-1.h.ns.svc) echo "replica" ;;
        vk-s-2.h.ns.svc) echo "replica" ;;
        *) echo "master" ;;
      esac
    }
    When call pick_candidate
    The status should be success
    The stdout should equal "vk-s-1.h.ns.svc"
  End

  It "hard-fails when no replica is available"
    role_of() { echo "unknown"; }
    When call pick_candidate
    The status should be failure
    The stderr should include "no reachable in-shard replica"
  End

  It "treats an already-master candidate as success (idempotent)"
    role_of() { echo "master"; }
    When call execute_switchover "vk-s-1.h.ns.svc"
    The status should be success
    The stdout should include "already master"
  End

  It "refuses to promote a candidate in unknown state"
    role_of() { echo "unknown"; }
    When call execute_switchover "vk-s-1.h.ns.svc"
    The status should be failure
    The stderr should include "cannot promote"
  End

  It "fails with a classified error when promotion is unconfirmed in budget"
    export SWITCHOVER_CONFIRM_BUDGET=2
    role_of() { echo "replica"; }
    When call confirm_promotion "vk-s-1.h.ns.svc"
    The status should be failure
    The stderr should include "did not report master within 2s"
    The stderr should include "safe to retry"
  End
End

Describe "valkey-cluster-member.sh"
  Include ../scripts/valkey-cluster-member.sh

  mb_env() {
    export CURRENT_SHARD_POD_FQDN_LIST="vk-s-0.h.ns.svc,vk-s-1.h.ns.svc"
    export SERVICE_PORT=6379
    ut_mode="true"
  }
  mb_clean() { unset CURRENT_SHARD_POD_FQDN_LIST KB_LEAVE_MEMBER_POD_FQDN KB_JOIN_MEMBER_POD_FQDN; }
  Before "mb_env"
  After "mb_clean"

  It "closes leave as effective when the member is already absent"
    export KB_LEAVE_MEMBER_POD_FQDN="vk-s-9.h.ns.svc"
    shard_vantage() { echo "vk-s-0.h.ns.svc"; }
    node_line_of() { echo ""; }
    When run member_leave
    The status should be success
    The stdout should include "leave already effective"
  End

  It "refuses to delete a master with no replica to fail over to"
    export KB_LEAVE_MEMBER_POD_FQDN="vk-s-0.h.ns.svc"
    shard_vantage() { echo "vk-s-1.h.ns.svc"; }
    node_line_of() { echo "id0 vk-s-0.h.ns.svc:6379@16379 master - 0 0 5 connected 0-5460"; }
    build_cli() { _cli=(mock_no_slave); }
    mock_no_slave() { printf 'id1 x myself,master - 0 0 5 connected\n'; }
    When run member_leave
    The status should be failure
    The stderr should include "would orphan slots"
  End

  It "requires the join target env"
    unset KB_JOIN_MEMBER_POD_FQDN
    When run member_join
    The status should be failure
    The stderr should include "KB_JOIN_MEMBER_POD_FQDN is required"
  End
End
