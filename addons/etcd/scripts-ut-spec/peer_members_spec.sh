# shellcheck shell=bash
# shellcheck disable=SC2034,SC2286
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo 'peer_members_spec.sh requires bash 4 or higher; skipping.'
  exit 0
fi

Describe 'Etcd quorum-independent peer membership'
  Include ../scripts/peer-members.sh

  It 'decodes started and multiple unnamed members without losing uint64 IDs'
    Data
      #|[{"id":18446744073709551615,"peerURLs":["http://etcd-0:2380"],"name":"etcd-0","clientURLs":["http://etcd-0:2379"]},{"id":"2","peerURLs":["http://etcd-1:2380"]},{"id":"3","peerURLs":["http://etcd-2:2380"],"isLearner":false}]
    End
    When call peer_members_to_list
    The status should be success
    The output should include '18446744073709551615, started, etcd-0, http://etcd-0:2380'
    The output should include '2, unstarted, , http://etcd-1:2380, , false'
    The output should include '3, unstarted, , http://etcd-2:2380, , false'
  End

  Context 'unreadable membership'
    Parameters
      '[]'
      '[{"id":"1","peerURLs":["http://etcd-0:2380"]}'
      '[{"id":"1","peerURLs":[]}]'
      '[{"id":"1","peerURLs":["http://a:2380","http://b:2380"]}]'
      '[{"id":"1","id":"2","peerURLs":["http://a:2380"]}]'
      '[{"id":"1","peerURLs":["http://a:2380"]}] garbage'
      '{"error":"unavailable"}'
    End
    It 'fails without emitting a partial member list'
      read_fixture() { printf '%s\n' "$1" | peer_members_to_list; }
      When call read_fixture "$1"
      The status should be failure
      The output should be blank
    End
  End

  It 'reads peer membership without a linearizable etcdctl call'
    curl() {
      echo "$*" >&2
      echo '[{"id":"1","peerURLs":["http://etcd-0:2380"],"name":"etcd-0"}]'
    }
    When call read_peer_members http://etcd-0:2380 5
    The status should be success
    The output should include '1, started, etcd-0'
    The stderr should include '--connect-timeout 3 --max-time 5 http://etcd-0:2380/members'
  End

  It 'fails closed when peer TLS credentials are missing'
    TLS_MOUNT_PATH=/nonexistent-etcd-test-tls
    When call read_peer_members https://etcd-0:2380 5
    The status should be failure
    The output should be blank
  End
End
