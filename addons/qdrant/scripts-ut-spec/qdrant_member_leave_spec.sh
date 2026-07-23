# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "qdrant_member_leave_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Qdrant Member Leave Bash Script Tests"
  export QDRANT_MEMBER_LEAVE_UNIT_TEST=true
  Include ../scripts/qdrant-member-leave.sh

  cleanup() {
    unset QDRANT_MEMBER_LEAVE_UNIT_TEST KB_LEAVE_MEMBER_POD_NAME
    unset qdrant_member_leave_deadline qdrant_member_leave_phase_deadline
  }
  After "cleanup"

  Describe "peer pod URI matching"
    cluster_info='{"result":{"peers":{"1":{"uri":"http://qdrant-cluster-qdrant-1.qdrant-cluster-qdrant-headless.default.svc.cluster.local:6335/"},"10":{"uri":"http://qdrant-cluster-qdrant-10.qdrant-cluster-qdrant-headless.default.svc.cluster.local:6335/"}}}}'

    It "matches the exact pod host and does not also match ordinal 10"
      When call qdrant_peer_id_for_pod "$cluster_info" "qdrant-cluster-qdrant-1"
      The status should be success
      The output should eq "1"
    End

    It "keeps ordinal 10 as a surviving control endpoint when ordinal 1 leaves"
      KB_LEAVE_MEMBER_POD_NAME="qdrant-cluster-qdrant-1"
      When call qdrant_control_uris_from_cluster_info "$cluster_info"
      The status should be success
      The output should eq "http://qdrant-cluster-qdrant-10.qdrant-cluster-qdrant-headless.default.svc.cluster.local:6333"
    End
  End

  Describe "qdrant_select_target_peer_id_for_shard()"
    cluster_info='{"result":{"peers":{"1":{"uri":"http://qdrant-0:6335/"},"2":{"uri":"http://qdrant-1:6335/"},"3":{"uri":"http://qdrant-2:6335/"}}}}'

    It "uses the raft leader when it does not already own the shard"
      collection_info='{"result":{"peer_id":3,"local_shards":[{"shard_id":8}],"remote_shards":[{"shard_id":7,"peer_id":1}],"shard_transfers":[]}}'
      When call qdrant_select_target_peer_id_for_shard "$cluster_info" "$collection_info" "1" "2" "7"
      The status should be success
      The output should eq "2"
    End

    It "skips a leader that owns the shard as a remote replica"
      collection_info='{"result":{"peer_id":3,"local_shards":[{"shard_id":8}],"remote_shards":[{"shard_id":7,"peer_id":1},{"shard_id":7,"peer_id":2}],"shard_transfers":[]}}'
      When call qdrant_select_target_peer_id_for_shard "$cluster_info" "$collection_info" "1" "2" "7"
      The status should be success
      The output should eq "3"
    End

    It "skips a leader that owns the shard locally"
      collection_info='{"result":{"peer_id":2,"local_shards":[{"shard_id":7}],"remote_shards":[{"shard_id":7,"peer_id":1}],"shard_transfers":[]}}'
      When call qdrant_select_target_peer_id_for_shard "$cluster_info" "$collection_info" "1" "2" "7"
      The status should be success
      The output should eq "3"
    End

    It "skips an in-flight transfer destination for the shard"
      collection_info='{"result":{"peer_id":3,"local_shards":[{"shard_id":8}],"remote_shards":[{"shard_id":7,"peer_id":1}],"shard_transfers":[{"shard_id":7,"from":3,"to":2}]}}'
      When call qdrant_select_target_peer_id_for_shard "$cluster_info" "$collection_info" "1" "2" "7"
      The status should be success
      The output should eq "3"
    End

    It "returns empty when every surviving peer already owns the shard"
      collection_info='{"result":{"peer_id":2,"local_shards":[{"shard_id":7}],"remote_shards":[{"shard_id":7,"peer_id":1},{"shard_id":7,"peer_id":3}],"shard_transfers":[]}}'
      When call qdrant_select_target_peer_id_for_shard "$cluster_info" "$collection_info" "1" "2" "7"
      The status should be success
      The output should eq ""
    End

    It "fails closed when a local shard has no serving peer identity"
      collection_info='{"result":{"local_shards":[{"shard_id":7}],"remote_shards":[{"shard_id":7,"peer_id":1}],"shard_transfers":[]}}'
      When call qdrant_select_target_peer_id_for_shard "$cluster_info" "$collection_info" "1" "2" "7"
      The status should be failure
      The stderr should include "local shard without peer_id"
    End
  End

  Describe "memberLeave action-wide deadline"
    cleanup_deadline() {
      unset QDRANT_MEMBER_LEAVE_ACTION_SECONDS QDRANT_MEMBER_LEAVE_CURL_TIMEOUT
      unset QDRANT_MEMBER_LEAVE_WAIT_SECONDS QDRANT_MEMBER_LEAVE_FINALIZE_SECONDS
      unset qdrant_member_leave_deadline qdrant_member_leave_phase_deadline
    }
    After "cleanup_deadline"

    It "starts one shared deadline before preflight work"
      SECONDS=7
      QDRANT_MEMBER_LEAVE_ACTION_SECONDS=50
      When call qdrant_initialize_member_leave_deadline
      The status should be success
      The variable qdrant_member_leave_deadline should eq 57
    End

    It "rejects a script budget that consumes the kbagent safety buffer"
      QDRANT_MEMBER_LEAVE_ACTION_SECONDS=51
      When call qdrant_initialize_member_leave_deadline
      The status should be failure
      The stderr should include "between 1 and 50"
    End

    It "reserves finalization time inside the shared action budget"
      SECONDS=10
      qdrant_member_leave_deadline=60
      QDRANT_MEMBER_LEAVE_WAIT_SECONDS=100
      QDRANT_MEMBER_LEAVE_FINALIZE_SECONDS=10

      When call qdrant_initialize_member_leave_drain_deadline
      The status should be success
      The variable qdrant_member_leave_phase_deadline should eq 50
    End

    It "clips each curl call to the remaining action budget"
      SECONDS=10
      qdrant_member_leave_deadline=13
      QDRANT_MEMBER_LEAVE_CURL_TIMEOUT=5
      qdrant_curl() {
        printf '%s\n' "$*"
      }

      When call qdrant_member_leave_curl "http://control/cluster"
      The status should be success
      The output should eq "-sf --max-time 3 http://control/cluster"
    End

    It "fails before a curl when the shared action budget is exhausted"
      SECONDS=10
      qdrant_member_leave_deadline=10
      qdrant_curl() {
        echo "unexpected qdrant_curl call" >&2
        return 99
      }

      When call qdrant_member_leave_curl "http://control/cluster"
      The status should be failure
      The stderr should include "memberLeave action budget exhausted"
      The stderr should not include "unexpected qdrant_curl call"
    End

    It "does not reset the deadline after preflight"
      qdrant_member_leave_deadline=12345
      qdrant_move_shards() {
        echo "deadline=${qdrant_member_leave_deadline}"
      }
      qdrant_remove_peer() {
        return 0
      }

      When call qdrant_leave_member
      The status should be success
      The output should include "deadline=12345"
    End
  End

  Describe "memberLeave replay safety"
    setup_replay_state() {
      export JQ="${JQ:-jq}"
      control_uri="http://control"
      leave_peer_uri="http://leaving"
      leave_peer_id="1"
      leader_peer_id="2"
      cluster_info='{"result":{"peers":{"1":{"uri":"http://qdrant-0:6335/"},"2":{"uri":"http://qdrant-1:6335/"},"3":{"uri":"http://qdrant-2:6335/"}}}}'
      qdrant_member_leave_deadline=$((SECONDS + 50))
    }
    Before "setup_replay_state"

    It "does not submit a duplicate move when the shard transfer already exists"
      moving_info='{"result":{"local_shards":[],"remote_shards":[{"shard_id":7,"peer_id":1}],"shard_transfers":[{"shard_id":7,"from":1,"to":2}]}}'
      qdrant_curl() {
        echo "unexpected qdrant_curl call" >&2
        return 99
      }

      When call qdrant_submit_shard_move_if_needed "demo" "7" "$moving_info"
      The status should be success
      The output should include "already moving"
    End

    It "treats a failed move submit as success when replay sees the transfer in progress"
      initial_info='{"result":{"local_shards":[],"remote_shards":[{"shard_id":7,"peer_id":1}],"shard_transfers":[]}}'
      qdrant_curl() {
        last_arg="${*: -1}"
        case "$last_arg" in
          "http://control/collections/demo/cluster")
            if [ "$1" = "-sf" ] && [ "$4" = "-X" ]; then
              return 1
            fi
            echo '{"result":{"local_shards":[],"remote_shards":[{"shard_id":7,"peer_id":1}],"shard_transfers":[{"shard_id":7,"from":1,"to":2}]}}'
            ;;
          *)
            return 1
            ;;
        esac
      }

      When call qdrant_submit_shard_move_if_needed "demo" "7" "$initial_info"
      The status should be success
      The output should include "already moving after failed submit"
    End

    It "submits the move to an unused peer instead of an existing replica"
      replicated_info='{"result":{"peer_id":3,"local_shards":[{"shard_id":8}],"remote_shards":[{"shard_id":7,"peer_id":1},{"shard_id":7,"peer_id":2}],"shard_transfers":[]}}'
      qdrant_curl() {
        printf '%s\n' "$*"
      }

      When call qdrant_submit_shard_move_if_needed "demo" "7" "$replicated_info"
      The status should be success
      The output should include '"to_peer_id":3'
      The output should not include '"to_peer_id":2'
    End

    It "does not submit a move when every surviving peer already owns the shard"
      replicated_info='{"result":{"peer_id":2,"local_shards":[{"shard_id":7}],"remote_shards":[{"shard_id":7,"peer_id":1},{"shard_id":7,"peer_id":3}],"shard_transfers":[]}}'
      qdrant_curl() {
        echo "unexpected qdrant_curl call" >&2
        return 99
      }

      When call qdrant_submit_shard_move_if_needed "demo" "7" "$replicated_info"
      The status should be failure
      The stderr should include "refusing to reduce replica count"
      The stderr should not include "unexpected qdrant_curl call"
    End

    It "discovers remaining shards from the control endpoint when the leaving endpoint is unavailable"
      qdrant_curl() {
        last_arg="${*: -1}"
        case "$last_arg" in
          "http://leaving/collections/demo/cluster")
            return 7
            ;;
          "http://control/collections/demo/cluster")
            echo '{"result":{"local_shards":[],"remote_shards":[{"shard_id":7,"peer_id":1},{"shard_id":8,"peer_id":2}],"shard_transfers":[]}}'
            ;;
          *)
            return 1
            ;;
        esac
      }

      When call qdrant_leaving_shards_for_collection "demo"
      The status should be success
      The output should include "7"
      The stderr should include "leaving peer endpoint unavailable"
    End

    It "treats peer removal as successful when the peer is absent after a failed delete response"
      qdrant_remove_peer_deleted_marker="$(mktemp)"
      rm -f "$qdrant_remove_peer_deleted_marker"
      qdrant_curl() {
        last_arg="${*: -1}"
        case "$last_arg" in
          "http://control/cluster")
            if [ -f "$qdrant_remove_peer_deleted_marker" ]; then
              echo '{"result":{"peers":{"2":{"uri":"http://qdrant-1:6335/"}}}}'
            else
              echo '{"result":{"peers":{"1":{"uri":"http://qdrant-0:6335/"},"2":{"uri":"http://qdrant-1:6335/"}}}}'
            fi
            ;;
          "http://control/cluster/peer/1")
            touch "$qdrant_remove_peer_deleted_marker"
            return 1
            ;;
          *)
            return 1
            ;;
        esac
      }

      When call qdrant_remove_peer
      The status should be success
      The output should include "absent after failed delete"
    End

    It "returns failure when shards are not drained within the bounded action window"
      export QDRANT_MEMBER_LEAVE_WAIT_SECONDS=0
      qdrant_member_leave_deadline="$SECONDS"
      qdrant_curl() {
        last_arg="${*: -1}"
        case "$last_arg" in
          "http://control/collections/demo/cluster")
            echo '{"result":{"local_shards":[],"remote_shards":[{"shard_id":7,"peer_id":1}],"shard_transfers":[{"shard_id":7,"from":1,"to":2}]}}'
            ;;
          *)
            return 1
            ;;
        esac
      }

      When call qdrant_wait_for_collection_drained "demo"
      The status should be failure
      The output should include "timed out waiting"
    End
  End
End
