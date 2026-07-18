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
    export MEMBER_JOIN_ENDPOINT_LOG="$TEST_DIR/endpoint.log"
    export MEMBER_JOIN_READ_COUNT="$TEST_DIR/read-count"
    export MEMBER_JOIN_STATES="$TEST_DIR/states"
    : > "$MEMBER_JOIN_CALL_LOG"
    : > "$MEMBER_JOIN_ENDPOINT_LOG"
    printf '0' > "$MEMBER_JOIN_READ_COUNT"
    : > "$MEMBER_JOIN_STATES"

    export LEADER_POD_FQDN="etcd-0.etcd-headless.default.svc.cluster.local"
    export KB_JOIN_MEMBER_POD_NAME="etcd-1"
    export KB_JOIN_MEMBER_POD_FQDN="etcd-1.etcd-headless.default.svc.cluster.local"
    export PEER_ENDPOINT=""
    export MEMBER_ADD_RC=0
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
      printf '%s %s\n' "$endpoint" "$*" >> "$MEMBER_JOIN_ENDPOINT_LOG"

      if [ "$1 $2" = "endpoint status" ]; then
        case "$LOCAL_LEADER_STATUS" in
          leader)
            printf '%s\n' '"MemberID" : 1' '"Leader" : 1'
            ;;
          follower)
            printf '%s\n' '"MemberID" : 1' '"Leader" : 2'
            ;;
          zero)
            printf '%s\n' '"MemberID" : 0' '"Leader" : 0'
            ;;
          adjacent-uint64-follower)
            printf '%s\n' \
              '"MemberID" : 18150782143940212502' \
              '"Leader" : 18150782143940212503'
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
        local index state
        index=$(cat "$MEMBER_JOIN_READ_COUNT")
        index=$((index + 1))
        printf '%s' "$index" > "$MEMBER_JOIN_READ_COUNT"
        state=$(sed -n "${index}p" "$MEMBER_JOIN_STATES")
        case "$state" in
          exact)
            printf '%s\n' \
              '"ID" : 0' \
              '"Name" : "etcd-0"' \
              '"PeerURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2379"' '' \
              '"ID" : 1' \
              '"Name" : "etcd-1"' \
              '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2379"' ''
            ;;
          exact-only)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "etcd-1"' \
              '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2379"' ''
            ;;
          unstarted-registered)
            printf '%s\n' \
              '"ID" : 0' \
              '"Name" : "etcd-0"' \
              '"PeerURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2379"' '' \
              '"ID" : 1' \
              '"Name" : ""' \
              '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' ''
            ;;
          unstarted-target-only)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : ""' \
              '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' ''
            ;;
          name-conflict)
            printf '%s\n' \
              '"ID" : 0' \
              '"Name" : "etcd-0"' \
              '"PeerURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2379"' '' \
              '"ID" : 1' \
              '"Name" : "etcd-1"' \
              '"PeerURL" : "http://wrong:2380"' \
              '"ClientURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2379"' ''
            ;;
          peer-conflict)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "other"' \
              '"PeerURL" : "http://etcd-1.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "http://other.etcd-headless.default.svc.cluster.local:2379"' ''
            ;;
          absent)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "etcd-0"' \
              '"PeerURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2379"' ''
            ;;
          client-address-collision)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "etcd-0"' \
              '"PeerURL" : "http://etcd-0.internal:2380"' \
              '"ClientURL" : "http://shared-lb.example:2379"' ''
            ;;
          unrelated-unstarted)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "etcd-0"' \
              '"PeerURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2379"' '' \
              '"ID" : 2' \
              '"Name" : ""' \
              '"PeerURL" : "http://etcd-2.etcd-headless.default.svc.cluster.local:2380"' ''
            ;;
          all-contacts-empty)
            printf '%s\n' \
              '"ID" : 2' \
              '"Name" : ""' \
              '"PeerURL" : "http://etcd-2.etcd-headless.default.svc.cluster.local:2380"' ''
            ;;
          malformed-client-url)
            printf '%s\n' \
              '"ID" : 1' \
              '"Name" : "etcd-0"' \
              '"PeerURL" : "http://etcd-0.etcd-headless.default.svc.cluster.local:2380"' \
              '"ClientURL" : "not-a-url"' ''
            ;;
          over-limit)
            local member
            for member in 0 2 3 4 5 6 7 8 9; do
              printf '%s\n' \
                "\"ID\" : $member" \
                "\"Name\" : \"etcd-$member\"" \
                "\"PeerURL\" : \"http://etcd-$member.example:2380\"" \
                "\"ClientURL\" : \"http://etcd-$member.example:2379\"" ''
            done
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
    unset TEST_DIR MEMBER_JOIN_CALL_LOG MEMBER_JOIN_ENDPOINT_LOG MEMBER_JOIN_READ_COUNT MEMBER_JOIN_STATES
    unset LEADER_POD_FQDN KB_JOIN_MEMBER_POD_NAME KB_JOIN_MEMBER_POD_FQDN
    unset PEER_ENDPOINT MEMBER_ADD_RC LOCAL_LEADER_STATUS
    unset -f get_protocol log exec_etcdctl
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

  build_contact_fixture() {
    local fixture="$1"
    local exclude_name="$2"
    local client_protocol="$3"
    local peer_protocol="${4:-$client_protocol}"
    build_current_contact_candidates "$exclude_name" "$client_protocol" "" \
      "contacts" "$peer_protocol" < "$fixture"
  }

  build_contact_fixture_excluding_id() {
    local fixture="$1"
    local exclude_id="$2"
    build_current_contact_candidates "" http "$exclude_id" < "$fixture"
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

  Describe "build_current_contact_candidates()"
    It "canonicalizes and stably deduplicates hostnames before returning contacts"
      write_fields \
        '"ID" : 1' \
        '"Name" : "etcd-0"' \
        '"PeerURL" : "http://ETCD-0.EXAMPLE.:2380"' \
        '"ClientURL" : "http://ETCD-0.EXAMPLE.:2379"' '' \
        '"ID" : 2' \
        '"Name" : "etcd-2"' \
        '"PeerURL" : "http://etcd-2.example:2380"' \
        '"ClientURL" : "http://etcd-0.example:2379"' ''
      When call build_contact_fixture "$TEST_DIR/member-list.fields" "" http
      The status should be success
      The output should eq "http://etcd-0.example:2379"
    End

    It "canonicalizes IPv4 octets"
      write_fields \
        '"ID" : 1' \
        '"Name" : "etcd-0"' \
        '"PeerURL" : "http://010.000.000.001:2380"' \
        '"ClientURL" : "http://010.000.000.001:2379"' ''
      When call build_contact_fixture "$TEST_DIR/member-list.fields" "" http
      The status should be success
      The output should eq "http://10.0.0.1:2379"
    End

    It "accepts one consistent TLS protocol"
      write_fields \
        '"ID" : 1' \
        '"Name" : "etcd-0"' \
        '"PeerURL" : "https://etcd-0.example:2380"' \
        '"ClientURL" : "https://etcd-0.example:2379"' ''
      When call build_contact_fixture "$TEST_DIR/member-list.fields" "" https
      The status should be success
      The output should eq "https://etcd-0.example:2379"
    End

    It "accepts independently configured client TLS and peer plaintext"
      write_fields \
        '"ID" : 1' \
        '"Name" : "etcd-0"' \
        '"PeerURL" : "http://etcd-0.example:2380"' \
        '"ClientURL" : "https://etcd-0.example:2379"' ''
      When call build_contact_fixture "$TEST_DIR/member-list.fields" "" https http
      The status should be success
      The output should eq "https://etcd-0.example:2379"
    End

    It "fails closed when authoritative URLs mix protocols"
      write_fields \
        '"ID" : 1' \
        '"Name" : "etcd-0"' \
        '"PeerURL" : "https://etcd-0.example:2380"' \
        '"ClientURL" : "https://etcd-0.example:2379"' '' \
        '"ID" : 2' \
        '"Name" : "etcd-2"' \
        '"PeerURL" : "http://etcd-2.example:2380"' \
        '"ClientURL" : "http://etcd-2.example:2379"' ''
      When call build_contact_fixture "$TEST_DIR/member-list.fields" "" https
      The status should be failure
      The output should eq ""
    End

    It "fails closed instead of numerically accepting a noncanonical client port"
      write_fields \
        '"ID" : 1' \
        '"Name" : "etcd-0"' \
        '"PeerURL" : "http://etcd-0.example:2380"' \
        '"ClientURL" : "http://etcd-0.example:02379"' ''
      When call build_contact_fixture "$TEST_DIR/member-list.fields" "" http
      The status should be failure
      The output should eq ""
    End

    It "excludes one raw uint64 ID without collapsing an adjacent ID"
      write_fields \
        '"ID" : 18150782143940212502' \
        '"Name" : "etcd-0"' \
        '"PeerURL" : "http://etcd-0.example:2380"' \
        '"ClientURL" : "http://etcd-0.example:2379"' '' \
        '"ID" : 18150782143940212503' \
        '"Name" : "etcd-1"' \
        '"PeerURL" : "http://etcd-1.example:2380"' \
        '"ClientURL" : "http://etcd-1.example:2379"' ''
      When call build_contact_fixture_excluding_id \
        "$TEST_DIR/member-list.fields" 18150782143940212502
      The status should be success
      The output should eq "http://etcd-1.example:2379"
    End
  End

  Describe "get_endpoint_adapt_lb()"
    It "matches the exact pod key when ordinals overlap"
      When call get_endpoint_adapt_lb \
        "etcd-10:10.0.0.10,etcd-1:10.0.0.1" etcd-1 etcd-1.internal
      The status should be success
      The output should eq "10.0.0.1"
      The error should include "Using exact LoadBalancer endpoint"
    End

    It "fails closed for duplicate exact keys"
      When call get_endpoint_adapt_lb \
        "etcd-1:10.0.0.1,etcd-1:10.0.0.2" etcd-1 etcd-1.internal
      The status should be failure
    End

    It "fails closed for malformed mapping tokens"
      When call get_endpoint_adapt_lb \
        "etcd-1:bad:host,etcd-2:10.0.0.2" etcd-1 etcd-1.internal
      The status should be failure
    End

    It "fails closed when the target mapping collides with another pod"
      When call get_endpoint_adapt_lb \
        "etcd-1:10.0.0.1,etcd-2:10.0.0.1" etcd-1 etcd-1.internal
      The status should be failure
    End

    It "canonicalizes a hostname mapping"
      When call get_endpoint_adapt_lb \
        "etcd-1:ETCD-1.EXAMPLE." etcd-1 etcd-1.internal
      The status should be success
      The output should eq "etcd-1.example"
      The error should include "Using exact LoadBalancer endpoint"
    End

    It "falls back only to a nonempty action-time FQDN when mapping is missing"
      When call get_endpoint_adapt_lb \
        "etcd-2:10.0.0.2" etcd-1 etcd-1.internal
      The status should be success
      The output should eq "etcd-1.internal"
      The error should include "mapping-missing-fallback-fqdn"
    End
  End

  Describe "add_member()"
    It "uses the action-time local leader instead of stale topology snapshots"
      export LEADER_POD_FQDN="deleted-0.old-headless.default.svc.cluster.local"
      export PEER_FQDNS="deleted-0.old-headless.default.svc.cluster.local,etcd-2.old-headless.default.svc.cluster.local"
      set_member_states exact
      When call add_member
      The status should be success
      The error should include "already joined"
      The contents of file "$MEMBER_JOIN_ENDPOINT_LOG" should include \
        "127.0.0.1:2379 endpoint status -w fields"
      The contents of file "$MEMBER_JOIN_ENDPOINT_LOG" should include \
        "127.0.0.1:2379 member list -w fields"
      The contents of file "$MEMBER_JOIN_ENDPOINT_LOG" should not include "deleted-0"
    End

    It "fails closed before querying when required action-time inputs are empty"
      unset LEADER_POD_FQDN KB_JOIN_MEMBER_POD_NAME KB_JOIN_MEMBER_POD_FQDN
      When call add_member
      The status should be failure
      The error should include "phase: required-input-empty"
      The error should not include "LEADER_POD_FQDN"
      The error should include "KB_JOIN_MEMBER_POD_NAME"
      The error should include "KB_JOIN_MEMBER_POD_FQDN"
      The error should include "next-retry-safe: no"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "0"
    End

    It "defers before mutation when the selected action pod is not the current leader"
      LOCAL_LEADER_STATUS=follower
      set_member_states absent
      When call add_member
      The status should be failure
      The error should include "phase: selected-contact-not-current-leader"
      The error should include "next-retry-safe: yes"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "0"
    End

    It "rejects a zero MemberID and Leader sentinel before mutation"
      LOCAL_LEADER_STATUS=zero
      set_member_states absent
      When call add_member
      The status should be failure
      The error should include "phase: selected-contact-not-current-leader"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "0"
    End

    It "does not collapse adjacent uint64 MemberID and Leader values"
      LOCAL_LEADER_STATUS=adjacent-uint64-follower
      set_member_states absent
      When call add_member
      The status should be failure
      The error should include "phase: selected-contact-not-current-leader"
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

    It "closes an exact replay even when the target is the only current contact"
      set_member_states exact-only
      When call add_member
      The status should be success
      The error should include "already joined"
      The error should not include "contact-candidate-empty"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "1"
    End

    It "closes an unstarted replay even when no member can contribute a contact"
      set_member_states unstarted-target-only
      When call add_member
      The status should be success
      The error should include "registered but not started"
      The error should not include "contact-candidate-empty"
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
      The error should include "phase: member-list-invalid"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "1"
    End

    It "adds once and accepts an unstarted post-read state"
      set_member_states absent unstarted-registered
      When call add_member
      The status should be success
      The error should include "registered but not started"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should include \
        "member add etcd-1 --peer-urls=http://etcd-1.etcd-headless.default.svc.cluster.local:2380"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should include \
        "--dial-timeout=2s --command-timeout=6s"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End

    It "ignores an unrelated valid unstarted block when a started contact exists"
      set_member_states unrelated-unstarted unstarted-registered
      When call add_member
      The status should be success
      The error should include "registered but not started"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should include "member add etcd-1"
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "2"
    End

    It "fails distinctly when every non-target member has empty client URLs"
      set_member_states all-contacts-empty
      When call add_member
      The status should be failure
      The error should include "phase: contact-candidate-empty"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
    End

    It "fails closed for a malformed nonempty client URL"
      set_member_states malformed-client-url
      When call add_member
      The status should be failure
      The error should include "phase: member-list-invalid"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
    End

    It "fails closed when the target advertised host collides with a current member contact"
      PEER_ENDPOINT="etcd-1:shared-lb.example"
      set_member_states client-address-collision
      When call add_member
      The status should be failure
      The error should include "phase: target-address-collision"
      The error should include "next-retry-safe: no"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
      The contents of file "$MEMBER_JOIN_READ_COUNT" should eq "1"
    End

    It "fails closed instead of truncating more than eight contacts"
      set_member_states over-limit
      When call add_member
      The status should be failure
      The error should include "phase: contact-candidate-over-limit"
      The contents of file "$MEMBER_JOIN_CALL_LOG" should eq ""
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
