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
      The stderr should include "retry_safe=no"
      The stderr should include "no fallback"
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
      The stderr should include "phase=shard-roster"
      The stderr should include "duplicate shard name"
    End

    It "hard-fails on an empty entry"
      export ALL_SHARDS_COMPONENT_SHORT_NAMES=":,shard-bbb:shard-bbb"
      When call coordinator_shard
      The status should be failure
      The stderr should include "phase=shard-roster"
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
      The stderr should include "phase=formation-wait-shards"
      The stderr should include "retry_safe=yes"
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
      The stderr should include "phase=formation-wait-primaries"
      The stderr should include "retry_safe=yes"
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
      The stderr should include "phase=remove-slots-nonzero"
      The stderr should include "retry_safe=yes"
      The stderr should include "still owns 5 slots"
      The stdout should include ""
    End
  End
  Describe "drive_shard_completion() — r3 CT05 livelock fix"
    # r3 live evidence: after one failed replica attach, the old
    # present-branch only observed ("shard present but full membership
    # not yet complete") and never re-drove the attach. The driver must
    # ACT from any partial state, not defer.

    It "drives the missing replica attach when the shard master is present with slots (livelock regression)"
      node_id_of() { echo "mid-new"; }
      slots_owned_by() { echo "120"; }
      ensure_replica_bound() { echo "DRIVE ${2}"; }
      shard_membership_bound() { return 0; }
      all_expected_members_present() { return 0; }
      build_cli() { _cli=(true); }
      When call drive_shard_completion "via.h" "vk-shard-abc-0.h.ns.svc"
      The status should be success
      The stdout should include "DRIVE vk-shard-abc-1.h.ns.svc"
      The stdout should include "membership bound"
    End

    It "re-drives rebalance when the shard master owns zero slots"
      node_id_of() { echo "mid-new"; }
      # command-substitution runs the stub in a subshell, so state must
      # live in a file: first call reports 0 slots, later calls 200.
      _slots_marker=$(mktemp)
      slots_owned_by() {
        if [ -s "${_slots_marker}" ]; then echo "200"; else echo seen > "${_slots_marker}"; echo "0"; fi
      }
      build_cluster_cli() { _ccli=(mock_reb); }
      mock_reb() { echo "rebalanced"; }
      ensure_replica_bound() { return 0; }
      shard_membership_bound() { return 0; }
      all_expected_members_present() { return 0; }
      build_cli() { _cli=(true); }
      When call drive_shard_completion "via.h" "vk-shard-abc-0.h.ns.svc"
      The status should be success
      The stdout should include "complete: 200 slots"
    End

    It "classifies a rebalance failure as retry-safe (re-entry re-drives)"
      node_id_of() { echo "mid-new"; }
      slots_owned_by() { echo "0"; }
      build_cluster_cli() { _ccli=(mock_reb_fail); }
      mock_reb_fail() { echo "[ERR] Nodes don't agree about configuration!" >&2; return 1; }
      When call drive_shard_completion "via.h" "vk-shard-abc-0.h.ns.svc"
      The status should be failure
      The stderr should include "phase=join-rebalance"
      The stderr should include "retry_safe=yes"
    End

    It "classifies a transient replica add-node preflight failure as retry-safe"
      build_cli() { _cli=(mock_empty_nodes); }
      mock_empty_nodes() { printf ''; }
      build_cluster_cli() { _ccli=(mock_add_fail); }
      mock_add_fail() { echo "[ERR] Nodes don't agree about configuration!" >&2; return 1; }
      When call ensure_replica_bound "via.h" "vk-shard-abc-1.h.ns.svc" "mid-new" "shard-abc"
      The status should be failure
      The stderr should include "phase=attach-add-node"
      The stderr should include "retry_safe=yes"
    End

    It "routes the present-branch of verify_or_join into the driver (no observe-only dead end)"
      each_shard_fqdn_list() {
        printf 'SHARD_ABC vk-shard-abc-0.h.ns.svc,vk-shard-abc-1.h.ns.svc\n'
      }
      cluster_state_of() { echo "ok"; }
      build_cli() { _cli=(mock_nodes_present); }
      mock_nodes_present() { printf 'mid-new vk-shard-abc-0.h.ns.svc:6379@16379 master - 0 0 1 connected 0-5460\n'; }
      drive_shard_completion() { echo "DRIVEN via=${1} self=${2}"; }
      When call verify_or_join
      The status should be success
      The stdout should include "DRIVEN"
      The stdout should include "self=vk-shard-abc-0.h.ns.svc"
    End
  End

  Describe "open-slot repair — r7 CT05 interrupted migration"
    # r7 live evidence: slot 5517 stuck in importing/migrating (rebalance
    # interrupted, e.g. by the action runtime clamp) blocks every later
    # add-node/rebalance preflight, and the engine never self-heals it.
    # The driver must repair open slots BEFORE trusting slot ownership.

    It "repairs open slots before continuing the join (own>0 must not skip past them)"
      _fix_marker=$(mktemp)
      node_id_of() { echo "mid-new"; }
      slots_owned_by() { echo "120"; }
      build_cluster_cli() { _ccli=(mock_checkfix "${_fix_marker}"); }
      mock_checkfix() {
        local f="${1}"; shift
        case "$*" in
          *check*)
            if [ -s "${f}" ]; then echo "[OK] All 16384 slots covered."; else
              echo "[WARNING] The following slots are open: 5517"
            fi ;;
          *fix*) echo "fixed" > "${f}"; echo "Fixing open slot 5517" ;;
        esac
      }
      ensure_replica_bound() { return 0; }
      shard_membership_bound() { return 0; }
      all_expected_members_present() { return 0; }
      build_cli() { _cli=(true); }
      When call drive_shard_completion "via.h" "vk-shard-abc-0.h.ns.svc"
      The status should be success
      The stdout should include "repaired open slots"
      The stdout should include "membership bound"
    End

    It "defers retry-safe when the fix cannot close the open slots"
      node_id_of() { echo "mid-new"; }
      build_cluster_cli() { _ccli=(mock_stuck_fix); }
      mock_stuck_fix() {
        case "$*" in
          *check*) echo "[WARNING] Node x has slots in importing state 5517." ;;
          *fix*) echo "tried" ;;
        esac
      }
      When call drive_shard_completion "via.h" "vk-shard-abc-0.h.ns.svc"
      The status should be failure
      The stderr should include "phase=join-fix"
      The stderr should include "retry_safe=yes"
    End

    It "gates the shard-remove drain on open-slot repair (zero-proof needs clean state)"
      validate_manage_env() { return 0; }
      each_shard_fqdn_list() { printf 'SHARD_DEF vk-shard-def-0.h.ns.svc\n'; }
      cluster_state_of() { echo "ok"; }
      shard_master_id_via() { echo "master-id-1"; }
      open_slots_present() { return 0; }
      repair_open_slots() { echo REPAIR-CALLED >&2; return 1; }
      When run shard_remove
      The status should be failure
      The stderr should include "REPAIR-CALLED"
    End
  End

  Describe "purge_shard_from_cluster() — r4 CT06 residue-free removal"
    # r4 CT06 live evidence: del-node's SHUTDOWN let the removed pods
    # restart with old nodes.conf and re-handshake back as fail entries.
    # The purge must FORGET old ids on EVERY remaining node and prove
    # absence before rc=0.
    purge_env() {
      export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-def"
      export CURRENT_SHARD_POD_FQDN_LIST="vk-def-0.h,vk-def-1.h"
      calls=$(mktemp)
      each_shard_fqdn_list() {
        printf 'SHARD_ABC vk-abc-0.h,vk-abc-1.h\n'
        printf 'SHARD_DEF vk-def-0.h,vk-def-1.h\n'
      }
      build_cli() { _cli=(mock_cli "${1}" "${calls}"); }
      # CI runs on Linux where getent EXISTS and fails for these fake
      # hostnames — without this stub every roster host would be
      # filtered as "departed" (macOS has no getent, hiding the issue).
      host_resolves() { return 0; }
    }
    Before "purge_env"

    # mock: NODES shows the removed shard's fail residue until all 4
    # FORGETs (2 remaining hosts x 2 old ids) have been recorded.
    mock_cli() {
      local host="${1}" f="${2}"; shift 2
      case "$*" in
        PING) echo PONG ;;
        FLUSHALL) echo OK ;;
        "CLUSTER RESET HARD") echo "RESET:${host}" >> "${f}"; echo OK ;;
        "CLUSTER FORGET"*) echo "FORGET:${host}:${3}" >> "${f}"; echo OK ;;
        "CLUSTER NODES")
          printf 'live1 vk-abc-0.h:6379@16379 master - 0 0 1 connected 0-16383\n'
          if [ "$(grep -c FORGET "${f}" 2>/dev/null)" -lt 4 ]; then
            printf 'dead1 vk-def-0.h:6379@16379 master,fail - 0 0 2 disconnected\n'
            printf 'dead2 vk-def-1.h:6379@16379 slave,fail dead1 0 0 2 disconnected\n'
          fi ;;
      esac
    }

    It "resets leaving pods, FORGETs old ids on every remaining pod, proves absence"
      When call purge_shard_from_cluster
      The status should be success
      The contents of file "${calls}" should include "RESET:vk-def-0.h"
      The contents of file "${calls}" should include "RESET:vk-def-1.h"
      The contents of file "${calls}" should include "FORGET:vk-abc-0.h:dead1"
      The contents of file "${calls}" should include "FORGET:vk-abc-0.h:dead2"
      The contents of file "${calls}" should include "FORGET:vk-abc-1.h:dead1"
      The contents of file "${calls}" should include "FORGET:vk-abc-1.h:dead2"
    End

    It "unions old ids across ALL remaining pods (residue known to one pod only)"
      # review blocker: collecting ids from a single vantage misses a
      # residue line that only one remaining pod still holds.
      mock_cli() {
        local host="${1}" f="${2}"; shift 2
        case "$*" in
          PING) echo PONG ;;
          FLUSHALL|"CLUSTER RESET HARD") echo OK ;;
          "CLUSTER MYID") echo "" ;;
          "CLUSTER FORGET"*) echo "FORGET:${host}:${3}" >> "${f}"; echo OK ;;
          "CLUSTER NODES")
            printf 'live1 vk-abc-0.h:6379@16379 master - 0 0 1 connected 0-16383\n'
            # only the SECOND remaining pod still sees the residue
            if [ "${host}" = "vk-abc-1.h" ] && [ "$(grep -c FORGET "${f}" 2>/dev/null)" -lt 2 ]; then
              printf 'dead2 vk-def-1.h:6379@16379 slave,fail dead1 0 0 2 disconnected\n'
            fi ;;
        esac
      }
      When call purge_shard_from_cluster
      The status should be success
      The contents of file "${calls}" should include "FORGET:vk-abc-0.h:dead2"
      The contents of file "${calls}" should include "FORGET:vk-abc-1.h:dead2"
    End

    It "skips a concurrently-departed sibling shard (DNS gone) and still purges via live members (r9 CT12)"
      # 5->3 scale-in: shard-def and shard-ghi leave in the same batch.
      # From shard-def's action, shard-ghi's pods are roster-listed but
      # their DNS is already gone — they must be skipped as vantage, not
      # deferred on forever.
      each_shard_fqdn_list() {
        printf 'SHARD_ABC vk-abc-0.h,vk-abc-1.h\n'
        printf 'SHARD_DEF vk-def-0.h,vk-def-1.h\n'
        printf 'SHARD_GHI vk-ghi-0.h,vk-ghi-1.h\n'
      }
      host_resolves() { case "${1}" in vk-ghi-*) return 1 ;; *) return 0 ;; esac; }
      When call purge_shard_from_cluster
      The status should be success
      The stdout should include "vk-ghi-0.h no longer resolves"
      The contents of file "${calls}" should include "FORGET:vk-abc-0.h:dead1"
      The contents of file "${calls}" should include "FORGET:vk-abc-1.h:dead1"
      The contents of file "${calls}" should not include "FORGET:vk-ghi"
    End

    It "still defers when a resolvable live member cannot be reached (connection failure is NOT departure)"
      host_resolves() { return 0; }
      mock_cli() {
        local host="${1}" f="${2}"; shift 2
        case "$*" in
          PING) echo PONG ;;
          FLUSHALL|"CLUSTER RESET HARD") echo OK ;;
          "CLUSTER FORGET"*)
            if [ "${host}" = "vk-abc-1.h" ]; then echo "Could not connect to Valkey at vk-abc-1.h:6379: Connection refused"; else echo OK; fi ;;
          "CLUSTER NODES")
            printf 'live1 vk-abc-0.h:6379@16379 master - 0 0 1 connected 0-16383\n'
            printf 'dead1 vk-def-0.h:6379@16379 master,fail - 0 0 2 disconnected\n' ;;
        esac
      }
      When call purge_shard_from_cluster
      The status should be failure
      The stderr should include "phase=remove-forget"
      The stderr should include "retry_safe=yes"
    End

    It "cannot succeed while resurrection residue persists (retry-safe defer)"
      mock_cli() {
        local host="${1}" f="${2}"; shift 2
        case "$*" in
          PING) echo PONG ;;
          FLUSHALL|"CLUSTER RESET HARD"|"CLUSTER FORGET"*) echo OK ;;
          "CLUSTER NODES")
            printf 'live1 vk-abc-0.h:6379@16379 master - 0 0 1 connected 0-16383\n'
            printf 'dead1 vk-def-0.h:6379@16379 master,fail - 0 0 2 disconnected\n' ;;
        esac
      }
      When call purge_shard_from_cluster
      The status should be failure
      The stderr should include "phase=remove-residue"
      The stderr should include "retry_safe=yes"
    End

    It "treats FORGET 'Unknown node' as already forgotten"
      _nodes_reads=$(mktemp)
      mock_cli() {
        local host="${1}" f="${2}"; shift 2
        case "$*" in
          PING) echo PONG ;;
          FLUSHALL|"CLUSTER RESET HARD") echo OK ;;
          "CLUSTER FORGET"*) echo "ERR Unknown node ${3}" ;;
          "CLUSTER NODES")
            printf 'live1 vk-abc-0.h:6379@16379 master - 0 0 1 connected 0-16383\n'
            if [ ! -s "${_nodes_reads}" ]; then
              echo seen > "${_nodes_reads}"
              printf 'dead1 vk-def-0.h:6379@16379 master,fail - 0 0 2 disconnected\n'
            fi ;;
        esac
      }
      When call purge_shard_from_cluster
      The status should be success
    End

    It "still purges on the already-removed path (no silent rc=0 over residue)"
      # shard_remove with no master in view must route through the purge,
      # not exit 0 blindly — pin by proving purge failure propagates.
      validate_manage_env() { return 0; }
      cluster_state_of() { echo "ok"; }
      shard_master_id_via() { echo ""; }
      purge_shard_from_cluster() { echo PURGE-CALLED; return 1; }
      When run shard_remove
      The status should be failure
      The stdout should include "PURGE-CALLED"
    End
  End

  Describe "shard_membership_bound()"
    nodes3ok='m1 vk-s-a-0.h:6379@16379 master - 0 0 1 connected 0-5460
s1 vk-s-a-1.h:6379@16379 slave m1 0 0 1 connected'
    It "passes when the shard has one master and slaves bound to it"
      When call shard_membership_bound "${nodes3ok}" "SHARD_A" "vk-s-a-0.h,vk-s-a-1.h"
      The status should be success
    End

    It "fails when a non-first pod is a stray master"
      nodes_bad='m1 vk-s-a-0.h:6379@16379 master - 0 0 1 connected 0-5460
m2 vk-s-a-1.h:6379@16379 master - 0 0 2 connected'
      When call shard_membership_bound "${nodes_bad}" "SHARD_A" "vk-s-a-0.h,vk-s-a-1.h"
      The status should be failure
      The stdout should include "2 in-shard master(s), expected exactly 1"
    End

    It "fails when a pod replicates a foreign master"
      nodes_bad2='m1 vk-s-a-0.h:6379@16379 master - 0 0 1 connected 0-5460
s1 vk-s-a-1.h:6379@16379 slave OTHER 0 0 1 connected'
      When call shard_membership_bound "${nodes_bad2}" "SHARD_A" "vk-s-a-0.h,vk-s-a-1.h"
      The status should be failure
      The stdout should include "replicates OTHER, not this shard's master m1"
    End
  End
End
