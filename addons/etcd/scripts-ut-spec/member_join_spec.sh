# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "member_join_spec.sh skip cases because bash 4 or higher is not installed."
  exit 0
fi

member_join_script="./member-join-under-test.sh"
sed -e '1,/^[[:space:]]*\. "\/scripts\/common\.sh"[[:space:]]*$/d' \
  -e '/^# Shellspec magic/,$d' ../scripts/member-join.sh > "$member_join_script"

Describe "Etcd Member Join Script Tests"
  Include ../scripts/common.sh
  Include $member_join_script

  setup() {
    TEST_DIR=$(mktemp -d)
    export TEST_DIR
    export MEMBER_JOIN_CALL_LOG="$TEST_DIR/call.log"
    export MEMBER_JOIN_READ_COUNT="$TEST_DIR/read-count"
    export MEMBER_JOIN_STATES="$TEST_DIR/states"
    : > "$MEMBER_JOIN_CALL_LOG"
    printf '0' > "$MEMBER_JOIN_READ_COUNT"
    : > "$MEMBER_JOIN_STATES"

    export LEADER_POD_FQDN="etcd-0.etcd-headless.default.svc.cluster.local"
    export KB_JOIN_MEMBER_POD_NAME="etcd-1"
    export KB_JOIN_MEMBER_POD_FQDN="etcd-1.etcd-headless.default.svc.cluster.local"
    export PEER_ENDPOINT=""
    export MEMBER_ADD_RC=0

    get_endpoint_adapt_lb() {
      printf '%s\n' "$3"
    }

    get_protocol() {
      printf 'http\n'
    }

    log() {
      printf '%s\n' "$1" >&2
    }

    exec_etcdctl() {
      local endpoint="$1"
      shift
      if [ "$1 $2" = "member list" ]; then
        local index state
        index=$(cat "$MEMBER_JOIN_READ_COUNT")
        index=$((index + 1))
        printf '%s' "$index" > "$MEMBER_JOIN_READ_COUNT"
        state=$(sed -n "${index}p" "$MEMBER_JOIN_STATES")
        case "$state" in
          exact)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "etcd-1"' \
              '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' ''
            ;;
          unstarted-registered)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : ""' \
              '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' ''
            ;;
          name-conflict)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "etcd-1"' \
              '"PeerURL" : "http://wrong:2380"' ''
            ;;
          peer-conflict)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "other"' \
              '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' ''
            ;;
          absent)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "etcd-0"' \
              '"PeerURL" : "http://etcd-0:2380"' ''
            ;;
          empty-peer-url)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "other"' \
              '"PeerURL" : ""' ''
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

      printf '%s %s\n' "$endpoint" "$*" >> "$MEMBER_JOIN_CALL_LOG"
      return "$MEMBER_ADD_RC"
    }
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    unset TEST_DIR MEMBER_JOIN_CALL_LOG MEMBER_JOIN_READ_COUNT MEMBER_JOIN_STATES
    unset LEADER_POD_FQDN KB_JOIN_MEMBER_POD_NAME KB_JOIN_MEMBER_POD_FQDN
    unset PEER_ENDPOINT MEMBER_ADD_RC
    unset -f get_endpoint_adapt_lb get_protocol log exec_etcdctl
  }
  AfterEach "cleanup"

  cleanup_generated_script() {
    rm -f "$member_join_script"
  }
  AfterAll "cleanup_generated_script"

  set_member_states() {
    printf '%s\n' "$@" > "$MEMBER_JOIN_STATES"
  }

  classify_fixture() {
    local fixture="$1"
    local target_name="$2"
    local target_peer_url="$3"
    classify_member_state "$target_name" "$target_peer_url" < "$fixture"
  }

  write_fields() {
    printf '%s\n' "$@" > "$TEST_DIR/member-list.fields"
  }

  Describe "classify_member_state()"
    It "classifies the byte-exact etcd 3.5.15 unstarted member fixture"
      When call classify_fixture \
        ./fixtures/member-join/etcd-3.5.15/after-add-unstarted.fields \
        node4 http://127.0.0.1:14410
      The status should be success
      The output should eq "unstarted-registered"
    End

    It "classifies the byte-exact etcd 3.6.12 unstarted member fixture"
      When call classify_fixture \
        ./fixtures/member-join/etcd-3.6.12/after-add-unstarted.fields \
        node4 http://127.0.0.1:24410
      The status should be success
      The output should eq "unstarted-registered"
    End

    It "classifies an exact member"
      write_fields \
        '"ID" : 1' \
        '"Name" : "etcd-1"' \
        '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' \
        '"IsLearner" : false' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 \
        http://etcd-1.etcd-headless.default.svc.cluster.local:2380
      The output should eq "exact"
    End

    It "classifies the same name with another URL as a name conflict"
      write_fields \
        '"ID" : 1' \
        '"Name" : "etcd-1"' \
        '"PeerURL" : "http://wrong:2380"' \
        '"IsLearner" : false' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The output should eq "name-conflict"
    End

    It "classifies the same URL with another nonempty name as a peer conflict"
      write_fields \
        '"ID" : 1' \
        '"Name" : "other"' \
        '"PeerURL" : "http://target:2380"' \
        '"IsLearner" : false' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The output should eq "peer-conflict"
    End

    It "does not combine the target name and URL from different member blocks"
      write_fields \
        '"ID" : 1' '"Name" : "etcd-1"' '"PeerURL" : "http://wrong:2380"' '' \
        '"ID" : 2' '"Name" : "other"' '"PeerURL" : "http://target:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The output should eq "name-conflict"
    End

    It "gives a name conflict priority over an unstarted target URL"
      write_fields \
        '"ID" : 1' '"Name" : ""' '"PeerURL" : "http://target:2380"' '' \
        '"ID" : 2' '"Name" : "etcd-1"' '"PeerURL" : "http://wrong:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The output should eq "name-conflict"
    End

    It "gives an exact member plus same-name ghost block a conflict verdict"
      write_fields \
        '"ID" : 1' '"Name" : "etcd-1"' '"PeerURL" : "http://target:2380"' '' \
        '"ID" : 2' '"Name" : "etcd-1"' '"PeerURL" : "http://ghost:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The output should eq "name-conflict"
    End

    It "gives an exact member plus same-URL foreign-name ghost a conflict verdict"
      write_fields \
        '"ID" : 1' '"Name" : "etcd-1"' '"PeerURL" : "http://target:2380"' '' \
        '"ID" : 2' '"Name" : "other"' '"PeerURL" : "http://target:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The output should eq "peer-conflict"
    End

    It "accepts an exact member when one of multiple peer URLs matches"
      write_fields \
        '"ID" : 1' \
        '"Name" : "etcd-1"' \
        '"PeerURL" : "http://old:2380"' \
        '"PeerURL" : "http://target:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The output should eq "exact"
    End

    It "classifies a missing name and URL as absent"
      write_fields \
        '"ClusterID" : 9' \
        '"ID" : 1' \
        '"Name" : "etcd-0"' \
        '"PeerURL" : "http://etcd-0:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The output should eq "absent"
    End


    It "fails closed when output contains no member block"
      write_fields '"ClusterID" : 9' '"MemberID" : 1'
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The status should be failure
      The output should eq ""
    End

    It "fails closed when a target peer block omits the Name field"
      write_fields '"ID" : 1' '"PeerURL" : "http://target:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The status should be failure
      The output should eq ""
    End

    It "fails closed when the Name value is missing"
      write_fields '"ID" : 1' '"Name" :' '"PeerURL" : "http://target:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The status should be failure
      The output should eq ""
    End

    It "fails closed when the Name value is unquoted"
      write_fields '"ID" : 1' '"Name" : etcd-1' '"PeerURL" : "http://target:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The status should be failure
      The output should eq ""
    End

    It "fails closed when the PeerURL value is unquoted"
      write_fields '"ID" : 1' '"Name" : "etcd-1"' '"PeerURL" : http://target:2380' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The status should be failure
      The output should eq ""
    End

    It "fails closed when the PeerURL value is quoted but empty"
      write_fields '"ID" : 1' '"Name" : "other"' '"PeerURL" : ""' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The status should be failure
      The output should eq ""
    End

    It "fails closed when the member ID is not decimal"
      write_fields '"ID" : not-decimal' '"Name" : "etcd-1"' \
        '"PeerURL" : "http://target:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The status should be failure
      The output should eq ""
    End

    It "fails closed when a member block has duplicate Name fields"
      write_fields '"ID" : 1' '"Name" : "other"' '"Name" : "etcd-1"' \
        '"PeerURL" : "http://target:2380"' ''
      When call classify_fixture "$TEST_DIR/member-list.fields" etcd-1 http://target:2380
      The status should be failure
      The output should eq ""
    End
  End

  Describe "add_member()"
    It "fails closed before querying when required action-time inputs are empty"
      unset LEADER_POD_FQDN KB_JOIN_MEMBER_POD_NAME KB_JOIN_MEMBER_POD_FQDN
      When call add_member
      The status should be failure
      The error should include "phase: required-input-empty"
      The error should include "LEADER_POD_FQDN"
      The error should include "KB_JOIN_MEMBER_POD_NAME"
      The error should include "KB_JOIN_MEMBER_POD_FQDN"
      The error should include "next-retry-safe: no"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "0"
    End

    It "returns success without mutation when the exact member exists"
      set_member_states exact
      When call add_member
      The status should be success
      The error should include "already joined"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "1"
    End

    It "returns success without mutation for an unstarted registered member"
      set_member_states unstarted-registered
      When call add_member
      The status should be success
      The error should include "registered but not started"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "1"
    End

    It "fails closed without mutation for a name conflict"
      set_member_states name-conflict
      When call add_member
      The status should be failure
      The error should include "action: memberJoin"
      The error should include "phase: member-name-conflict"
      The error should include "next-retry-safe: no"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
    End

    It "fails closed without mutation for a peer URL conflict"
      set_member_states peer-conflict
      When call add_member
      The status should be failure
      The error should include "phase: member-peer-url-conflict"
      The error should include "next-retry-safe: no"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
    End

    It "fails closed without mutation for a quoted-empty peer URL"
      set_member_states empty-peer-url
      When call add_member
      The status should be failure
      The error should include "phase: member-list-query-failed"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "1"
    End

    It "adds once and accepts an unstarted post-read state"
      set_member_states absent unstarted-registered
      When call add_member
      The status should be success
      The error should include "registered but not started"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq \
        "etcd-0.etcd-headless.default.svc.cluster.local:2379 member add etcd-1 --peer-urls=http://etcd-1.etcd-headless.default.svc.cluster.local:2380"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End

    It "accepts an exact post-read even when the concurrent add returned nonzero"
      set_member_states absent exact
      MEMBER_ADD_RC=1
      When call add_member
      The status should be success
      The error should include "already joined"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End

    It "accepts an unstarted post-read when the concurrent add returned nonzero"
      set_member_states absent unstarted-registered
      MEMBER_ADD_RC=1
      When call add_member
      The status should be success
      The error should include "registered but not started"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End

    It "fails closed when a name conflict appears after add"
      set_member_states absent name-conflict
      When call add_member
      The status should be failure
      The error should include "phase: member-name-conflict"
      The error should include "next-retry-safe: no"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End

    It "fails closed when a peer URL conflict appears after add"
      set_member_states absent peer-conflict
      MEMBER_ADD_RC=1
      When call add_member
      The status should be failure
      The error should include "phase: member-peer-url-conflict"
      The error should include "next-retry-safe: no"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End

    It "classifies add failure followed by absent as transient"
      set_member_states absent absent
      MEMBER_ADD_RC=1
      When call add_member
      The status should be failure
      The error should include "phase: member-add-failed"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End

    It "classifies a successful add not observed by post-read as transient"
      set_member_states absent absent
      When call add_member
      The status should be failure
      The error should include "phase: member-registration-not-observed"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End

    It "classifies a pre-read query failure as transient without mutation"
      set_member_states query-failed
      When call add_member
      The status should be failure
      The error should include "phase: member-list-query-failed"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
    End

    It "classifies a post-read query failure as transient after one add"
      set_member_states absent query-failed
      When call add_member
      The status should be failure
      The error should include "phase: member-post-add-query-failed"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End
  End
End
