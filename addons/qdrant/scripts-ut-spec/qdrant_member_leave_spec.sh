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
    unset QDRANT_MEMBER_LEAVE_UNIT_TEST
  }
  After "cleanup"

  Describe "qdrant_select_target_peer_id()"
    cluster_info='{"result":{"peers":{"1":{"uri":"http://qdrant-0:6335/"},"2":{"uri":"http://qdrant-1:6335/"},"3":{"uri":"http://qdrant-2:6335/"}}}}'

    It "keeps the raft leader as the shard target when the leader is not leaving"
      When call qdrant_select_target_peer_id "$cluster_info" "1" "2"
      The status should be success
      The output should eq "2"
    End

    It "selects a surviving peer when the leaving peer is the raft leader"
      When call qdrant_select_target_peer_id "$cluster_info" "1" "1"
      The status should be success
      The output should eq "2"
    End

    It "returns empty when there is no surviving peer"
      single_peer_cluster='{"result":{"peers":{"1":{"uri":"http://qdrant-0:6335/"}}}}'
      When call qdrant_select_target_peer_id "$single_peer_cluster" "1" "1"
      The status should be success
      The output should eq ""
    End
  End

  Describe "memberLeave replay safety"
    setup_replay_state() {
      export JQ="${JQ:-jq}"
      control_uri="http://control"
      leave_peer_uri="http://leaving"
      leave_peer_id="1"
      target_peer_id="2"
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
