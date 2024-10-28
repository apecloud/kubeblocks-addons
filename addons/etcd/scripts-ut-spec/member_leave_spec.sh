# shellcheck shell=bash
# shellcheck disable=SC2317

Describe "Member Leave Script Tests"
  Include ../scripts/member-leave.sh

  Describe "get_leaver_endpoint()"
    It "returns the correct leaver endpoint"
      export KB_MEMBER_ADDRESSES="http://etcd-0:2379,http://etcd-1:2379,http://etcd-2:2379"
      export KB_LEAVE_MEMBER_POD_NAME="etcd-1"
      When call get_leaver_endpoint
      The output should equal "http://etcd-1:2379"
    End

    It "returns empty when leaver endpoint is not found"
      export KB_MEMBER_ADDRESSES="http://etcd-0:2379,http://etcd-1:2379,http://etcd-2:2379"
      export KB_LEAVE_MEMBER_POD_NAME="etcd-3"
      When call get_leaver_endpoint
      The status should be failure
    End
  End

  Describe "get_etcd_id()"
    It "returns the correct etcd ID"
      exec_etcdctl() {
        echo "127.0.0.1:2379, 8e9e05c52164694d, 3.5.16, 25 kB, true, false, 2, 4, 4,"
      }
      When call get_etcd_id "http://etcd-0:2379"
      The output should equal "8e9e05c52164694d"
    End
  End

  Describe "remove_member()"
    It "removes the member successfully"
      exec_etcdctl() { return 0; }
      When call remove_member "8e9e05c52164694d"
      The status should be success
    End

    It "fails to remove the member"
      exec_etcdctl() { return 1; }
      When call remove_member "8e9e05c52164694d"
      The status should be failure
    End
  End

  Describe "member_leave()"
    It "leaves the member successfully"
      get_leaver_endpoint() { echo "http://etcd-1:2379"; }
      get_etcd_id() { echo "8e9e05c52164694d"; }
      remove_member() { return 0; }
      When call member_leave
      The status should be success
    End

    It "fails to leave the member when leaver endpoint is not found"
      get_leaver_endpoint() { return 1; }
      When call member_leave
      The status should be failure
      The stderr should include "ERROR: leave member pod name not found in member addresses"
    End

    It "fails to leave the member when etcd ID retrieval fails"
      get_leaver_endpoint() { echo "http://etcd-1:2379"; }
      get_etcd_id() { return 1; }
      exec_etcdctl() { if [ -z "$1" ]; then echo "ERROR: fails to get etcd id" >&2; fi; return 1; }
      When call member_leave
      The status should be failure
      The stderr should include "ERROR: fails to get etcd id"
      The stderr should include "ERROR: etcdctl remove_member failed"
    End
  End
End