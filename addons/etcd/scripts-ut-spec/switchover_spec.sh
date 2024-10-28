# shellcheck shell=bash
# shellcheck disable=SC2317

Describe "Switchover Script Tests"
  Include ../scripts/switchover.sh

  exec_etcdctl() {
    return 0
  }

  is_empty() { [[ -z "$1" ]]; }

  BeforeEach "exec_etcdctl" "is_empty"

  Describe "switchover_with_candidate()"
    It "fails to get current leader endpoint"
      get_current_leader_with_retry() { return 1; }
      When call switchover_with_candidate
      The status should be failure
      The stderr should include "failed to get current leader endpoint"
    End

    It "does not switch when current leader is the same as candidate"
      export KB_SWITCHOVER_CANDIDATE_FQDN="candidate_endpoint"
      get_current_leader_with_retry() { echo "candidate_endpoint:2379"; return 0; }
      When call switchover_with_candidate
      The status should be success
      The stdout should include "current leader is the same as candidate, no need to switch"
    End

    It "switches to the candidate successfully"
      get_current_leader_with_retry() { echo "leader_endpoint:2379"; return 0; }
      exec_etcdctl() { echo "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, true, false, 2, 4, 4,"; return 0; }
      When call switchover_with_candidate
      The stdout should include "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, true, false, 2, 4, 4,"
      The status should be success
    End

    It "fails to switch to the candidate"
      get_current_leader_with_retry() { echo "leader_endpoint:2379"; return 0; }
      exec_etcdctl() { return 1; }
      When call switchover_with_candidate
      The status should be failure
    End
  End

  Describe "switchover_without_candidate()"
    It "fails to get current leader endpoint"
      get_current_leader_with_retry() { return 1; }
      When call switchover_without_candidate
      The status should be failure
      The stderr should include "failed to get current leader endpoint"
    End

    It "does not switch when leader has been changed"
      get_current_leader_with_retry() { echo "new_leader_endpoint:2379"; return 0; }
      When call switchover_without_candidate
      The status should be success
      The stdout should include "leader has been changed, do not perform switchover, please check!"
    End

    It "fails when no candidate found"
      export LEADER_POD_FQDN="leader_endpoint"
      get_current_leader_with_retry() { echo "leader_endpoint:2379"; return 0; }
      exec_etcdctl() { echo "leader_id"; return 0; }

      When call switchover_without_candidate
      The status should be failure
      The stderr should include "no candidate found"
    End

    It "switches to a random candidate successfully"
      export LEADER_POD_FQDN="leader_endpoint"
      get_current_leader_with_retry() { echo "leader_endpoint:2379"; return 0; }
      exec_etcdctl() { echo "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, false, false, 2, 4, 4,"; return 0; }
      is_empty() { return 1; }
      When call switchover_without_candidate
      The status should be success
      The stdout should include "switchover successfully"
    End

    It "fails to switch to a random candidate"
      export LEADER_POD_FQDN="leader_endpoint"
      get_current_leader_with_retry() { echo "leader_endpoint:2379"; return 0; }
      exec_etcdctl() { echo "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, true, false, 2, 4, 4,"; return 0; }
      is_empty() { return 1; }
      When call switchover_without_candidate
      The status should be failure
      The stdout should include "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, true, false, 2, 4, 4,"
      The stderr should include "switchover failed, please check!"
    End
  End

  Describe "switchover()"
    It "calls switchover_with_candidate when candidate is provided"
      is_empty() { return 1; }
      switchover_with_candidate() { return 0; }
      When call switchover
      The status should be success
    End

    It "calls switchover_without_candidate when candidate is not provided"
      is_empty() { return 0; }
      switchover_without_candidate() { return 0; }
      When call switchover
      The status should be success
    End

    It "fails when switchover_with_candidate fails"
      is_empty() { return 1; }
      switchover_with_candidate() { return 1; }
      When call switchover
      The status should be failure
      The stderr should include "Failed to switchover. Exiting."
    End

    It "fails when switchover_without_candidate fails"
      is_empty() { return 0; }
      switchover_without_candidate() { return 1; }
      When call switchover
      The status should be failure
      The stderr should include "Failed to switchover. Exiting."
    End
  End
End