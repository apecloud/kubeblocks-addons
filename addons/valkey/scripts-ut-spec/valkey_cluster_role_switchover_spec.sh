# shellcheck shell=bash
# shellcheck disable=SC2034

# Phase C behavioral tests (issue #3037): cluster roleProbe contract,
# switchover candidate selection + confirmation, member leave safety.

Describe "valkey-cluster-check-role.sh"
  Include ../scripts/valkey-cluster-check-role.sh

  It "emits single-token 'primary' from a myself,master line"
    build_cli_cmd() { cli_cmd=(mock_nodes); }
    mock_nodes() {
      printf 'aaa 10.0.0.1:6379@16379 myself,master - 0 0 7 connected 0-5460\n'
      printf 'bbb 10.0.0.2:6379@16379 slave aaa 0 0 7 connected\n'
    }
    When call probe_cluster_role
    The status should be success
    The stdout should equal "primary"
  End

  It "emits single-token 'secondary' from a myself,slave line"
    build_cli_cmd() { cli_cmd=(mock_nodes); }
    mock_nodes() {
      printf 'bbb 10.0.0.2:6379@16379 myself,slave aaa 0 0 12 connected\n'
    }
    When call probe_cluster_role
    The status should be success
    The stdout should equal "secondary"
  End

  It "skips the sample (non-zero, no role token) when myself is absent"
    build_cli_cmd() { cli_cmd=(mock_nodes); }
    mock_nodes() { printf 'ccc 10.0.0.3:6379@16379 master - 0 0 3 connected\n'; }
    When call probe_cluster_role
    The status should be failure
    The stdout should equal ""
    The stderr should include "skip sample"
  End

  It "never emits a version token (single-token contract, versioned path deferred)"
    build_cli_cmd() { cli_cmd=(mock_nodes); }
    mock_nodes() { printf 'ddd 10.0.0.4:6379@16379 myself,master - 0 0 42 connected 0-5460\n'; }
    When call probe_cluster_role
    The status should be success
    The stdout should not include " "
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
    The stderr should include "phase=candidate-state"
  End

  It "refuses an explicit candidate outside this shard"
    export KB_SWITCHOVER_CANDIDATE_FQDN="vk-OTHER-9.h.ns.svc"
    When call switchover
    The status should be failure
    The stderr should include "phase=candidate-outside-shard"
  End

  It "refuses non-primary role switchover requests"
    export KB_SWITCHOVER_ROLE="secondary"
    When call switchover
    The status should be failure
    The stderr should include "phase=role-guard"
  End

  It "refuses a candidate that does not replicate this shard's master"
    role_of() { echo "replica"; }
    candidate_replicates_this_shard() { return 1; }
    When call execute_switchover "vk-s-1.h.ns.svc"
    The status should be failure
    The stderr should include "phase=candidate-wrong-master"
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
    # fake spec hostnames must count as resolvable on Linux CI (getent
    # exists there and would filter the whole roster as departed)
    host_resolves() { return 0; }
  }
  mb_clean() { unset CURRENT_SHARD_POD_FQDN_LIST KB_LEAVE_MEMBER_POD_FQDN KB_JOIN_MEMBER_POD_FQDN; }
  Before "mb_env"
  After "mb_clean"

  It "purges residue even when the vantage cannot see the member (no blind early close)"
    # review blocker: one blind vantage proves nothing about other pods'
    # tables — an fqdn-bearing fail line on another remaining pod must
    # still be forgotten before the leave can close.
    export KB_LEAVE_MEMBER_POD_FQDN="vk-s-1.h.ns.svc"
    export ALL_SHARDS_POD_FQDN_LIST_SHARD_S="vk-s-0.h.ns.svc,vk-s-1.h.ns.svc"
    export ALL_SHARDS_POD_FQDN_LIST_SHARD_T="vk-t-0.h.ns.svc"
    mb_calls=$(mktemp)
    shard_vantage() { echo "vk-s-0.h.ns.svc"; }
    node_line_of() { echo ""; }
    build_cli() { _cli=(mock_blind_cli "${1}" "${mb_calls}"); }
    mock_blind_cli() {
      local host="${1}" f="${2}"; shift 2
      case "$*" in
        PING) [ "${host}" = "vk-s-1.h.ns.svc" ] && return 1; echo PONG ;;
        "CLUSTER FORGET"*) echo "FORGET:${host}:${3}" >> "${f}"; echo OK ;;
        "CLUSTER NODES")
          if [ "$(grep -c FORGET "${f}" 2>/dev/null)" -lt 2 ]; then
            printf 'tid2 vk-s-1.h.ns.svc:6379@16379 slave,fail mid1 0 0 5 disconnected\n'
          fi
          printf 'mid1 vk-s-0.h.ns.svc:6379@16379 master - 0 0 5 connected 0-16383\n' ;;
      esac
    }
    When run member_leave
    The status should be success
    The stdout should include "reset, forgotten, absence-proven"
    The contents of file "${mb_calls}" should include "FORGET:vk-s-0.h.ns.svc:tid2"
    The contents of file "${mb_calls}" should include "FORGET:vk-t-0.h.ns.svc:tid2"
  End

  It "catches id-only noaddr residue via the target's own MYID (fqdn check alone would false-close)"
    export KB_LEAVE_MEMBER_POD_FQDN="vk-s-1.h.ns.svc"
    export ALL_SHARDS_POD_FQDN_LIST_SHARD_S="vk-s-0.h.ns.svc,vk-s-1.h.ns.svc"
    mb_calls=$(mktemp)
    shard_vantage() { echo "vk-s-0.h.ns.svc"; }
    node_line_of() { echo ""; }
    build_cli() { _cli=(mock_noaddr_cli "${1}" "${mb_calls}"); }
    mock_noaddr_cli() {
      local host="${1}" f="${2}"; shift 2
      case "$*" in
        PING) echo PONG ;;
        FLUSHALL) echo OK ;;
        "CLUSTER MYID") echo "tid2" ;;
        "CLUSTER RESET HARD") echo OK ;;
        "CLUSTER FORGET"*) echo "FORGET:${host}:${3}" >> "${f}"; echo OK ;;
        "CLUSTER NODES")
          if [ "${host}" = "vk-s-1.h.ns.svc" ]; then
            printf 'tid2 :0@0 myself,slave mid1 0 0 5 connected\n'
          elif [ "$(grep -c FORGET "${f}" 2>/dev/null)" -lt 1 ]; then
            # id-only residue: NO fqdn in the line
            printf 'tid2 :0@0 slave,fail,noaddr mid1 0 0 5 disconnected\n'
            printf 'mid1 vk-s-0.h.ns.svc:6379@16379 master - 0 0 5 connected 0-16383\n'
          else
            printf 'mid1 vk-s-0.h.ns.svc:6379@16379 master - 0 0 5 connected 0-16383\n'
          fi ;;
      esac
    }
    When run member_leave
    The status should be success
    The stdout should include "reset, forgotten, absence-proven"
    The contents of file "${mb_calls}" should include "FORGET:vk-s-0.h.ns.svc:tid2"
  End

  It "refuses to delete a master with no replica to fail over to"
    export KB_LEAVE_MEMBER_POD_FQDN="vk-s-0.h.ns.svc"
    shard_vantage() { echo "vk-s-1.h.ns.svc"; }
    node_line_of() { echo "id0 vk-s-0.h.ns.svc:6379@16379 master - 0 0 5 connected 0-5460"; }
    build_cli() { _cli=(mock_no_slave "${1}"); }
    mock_no_slave() {
      local host="${1}"; shift
      case "$*" in
        "CLUSTER MYID") echo "id0" ;;
        *) printf 'id1 x myself,master - 0 0 5 connected\n' ;;
      esac
    }
    When run member_leave
    The status should be failure
    The stderr should include "phase=leave-orphan-guard"
    The stderr should include "would orphan slots"
  End

  Describe "demote candidate binding (fresh-eyes M3: never fail over a mis-bound replica)"
    # "Any in-shard pod flagged slave" is NOT a promotion candidate: a
    # replica mis-bound to ANOTHER shard's master (an acknowledged
    # reachable state — see ensure_replica_bound's wrong-parent repair)
    # would CLUSTER FAILOVER the WRONG shard. The candidate's myself
    # parent id must equal the leaving master's node id.
    demote_env() {
      export CURRENT_SHARD_POD_FQDN_LIST="vk-s-0.h.ns.svc,vk-s-1.h.ns.svc"
    }
    Before "demote_env"

    It "rejects an in-shard slave that replicates a foreign master (orphan-guard, no failover issued)"
      _fo_calls=$(mktemp)
      build_cli() { _cli=(mock_misbound "${1}" "${_fo_calls}"); }
      mock_misbound() {
        local host="${1}" f="${2}"; shift 2
        case "$*" in
          "CLUSTER MYID") echo "leaving-id" ;;
          "CLUSTER FAILOVER") echo "FAILOVER:${host}" >> "${f}"; echo OK ;;
          "CLUSTER NODES") printf 'cid1 %s:6379@16379 myself,slave FOREIGN-master-id 0 0 5 connected\n' "${host}" ;;
        esac
      }
      When call demote_master_before_leave "vk-s-1.h.ns.svc" "vk-s-0.h.ns.svc"
      The status should be failure
      The stderr should include "phase=leave-orphan-guard"
      The stderr should include "no in-shard replica of it"
      The contents of file "${_fo_calls}" should equal ""
    End

    It "promotes the replica that actually replicates the leaving master"
      _fo_calls=$(mktemp)
      shard_master_line() { echo "cid1 vk-s-1.h.ns.svc:6379@16379 master - 0 0 5 connected 0-5460"; }
      build_cli() { _cli=(mock_bound "${1}" "${_fo_calls}"); }
      mock_bound() {
        local host="${1}" f="${2}"; shift 2
        case "$*" in
          "CLUSTER MYID") echo "leaving-id" ;;
          "CLUSTER FAILOVER") echo "FAILOVER:${host}" >> "${f}"; echo OK ;;
          "CLUSTER NODES") printf 'cid1 %s:6379@16379 myself,slave leaving-id 0 0 5 connected\n' "${host}" ;;
        esac
      }
      When call demote_master_before_leave "vk-s-1.h.ns.svc" "vk-s-0.h.ns.svc"
      The status should be success
      The stdout should include "mastership moved to vk-s-1.h.ns.svc"
      The contents of file "${_fo_calls}" should include "FAILOVER:vk-s-1.h.ns.svc"
    End

    It "defers retry-safe when the leaving master's MYID is unreadable"
      build_cli() { _cli=(mock_mute); }
      mock_mute() { printf ''; }
      When call demote_master_before_leave "vk-s-1.h.ns.svc" "vk-s-0.h.ns.svc"
      The status should be failure
      The stderr should include "phase=leave-myid"
      The stderr should include "retry_safe=yes"
    End
  End

  Describe "roster env contract in purge (fresh-eyes M1)"
    roster_purge_clean() {
      unset ALL_SHARDS_POD_FQDN_LIST_SHARD_S ALL_SHARDS_POD_FQDN_LIST_SHARD_T
    }
    After "roster_purge_clean"

    It "hard-fails the leave when a roster var is empty (silent truncation would weaken the FORGET sweep)"
      export KB_LEAVE_MEMBER_POD_FQDN="vk-s-1.h.ns.svc"
      export ALL_SHARDS_POD_FQDN_LIST_SHARD_S="vk-s-0.h.ns.svc,vk-s-1.h.ns.svc"
      export ALL_SHARDS_POD_FQDN_LIST_SHARD_T=""
      shard_vantage() { echo "vk-s-0.h.ns.svc"; }
      node_line_of() { echo ""; }
      build_cli() { _cli=(mock_pong_only); }
      mock_pong_only() { echo PONG; }
      When run member_leave
      The status should be failure
      The stderr should include "ALL_SHARDS_POD_FQDN_LIST_SHARD_T is empty"
      The stderr should include "retry_safe=no"
    End
  End

  Describe "member_join existing-node argument (fresh-eyes minor: no address parsing)"
    It "passes the vantage FQDN to add-node — never an address parsed from CLUSTER NODES (IPv6-safe)"
      export KB_JOIN_MEMBER_POD_FQDN="vk-s-1.h.ns.svc"
      _add_calls=$(mktemp)
      _join_marker=$(mktemp -u)
      shard_vantage() { echo "vk-s-0.h.ns.svc"; }
      # master announces an IPv6 address: the old parse (cut -d: -f1)
      # would have mangled it to "2001"
      shard_master_line() { echo "mid1 2001:db8::5:6379@16379 master - 0 0 5 connected 0-16383"; }
      node_line_of() { echo ""; }
      join_confirmed() {
        if [ -e "${_join_marker}" ]; then return 0; fi
        touch "${_join_marker}"
        return 1
      }
      build_cluster_cli() { _ccli=(mock_addnode "${_add_calls}"); }
      mock_addnode() { local f="${1}"; shift; echo "ADDNODE $*" >> "${f}"; echo OK; }
      When run member_join
      The status should be success
      The stdout should include "joined shard as replica"
      The contents of file "${_add_calls}" should include "vk-s-0.h.ns.svc:6379"
      The contents of file "${_add_calls}" should not include "2001:6379"
    End
  End

  It "leaves via reset+FORGET-sweep+absence, never del-node (r4 CT06 family)"
    export KB_LEAVE_MEMBER_POD_FQDN="vk-s-1.h.ns.svc"
    export ALL_SHARDS_POD_FQDN_LIST_SHARD_S="vk-s-0.h.ns.svc,vk-s-1.h.ns.svc"
    export ALL_SHARDS_POD_FQDN_LIST_SHARD_T="vk-t-0.h.ns.svc"
    mb_calls=$(mktemp)
    shard_vantage() { echo "vk-s-0.h.ns.svc"; }
    node_line_of() { echo "tid2 vk-s-1.h.ns.svc:6379@16379 slave mid1 0 0 5 connected"; }
    build_cli() { _cli=(mock_leave_cli "${1}" "${mb_calls}"); }
    mock_leave_cli() {
      local host="${1}" f="${2}"; shift 2
      case "$*" in
        PING) echo PONG ;;
        FLUSHALL) echo OK ;;
        "CLUSTER MYID") echo "tid2" ;;
        "CLUSTER RESET HARD") echo "RESET:${host}" >> "${f}"; echo OK ;;
        "CLUSTER FORGET"*) echo "FORGET:${host}:${3}" >> "${f}"; echo OK ;;
        "CLUSTER NODES")
          if [ "${host}" = "vk-s-1.h.ns.svc" ]; then
            printf 'tid2 vk-s-1.h.ns.svc:6379@16379 myself,slave mid1 0 0 5 connected\n'
          elif [ "$(grep -c FORGET "${f}" 2>/dev/null)" -lt 2 ]; then
            printf 'tid2 vk-s-1.h.ns.svc:6379@16379 slave mid1 0 0 5 connected\n'
            printf 'mid1 vk-s-0.h.ns.svc:6379@16379 master - 0 0 5 connected 0-16383\n'
          else
            printf 'mid1 vk-s-0.h.ns.svc:6379@16379 master - 0 0 5 connected 0-16383\n'
          fi ;;
      esac
    }
    When run member_leave
    The status should be success
    The stdout should include "reset, forgotten, absence-proven"
    The contents of file "${mb_calls}" should include "RESET:vk-s-1.h.ns.svc"
    The contents of file "${mb_calls}" should include "FORGET:vk-s-0.h.ns.svc:tid2"
    The contents of file "${mb_calls}" should include "FORGET:vk-t-0.h.ns.svc:tid2"
  End

  It "cannot close a leave while any remaining pod still sees the member"
    export KB_LEAVE_MEMBER_POD_FQDN="vk-s-1.h.ns.svc"
    export ALL_SHARDS_POD_FQDN_LIST_SHARD_S="vk-s-0.h.ns.svc,vk-s-1.h.ns.svc"
    shard_vantage() { echo "vk-s-0.h.ns.svc"; }
    node_line_of() { echo "tid2 vk-s-1.h.ns.svc:6379@16379 slave,fail mid1 0 0 5 disconnected"; }
    build_cli() { _cli=(mock_stuck "${1}"); }
    mock_stuck() {
      local host="${1}"; shift
      case "$*" in
        PING) echo PONG ;;
        "CLUSTER MYID") echo "tid2" ;;
        "CLUSTER NODES")
          if [ "${host}" = "vk-s-1.h.ns.svc" ]; then
            printf 'tid2 vk-s-1.h.ns.svc:6379@16379 myself,slave mid1 0 0 5 connected\n'
          else
            printf 'tid2 vk-s-1.h.ns.svc:6379@16379 slave,fail mid1 0 0 5 disconnected\n'
          fi ;;
        *) echo OK ;;
      esac
    }
    When run member_leave
    The status should be failure
    The stderr should include "phase=leave-confirm"
    The stderr should include "retry_safe=yes"
  End

  It "excludes the join target from the vantage and requires a formed member"
    export KB_JOIN_MEMBER_POD_FQDN="vk-s-1.h.ns.svc"
    # Only the target itself would answer: vantage must refuse it and fail.
    build_cli() {
      case "$1" in
        vk-s-1.h.ns.svc) _cli=(mock_up) ;;
        *) _cli=(mock_down) ;;
      esac
    }
    mock_up() { case "$1" in PING) echo PONG;; *) echo "cluster_state:ok";; esac; }
    mock_down() { return 1; }
    When run member_join
    The status should be failure
    The stderr should include "phase=vantage"
  End

  It "does not confirm a join on visibility alone (must be replica of this master)"
    export KB_JOIN_MEMBER_POD_FQDN="vk-s-1.h.ns.svc"
    shard_vantage() { echo "vk-s-0.h.ns.svc"; }
    shard_master_line() { echo "mid1 vk-s-0.h.ns.svc:6379@16379 myself,master - 0 0 5 connected 0-5460"; }
    # target visible but flagged master of nothing (not slave of mid1)
    node_line_of() { echo "tid2 vk-s-1.h.ns.svc:6379@16379 master - 0 0 6 connected"; }
    build_cluster_cli() { _ccli=(mock_add); }
    mock_add() { echo "added"; }
    When run member_join
    The status should be failure
    The stderr should include "phase=join-confirm"
  End

  It "requires the join target env"
    unset KB_JOIN_MEMBER_POD_FQDN
    When run member_join
    The status should be failure
    The stderr should include "phase=env-contract"
    The stderr should include "KB_JOIN_MEMBER_POD_FQDN is required"
  End
End
