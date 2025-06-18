# shellcheck shell=bash
# shellcheck disable=SC2317

Describe "Switchover Script Tests"
  Include ../scripts/switchover.sh

  exec_etcdctl() {
    return 0
  }

  log() { echo "$@"; }
  error_exit() { echo "ERROR: $1" >&2; exit 1; }
  get_pod_endpoint_with_lb() { echo "$3"; }

  BeforeEach "exec_etcdctl" "log" "error_exit" "get_pod_endpoint_with_lb"

  Describe "get_member_and_leader_id()"
    It "returns member and leader IDs"
      exec_etcdctl() {
        echo '"MemberID" : 12345
"Leader" : 67890'
      }
      When call get_member_and_leader_id "test_endpoint"
      The output should equal "12345 67890"
      The status should be success
    End
  End

  Describe "get_current_leader()"
    It "returns current leader endpoint"
      exec_etcdctl() {
        case "$*" in
          *"member list"*) echo "id1, name1, peer1, client1, http://peer1:2379";;
          *"endpoint status"*) echo '"MemberID" : 12345
"Leader" : 12345
"Endpoint" : "http://leader_endpoint:2379"
"MemberID" : 67890
"Leader" : 12345
"Endpoint" : "http://follower_endpoint:2379"';;
        esac
      }
      When call get_current_leader "contact_point"
      The output should equal "http://leader_endpoint:2379"
      The status should be success
    End

    It "fails when no peer endpoints found"
      exec_etcdctl() { echo ""; }
      When call get_current_leader "contact_point"
      The status should be failure
      The stderr should include "No peer endpoints found"
    End
  End

  Describe "switchover_with_candidate()"
    It "does not switch when current leader is the same as candidate"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export KB_SWITCHOVER_CANDIDATE_FQDN="candidate_endpoint.domain"
      export PEER_ENDPOINT=""
      get_current_leader() { echo "candidate_endpoint:2379"; return 0; }
      When call switchover_with_candidate
      The status should be success
      The stdout should include "Current leader is the same as candidate, no need to switch"
    End

    It "switches to the candidate successfully"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export KB_SWITCHOVER_CANDIDATE_FQDN="candidate_endpoint.domain"
      export PEER_ENDPOINT=""
      get_current_leader() { echo "current_endpoint:2379"; return 0; }
      get_member_and_leader_id() { echo "12345 12345"; }
      When call switchover_with_candidate
      The status should be success
      The stdout should include "Switchover to candidate candidate_endpoint.domain completed successfully"
    End

    It "fails to switch to the candidate"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export KB_SWITCHOVER_CANDIDATE_FQDN="candidate_endpoint.domain"
      export PEER_ENDPOINT=""
      get_current_leader() { echo "current_endpoint:2379"; return 0; }
      get_member_and_leader_id() { echo "12345 67890"; }
      When call switchover_with_candidate
      The status should be failure
      The stderr should include "Switchover failed - candidate is not leader after move-leader command"
    End
  End

  Describe "switchover_without_candidate()"
    It "does not switch when leader has already changed"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export PEER_ENDPOINT=""
      get_current_leader() { echo "new_leader_endpoint:2379"; return 0; }
      When call switchover_without_candidate
      The status should be success
      The stdout should include "Leader has already changed, no switchover needed"
    End

    It "fails when no candidate found"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export PEER_ENDPOINT=""
      get_current_leader() { echo "current_endpoint:2379"; return 0; }
      get_member_and_leader_id() { echo "12345 67890"; }
      exec_etcdctl() { echo "12345"; return 0; }
      When call switchover_without_candidate
      The status should be failure
      The stderr should include "No candidate found for switchover"
    End

    It "switches to a random candidate successfully"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export PEER_ENDPOINT=""
      get_current_leader() { echo "current_endpoint:2379"; return 0; }
      get_member_and_leader_id() { echo "12345 67890"; }
      exec_etcdctl() { echo -e "12345\n67890"; return 0; }
      When call switchover_without_candidate
      The status should be success
      The stdout should include "Switchover completed successfully - current node is no longer leader"
    End

    It "fails to switch - current node still leader"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export PEER_ENDPOINT=""
      get_current_leader() { echo "current_endpoint:2379"; return 0; }
      get_member_and_leader_id() { echo "12345 12345"; }
      exec_etcdctl() { echo -e "12345\n67890"; return 0; }
      When call switchover_without_candidate
      The status should be failure
      The stderr should include "Switchover failed - current node is still leader after move-leader command"
    End
  End

  Describe "switchover()"
    It "exits when not current role holder"
      export LEADER_POD_FQDN="other_pod"
      export KB_SWITCHOVER_CURRENT_FQDN="current_pod"
      When call switchover
      The status should be success
      The stdout should include "switchover action not triggered for leader pod. Exiting."
    End

    It "calls switchover_with_candidate when candidate is provided"
      export LEADER_POD_FQDN="current_pod"
      export KB_SWITCHOVER_CURRENT_FQDN="current_pod"
      export KB_SWITCHOVER_CANDIDATE_FQDN="candidate_pod"
      switchover_with_candidate() { return 0; }
      When call switchover
      The status should be success
      The stdout should include "Switchover completed successfully"
    End

    It "calls switchover_without_candidate when candidate is not provided"
      export LEADER_POD_FQDN="current_pod"
      export KB_SWITCHOVER_CURRENT_FQDN="current_pod"
      unset KB_SWITCHOVER_CANDIDATE_FQDN
      switchover_without_candidate() { return 0; }
      When call switchover
      The status should be success
      The stdout should include "Switchover completed successfully"
    End
  End
End