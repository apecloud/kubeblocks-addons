# shellcheck shell=bash
# shellcheck disable=SC2317

Describe "Role Probe Tests"
  Include ../scripts/roleprobe.sh

  Describe "get_etcd_role()"
    It "returns leader when IsLeader is true"
      exec_etcdctl() {
        echo "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, true, false, 2, 4, 4,"
      }
      When call get_etcd_role
      The output should equal "leader"
    End

    It "returns learner when IsLearner is true"
      exec_etcdctl() {
        echo "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, false, true, 2, 4, 4,"
      }
      When call get_etcd_role
      The output should equal "learner"
    End

    It "returns follower when both IsLeader and IsLearner are false"
      exec_etcdctl() {
        echo "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, false, false, 2, 4, 4,"
      }
      When call get_etcd_role
      The output should equal "follower"
    End

    It "returns error when role is invalid"
      exec_etcdctl() {
        echo "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, invalid_status, false, 2, 4, 4,"
      }
      When call get_etcd_role
      The status should be failure
      The stderr should include "bad role, please check!"
    End
  End
End