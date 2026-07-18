# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "member_leave_spec.sh skip cases because bash 4 or higher is not installed."
  exit 0
fi

member_leave_script="./member-leave-under-test.sh"
sed -e '1,/^[[:space:]]*\. "\/scripts\/common\.sh"[[:space:]]*$/d' \
  -e '/^# Shellspec magic/,$d' ../scripts/member-leave.sh > "$member_leave_script"

Describe "Etcd Member Leave Script Tests"
  Include ../scripts/common.sh
  Include $member_leave_script

  setup() {
    TEST_DIR=$(mktemp -d)
    export TEST_DIR
    export MEMBER_LEAVE_CALL_LOG="$TEST_DIR/call.log"
    export MEMBER_LEAVE_ENDPOINT_LOG="$TEST_DIR/endpoint.log"
    export MEMBER_LEAVE_READ_COUNT="$TEST_DIR/read-count"
    export MEMBER_LEAVE_STATES="$TEST_DIR/states"
    : > "$MEMBER_LEAVE_CALL_LOG"
    : > "$MEMBER_LEAVE_ENDPOINT_LOG"
    printf '0' > "$MEMBER_LEAVE_READ_COUNT"
    : > "$MEMBER_LEAVE_STATES"

    export LEADER_POD_FQDN="deleted-0.old-headless.default.svc.cluster.local"
    export PEER_FQDNS="deleted-0.old-headless.default.svc.cluster.local,etcd-2.old-headless.default.svc.cluster.local"
    export KB_LEAVE_MEMBER_POD_NAME="etcd-1"
    export KB_LEAVE_MEMBER_POD_FQDN="etcd-1.etcd-headless.default.svc.cluster.local"
    export PEER_ENDPOINT=""
    export MEMBER_REMOVE_RC=0
    export LOCAL_LEADER_STATUS="leader"

    get_protocol() {
      printf 'http\n'
    }

    log() {
      printf '%s\n' "$1" >&2
    }

    exec_etcdctl() {
      local endpoint="$1"
      shift
      printf '%s %s\n' "$endpoint" "$*" >> "$MEMBER_LEAVE_ENDPOINT_LOG"

      if [ "$1 $2" = "endpoint status" ]; then
        case "$LOCAL_LEADER_STATUS" in
          leader)
            printf '%s\n' '"MemberID" : 1' '"Leader" : 1'
            ;;
          follower)
            printf '%s\n' '"MemberID" : 1' '"Leader" : 2'
            ;;
          query-failed)
            return 1
            ;;
          *)
            printf '%s\n' 'malformed endpoint status'
            ;;
        esac
        return 0
      fi

      if [ "$1 $2" = "member list" ]; then
        local index state member
        index=$(cat "$MEMBER_LEAVE_READ_COUNT")
        index=$((index + 1))
        printf '%s' "$index" > "$MEMBER_LEAVE_READ_COUNT"
        state=$(sed -n "${index}p" "$MEMBER_LEAVE_STATES")
        case "$state" in
          present)
            print_started_member 1 etcd-0 etcd-0.etcd-headless.default.svc.cluster.local
            print_started_member 1002 etcd-1 etcd-1.etcd-headless.default.svc.cluster.local
            print_started_member 3 etcd-2 etcd-2.etcd-headless.default.svc.cluster.local
            ;;
          absent)
            print_started_member 1 etcd-0 etcd-0.etcd-headless.default.svc.cluster.local
            print_started_member 3 etcd-2 etcd-2.etcd-headless.default.svc.cluster.local
            ;;
          unrelated-unstarted)
            print_started_member 1 etcd-0 etcd-0.etcd-headless.default.svc.cluster.local
            print_started_member 1002 etcd-1 etcd-1.etcd-headless.default.svc.cluster.local
            printf '%s\n' \
              '"ID" : 3' \
              '"Name" : ""' \
              '"PeerURL" : "http://etcd-2.etcd-headless.default.svc.cluster.local:2380"' ''
            ;;
          target-only)
            print_started_member 1002 etcd-1 etcd-1.etcd-headless.default.svc.cluster.local
            ;;
          malformed-client-url)
            print_started_member 1 etcd-0 etcd-0.etcd-headless.default.svc.cluster.local
            printf '%s\n' \
              '"ID" : 1002' \
              '"Name" : "etcd-1"' \
              '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "not-a-url"' ''
            ;;
          duplicate-target)
            print_started_member 1 etcd-0 etcd-0.etcd-headless.default.svc.cluster.local
            print_started_member 1002 etcd-1 etcd-1.etcd-headless.default.svc.cluster.local
            print_started_member 1003 etcd-1 duplicate.etcd-headless.default.svc.cluster.local
            ;;
          over-limit)
            print_started_member 1002 etcd-1 etcd-1.etcd-headless.default.svc.cluster.local
            for member in 0 2 3 4 5 6 7 8 9; do
              print_started_member "$member" "etcd-$member" "etcd-$member.example"
            done
            ;;
          query-failed)
            return 1
            ;;
          *)
            printf '%s\n' 'malformed output without member blocks'
            ;;
        esac
        return 0
      fi

      printf '%s %s\n' "$endpoint" "$*" >> "$MEMBER_LEAVE_CALL_LOG"
      return "$MEMBER_REMOVE_RC"
    }
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    unset TEST_DIR MEMBER_LEAVE_CALL_LOG MEMBER_LEAVE_ENDPOINT_LOG
    unset MEMBER_LEAVE_READ_COUNT MEMBER_LEAVE_STATES
    unset LEADER_POD_FQDN PEER_FQDNS KB_LEAVE_MEMBER_POD_NAME KB_LEAVE_MEMBER_POD_FQDN
    unset PEER_ENDPOINT MEMBER_REMOVE_RC LOCAL_LEADER_STATUS
    unset -f get_protocol log exec_etcdctl
  }
  AfterEach "cleanup"

  cleanup_generated_script() {
    rm -f "$member_leave_script"
  }
  AfterAll "cleanup_generated_script"

  set_member_states() {
    printf '%s\n' "$@" > "$MEMBER_LEAVE_STATES"
  }

  print_started_member() {
    local id="$1"
    local name="$2"
    local host="$3"
    printf '%s\n' \
      "\"ID\" : $id" \
      "\"Name\" : \"$name\"" \
      "\"PeerURL\" : \"http://$host:2380\"" \
      "\"ClientURL\" : \"http://$host:2379\"" ''
  }

  find_leave_fixture() {
    local fixture="$1"
    local target_name="$2"
    find_leave_target_id "$target_name" < "$fixture"
  }

  Describe "find_leave_target_id()"
    It "returns the target raw decimal member ID from one exact block"
      print_started_member 1 etcd-0 etcd-0.example > "$TEST_DIR/member-list.fields"
      print_started_member 1002 etcd-1 etcd-1.example >> "$TEST_DIR/member-list.fields"
      When call find_leave_fixture "$TEST_DIR/member-list.fields" etcd-1
      The status should be success
      The output should eq "1002"
    End

    It "returns absent when the target name is not present"
      print_started_member 1 etcd-0 etcd-0.example > "$TEST_DIR/member-list.fields"
      When call find_leave_fixture "$TEST_DIR/member-list.fields" etcd-1
      The status should be success
      The output should eq "absent"
    End

    It "fails closed for duplicate target identities"
      print_started_member 1002 etcd-1 etcd-1.example > "$TEST_DIR/member-list.fields"
      print_started_member 1003 etcd-1 duplicate.example >> "$TEST_DIR/member-list.fields"
      When call find_leave_fixture "$TEST_DIR/member-list.fields" etcd-1
      The status should be failure
      The output should eq ""
    End
  End

  Describe "member_leave()"
    It "uses the action-time local leader and current member list instead of static snapshots"
      set_member_states absent
      When call member_leave
      The status should be success
      The error should include "already absent"
      The contents of file "$MEMBER_LEAVE_ENDPOINT_LOG" should include \
        "127.0.0.1:2379 endpoint status -w fields"
      The contents of file "$MEMBER_LEAVE_ENDPOINT_LOG" should include \
        "127.0.0.1:2379 member list -w fields"
      The contents of file "$MEMBER_LEAVE_ENDPOINT_LOG" should not include "deleted-0"
    End

    It "fails closed before querying when required action-time inputs are empty"
      unset LEADER_POD_FQDN KB_LEAVE_MEMBER_POD_NAME KB_LEAVE_MEMBER_POD_FQDN
      When call member_leave
      The status should be failure
      The error should include "phase: required-input-empty"
      The error should not include "LEADER_POD_FQDN"
      The error should include "KB_LEAVE_MEMBER_POD_NAME"
      The error should include "KB_LEAVE_MEMBER_POD_FQDN"
      The error should include "next-retry-safe: no"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should eq ""
      The contents of file "$MEMBER_LEAVE_READ_COUNT" should eq "0"
    End

    It "defers before mutation when the selected action pod is not the current leader"
      LOCAL_LEADER_STATUS=follower
      set_member_states present
      When call member_leave
      The status should be failure
      The error should include "phase: selected-contact-not-current-leader"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should eq ""
      The contents of file "$MEMBER_LEAVE_READ_COUNT" should eq "0"
    End

    It "returns success without mutation when the target is already absent"
      set_member_states absent
      When call member_leave
      The status should be success
      The error should include "already absent"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should eq ""
      The contents of file "$MEMBER_LEAVE_READ_COUNT" should eq "1"
    End

    It "removes once by raw target ID and closes only after an absent post-read"
      set_member_states present absent
      When call member_leave
      The status should be success
      The error should include "left cluster"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should include "member remove 3ea"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should include \
        "--dial-timeout=2s --command-timeout=6s"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should not include \
        "etcd-1.etcd-headless.default.svc.cluster.local:2379"
      The contents of file "$MEMBER_LEAVE_READ_COUNT" should eq "2"
    End

    It "accepts an absent post-read even when the concurrent remove returned nonzero"
      set_member_states present absent
      MEMBER_REMOVE_RC=1
      When call member_leave
      The status should be success
      The error should include "left cluster"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should include "member remove 3ea"
      The contents of file "$MEMBER_LEAVE_READ_COUNT" should eq "2"
    End

    It "fails transiently when a successful remove is not observed"
      set_member_states present present
      When call member_leave
      The status should be failure
      The error should include "phase: member-removal-not-observed"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should include "member remove 3ea"
      The contents of file "$MEMBER_LEAVE_READ_COUNT" should eq "2"
    End

    It "fails transiently when remove fails and the target remains present"
      set_member_states present present
      MEMBER_REMOVE_RC=1
      When call member_leave
      The status should be failure
      The error should include "phase: member-remove-failed"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_LEAVE_READ_COUNT" should eq "2"
    End

    It "accepts an unrelated valid unstarted block while using a started contact"
      set_member_states unrelated-unstarted absent
      When call member_leave
      The status should be success
      The error should include "left cluster"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should include "member remove 3ea"
    End

    It "fails distinctly when excluding the target leaves no current contact"
      set_member_states target-only
      When call member_leave
      The status should be failure
      The error should include "phase: contact-candidate-empty"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should eq ""
    End

    It "fails closed for a malformed nonempty client URL"
      set_member_states malformed-client-url
      When call member_leave
      The status should be failure
      The error should include "phase: member-list-invalid"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should eq ""
    End

    It "fails closed for a duplicate target identity"
      set_member_states duplicate-target
      When call member_leave
      The status should be failure
      The error should include "phase: member-list-invalid"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should eq ""
    End

    It "fails closed instead of truncating more than eight contacts"
      set_member_states over-limit
      When call member_leave
      The status should be failure
      The error should include "phase: contact-candidate-over-limit"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should eq ""
    End

    It "classifies a pre-read query failure as transient without mutation"
      set_member_states query-failed
      When call member_leave
      The status should be failure
      The error should include "phase: member-list-query-failed"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_LEAVE_CALL_LOG" should eq ""
    End

    It "classifies a post-read query failure as transient after one remove"
      set_member_states present query-failed
      When call member_leave
      The status should be failure
      The error should include "phase: member-post-remove-query-failed"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_LEAVE_READ_COUNT" should eq "2"
    End
  End
End
