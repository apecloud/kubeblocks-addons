# shellcheck shell=bash
# shellcheck disable=SC2317

Describe "Role Probe Tests"
  Include ../scripts/roleprobe.sh

  Describe "get_etcd_role()"
    It "returns leader when MemberID equals Leader ID"
      exec_etcdctl() {
        echo '"ClusterID" : 13039986632204101178
"MemberID" : 2629816592825133483
"Revision" : 1
"RaftTerm" : 2
"Version" : "3.6.1"
"StorageVersion" : "3.6.0"
"DBSize" : 20480
"DBSizeInUse" : 16384
"Leader" : 2629816592825133483
"IsLearner" : false
"RaftIndex" : 9
"RaftTerm" : 2
"RaftAppliedIndex" : 9
"Errors" : []
"Endpoint" : "127.0.0.1:2379"
"DowngradeTargetVersion" : ""
"DowngradeEnabled" : false'
      }
      When call get_etcd_role
      The output should equal "leader"
    End

    It "returns learner when IsLearner is true"
      exec_etcdctl() {
        echo '"ClusterID" : 13039986632204101178
"MemberID" : 7313738417175062960
"Revision" : 1
"RaftTerm" : 2
"Version" : "3.6.1"
"StorageVersion" : "3.6.0"
"DBSize" : 20480
"DBSizeInUse" : 16384
"Leader" : 2629816592825133483
"IsLearner" : true
"RaftIndex" : 9
"RaftTerm" : 2
"RaftAppliedIndex" : 9
"Errors" : []
"Endpoint" : "127.0.0.1:2379"
"DowngradeTargetVersion" : ""
"DowngradeEnabled" : false'
      }
      When call get_etcd_role
      The output should equal "learner"
    End

    It "returns follower when MemberID does not equal Leader ID and IsLearner is false"
      exec_etcdctl() {
        echo '"ClusterID" : 13039986632204101178
"MemberID" : 7313738417175062960
"Revision" : 1
"RaftTerm" : 2
"Version" : "3.6.1"
"StorageVersion" : "3.6.0"
"DBSize" : 20480
"DBSizeInUse" : 16384
"Leader" : 2629816592825133483
"IsLearner" : false
"RaftIndex" : 9
"RaftTerm" : 2
"RaftAppliedIndex" : 9
"Errors" : []
"Endpoint" : "127.0.0.1:2379"
"DowngradeTargetVersion" : ""
"DowngradeEnabled" : false'
      }
      When call get_etcd_role
      The output should equal "follower"
    End

    It "fails when exec_etcdctl command fails"
      exec_etcdctl() {
        return 1
      }
      When call get_etcd_role
      The status should be failure
      The stderr should include "ERROR: Failed to get endpoint status"
    End
  End
End