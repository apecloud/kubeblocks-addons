# shellcheck shell=bash
# shellcheck disable=SC2317

Describe "Switchover Script Tests"
  Include ../scripts/switchover.sh

  exec_etcdctl() {
    return 0
  }

  log() { echo "$@"; }
  error_exit() { echo "ERROR: $1" >&2; exit 1; }
  get_endpoint_adapt_lb() { echo "$3"; }

  BeforeEach "exec_etcdctl" "log" "error_exit" "get_endpoint_adapt_lb"

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

  Describe "get_member_id()"
    It "returns member ID"
      exec_etcdctl() {
        echo '"MemberID" : 12345'
      }
      When call get_member_id "test_endpoint"
      The output should equal "12345"
      The status should be success
    End

    It "fails when cannot get endpoint status"
      exec_etcdctl() { return 1; }
      When call get_member_id "test_endpoint"
      The status should be failure
      The stderr should include "Failed to get endpoint status"
    End
  End

  Describe "get_first_follower()"
    It "returns first follower ID"
      get_member_id() { echo "12345"; }
      exec_etcdctl() { 
        case "$*" in
          *"member list"*) echo -e '"ID" : 12345\n"ID" : 67890';;
        esac
      }
      When call get_first_follower "test_endpoint"
      The output should equal "67890"
      The status should be success
    End

    It "fails when no follower found"
      get_member_id() { echo "12345"; }
      exec_etcdctl() { 
        case "$*" in
          *"member list"*) echo '"ID" : 12345';;  # only current member
        esac
      }
      When call get_first_follower "test_endpoint"
      The status should be failure
      The stderr should include "No follower found for switchover"
    End
  End

  Describe "is_leader()"
    It "returns success when endpoint is leader"
      exec_etcdctl() {
        echo '"MemberID" : 12345
"Leader" : 12345'
      }
      When call is_leader "test_endpoint"
      The status should be success
    End

    It "returns failure when endpoint is not leader"
      exec_etcdctl() {
        echo '"MemberID" : 12345
"Leader" : 67890'
      }
      When call is_leader "test_endpoint"
      The status should be failure
    End

    It "fails when cannot get endpoint status"
      exec_etcdctl() { return 1; }
      When call is_leader "test_endpoint"
      The status should be failure
      The stderr should include "Failed to get endpoint status"
    End
  End

  Describe "switchover_with_candidate()"
    It "does not switch when candidate is already leader"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export KB_SWITCHOVER_CANDIDATE_FQDN="candidate_endpoint.domain"
      export PEER_ENDPOINT=""
      is_leader() { return 0; }  # candidate is leader
      When call switchover_with_candidate
      The status should be success
      The stdout should include "Current leader is the same as candidate, no need to switch"
    End

    It "switches to the candidate successfully"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export KB_SWITCHOVER_CANDIDATE_FQDN="candidate_endpoint.domain"
      export PEER_ENDPOINT=""
      is_leader() { 
        case "$1" in
          *current*) return 1;;  # current is not leader
          *candidate*) return 0;;  # candidate becomes leader
        esac
      }
      get_member_id() { echo "12345"; }
      When call switchover_with_candidate
      The status should be success
      The stdout should include "Switchover to candidate candidate_endpoint.domain completed successfully"
    End

    It "fails to switch to the candidate"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export KB_SWITCHOVER_CANDIDATE_FQDN="candidate_endpoint.domain"
      export PEER_ENDPOINT=""
      is_leader() { 
        case "$1" in
          *current*) return 1;;  # current is not leader
          *candidate*) return 1;;  # candidate fails to become leader
        esac
      }
      get_member_id() { echo "12345"; }
      When call switchover_with_candidate
      The status should be failure
      The stderr should include "Candidate is not leader"
    End
  End

  Describe "switchover_without_candidate()"
    It "does not switch when current endpoint is not leader"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export PEER_ENDPOINT=""
      is_leader() { return 1; }  # current endpoint is not leader
      When call switchover_without_candidate
      The status should be success
      The stdout should include "Leader has already changed, no switchover needed"
    End

    It "fails when no candidate found"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export PEER_ENDPOINT=""
      is_leader() { return 0; }  # current endpoint is leader
      get_first_follower() { error_exit "No follower found for switchover"; }
      When call switchover_without_candidate
      The status should be failure
      The stderr should include "No follower found for switchover"
    End

    It "switches to a random candidate successfully"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export PEER_ENDPOINT=""
      call_count=0
      is_leader() { 
        call_count=$((call_count + 1))
        if [ "$call_count" -eq 1 ]; then
          return 0  # initially leader
        else
          return 1  # no longer leader after switch
        fi
      }
      get_first_follower() { echo "67890"; }
      exec_etcdctl() { 
        case "$*" in
          *"move-leader"*) return 0;;
        esac
      }
      When call switchover_without_candidate
      The status should be success
      The stdout should include "Switchover completed successfully - current node is no longer leader"
    End

    It "fails to switch - current node still leader"
      export KB_SWITCHOVER_CURRENT_FQDN="current_endpoint.domain"
      export PEER_ENDPOINT=""
      is_leader() { return 0; }  # always leader (switch fails)
      get_first_follower() { echo "67890"; }
      exec_etcdctl() { 
        case "$*" in
          *"move-leader"*) return 0;;
        esac
      }
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