# shellcheck shell=bash
# shellcheck disable=SC2317

Describe "Member Join Script Tests"
  Include ../scripts/member-join.sh

  Describe "add_member()"
    It "adds the member successfully"
      # Mock required environment variables and functions
      export LEADER_POD_FQDN="etcd-0.etcd-headless.default.svc.cluster.local"
      export KB_JOIN_MEMBER_POD_NAME="etcd-3"
      export KB_JOIN_MEMBER_POD_FQDN="etcd-3.etcd-headless.default.svc.cluster.local"
      export PEER_ENDPOINT=""
      get_pod_endpoint_with_lb() { echo "$3"; }
      log() { echo "$@"; }
      get_peer_protocol() { echo "http"; }
      get_client_protocol() { echo "http"; }
      exec_etcdctl() { return 0; }
      When call add_member
      The status should be success
    End

    It "fails to add the member"
      # Mock required environment variables and functions
      export LEADER_POD_FQDN="etcd-0.etcd-headless.default.svc.cluster.local"
      export KB_JOIN_MEMBER_POD_NAME="etcd-3"
      export KB_JOIN_MEMBER_POD_FQDN="etcd-3.etcd-headless.default.svc.cluster.local"
      export PEER_ENDPOINT=""
      get_pod_endpoint_with_lb() { echo "$3"; }
      log() { echo "$@"; }
      get_peer_protocol() { echo "http"; }
      get_client_protocol() { echo "http"; }
      exec_etcdctl() { return 1; }
      When call add_member
      The status should be failure
    End

    It "handles empty environment variables"
      # Test with missing required environment variables
      unset LEADER_POD_FQDN
      unset KB_JOIN_MEMBER_POD_NAME
      unset KB_JOIN_MEMBER_POD_FQDN
      get_pod_endpoint_with_lb() { echo ""; }
      log() { echo "$@"; }
      get_peer_protocol() { echo "http"; }
      get_client_protocol() { echo "http"; }
      exec_etcdctl() { return 1; }
      When call add_member
      The status should be failure
    End
  End
End