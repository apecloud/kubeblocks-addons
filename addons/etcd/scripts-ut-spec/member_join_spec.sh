# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "member_join_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe 'Etcd memberJoin registration reconciliation'
  Include ../scripts/member-join.sh

  setup() {
    LEADER_POD_FQDN=etcd-0.headless
    KB_JOIN_MEMBER_POD_NAME=etcd-1
    KB_JOIN_MEMBER_POD_FQDN=etcd-1.headless
    PEER_ENDPOINT=''
    peer='http://etcd-1.headless:2380'
    scenario=absent
    added=false
    get_endpoint_adapt_lb() { echo "$3"; }
    get_protocol() { echo http; }
    log() { echo "$1"; }
    error_exit() { echo "$1"; return 1; }
    exec_etcdctl() {
      # Validate that every query/add is bounded and uses the leader endpoint.
      [ "$1" = 'etcd-0.headless:2379' ] || return 90
      [ "$2" = '--dial-timeout=3s' ] || return 91
      [ "$3" = '--command-timeout=5s' ] || return 92
      shift 3
      case "$*" in
        'member list -w simple')
          if [ "$added" = true ]; then
            case "$scenario" in
              absent|lost_reply) echo "2, unstarted, , $peer, , false"; return;;
              add_failure|post_success_absent) echo '1, started, etcd-0, http://etcd-0.headless:2380, http://etcd-0.headless:2379, false'; return;;
              post_query_failure|post_success_query_failure) return 1;;
              post_success_conflict) echo "2, started, wrong, $peer, , false"; return;;
            esac
          fi
          case "$scenario" in
            present) echo "2, started, etcd-1, $peer, http://etcd-1.headless:2379, false";;
            unstarted) echo "2, unstarted, , $peer, , false";;
            wrong_name) echo "2, started, other, $peer, http://other:2379, false";;
            wrong_peer) echo '2, started, etcd-1, http://wrong:2380, http://wrong:2379, false';;
            learner) echo "2, unstarted, , $peer, , true";;
            duplicate)
              echo "2, unstarted, , $peer, , false"
              echo "3, unstarted, , $peer, , false";;
            malformed) echo 'not membership';;
            empty) :;;
            query_failure) return 1;;
            *) echo '1, started, etcd-0, http://etcd-0.headless:2380, http://etcd-0.headless:2379, false';;
          esac
          ;;
        "member add etcd-1 --peer-urls=$peer")
          added=true
          echo ADD
          case "$scenario" in lost_reply|add_failure|post_query_failure) return 1;; esac
          ;;
        *) return 93;;
      esac
    }
  }
  BeforeEach setup

  It 'adds a missing member'
    When call add_member
    The status should be success
    The output should include 'ADD'
    The output should include 'registration confirmed after successful add'
  End

  Context "already registered"
    Parameters
      present
      unstarted
    End
    It 'accepts an existing voter without adding it again'
      scenario="$1"
      When call add_member
      The status should be success
      The output should include 'already registered'
      The output should not include 'ADD'
    End

  End

  Context "invalid precondition"
    Parameters
      wrong_name
      wrong_peer
      learner
      duplicate
      malformed
      empty
      query_failure
    End
    It 'fails closed before add on a conflict or unreadable membership'
      scenario="$1"
      When call add_member
      The status should be failure
      The output should include 'Cannot safely join member'
      The output should include 'Last observed membership'
      The output should not include 'ADD'
    End

  End

  It 'recovers when the add committed but its reply failed'
    scenario=lost_reply
    When call add_member
    The status should be success
    The output should include 'registration confirmed after add error'
  End

  Context "unconfirmed failure"
    Parameters
      add_failure
      post_query_failure
      post_success_absent
      post_success_conflict
      post_success_query_failure
    End
    It 'does not hide an unconfirmed add failure'
      scenario="$1"
      When call add_member
      The status should be failure
      The output should include 'registration could not be confirmed'
      The output should include 'Last observed membership'
    End
  End
  Context "failure diagnostics"
    Parameters
      wrong_name '2, started, other, http://etcd-1.headless:2380'
      post_success_absent '1, started, etcd-0, http://etcd-0.headless:2380'
      post_success_query_failure '(query failed)'
      empty '<(empty)>'
    End
    It 'includes the observed membership or an explicit failure marker'
      scenario="$1"
      When call add_member
      The status should be failure
      The output should include "$2"
    End
  End

  It 'bounds membership diagnostics to 20 lines'
    join_membership_snapshot=$(for i in {1..25}; do echo "member-line-$i"; done)
    join_membership_query_error=''
    When call log_join_membership
    The status should be success
    The output should include 'member-line-20'
    The output should not include 'member-line-21'
  End

End
