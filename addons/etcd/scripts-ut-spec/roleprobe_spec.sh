# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "roleprobe_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Etcd Role Probe Script Tests"
  Include ../scripts/roleprobe.sh

  setup() {
    TEST_DIR=$(mktemp -d)
    export TEST_DIR
    export ROLEPROBE_ENTRYPOINT_DIR="$TEST_DIR/scripts"
    export ROLEPROBE_ETCDCTL_RC=0
    export ROLEPROBE_ETCDCTL_STDOUT=
    export ROLEPROBE_ETCDCTL_STDERR=

    mkdir -p "$ROLEPROBE_ENTRYPOINT_DIR"
    cp ../scripts/roleprobe.sh "$ROLEPROBE_ENTRYPOINT_DIR/roleprobe.sh"
    cat > "$ROLEPROBE_ENTRYPOINT_DIR/common.sh" <<'COMMON'
setup_shellspec() { :; }
load_common_library() { :; }
exec_etcdctl() {
  if [ "$*" != "127.0.0.1:2379 endpoint status -w fields --command-timeout=300ms --dial-timeout=100ms" ]; then
    printf 'unexpected etcdctl arguments: %s\n' "$*" >&2
    return 64
  fi
  printf '%s' "${ROLEPROBE_ETCDCTL_STDOUT:-}"
  printf '%s' "${ROLEPROBE_ETCDCTL_STDERR:-}" >&2
  return "${ROLEPROBE_ETCDCTL_RC:-0}"
}
COMMON

    exec_etcdctl() {
      printf '%s' "${ROLEPROBE_ETCDCTL_STDOUT:-}"
      printf '%s' "${ROLEPROBE_ETCDCTL_STDERR:-}" >&2
      return "${ROLEPROBE_ETCDCTL_RC:-0}"
    }
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    unset TEST_DIR ROLEPROBE_ENTRYPOINT_DIR ROLEPROBE_ETCDCTL_RC
    unset ROLEPROBE_ETCDCTL_STDOUT ROLEPROBE_ETCDCTL_STDERR
    unset -f exec_etcdctl
  }
  AfterEach "cleanup"

  endpoint_status() {
    printf '"MemberID" : %s\n"Leader" : %s\n"IsLearner" : %s\n' "$1" "$2" "$3"
  }

  run_roleprobe_entrypoint() {
    cmp -s ../scripts/roleprobe.sh "$ROLEPROBE_ENTRYPOINT_DIR/roleprobe.sh" ||
      return 99
    bash "$ROLEPROBE_ENTRYPOINT_DIR/roleprobe.sh"
  }

  assert_role_failure() {
    ROLEPROBE_ETCDCTL_STDOUT="$1"
    export ROLEPROBE_ETCDCTL_STDOUT
    roleprobe_main
  }

  Describe "production get_etcd_role()"
    It "detects an official-shape leader"
      ROLEPROBE_ETCDCTL_STDOUT=$'"Endpoint" : "127.0.0.1:2379"\n"ClusterID" : 9\n'
      ROLEPROBE_ETCDCTL_STDOUT+="$(endpoint_status 1002 1002 false)"
      When call get_etcd_role
      The status should be success
      The output should eq "leader"
    End

    It "detects an official-shape follower"
      ROLEPROBE_ETCDCTL_STDOUT=$(endpoint_status 1001 1002 false)
      When call get_etcd_role
      The status should be success
      The output should eq "follower"
    End

    It "detects an official-shape learner"
      ROLEPROBE_ETCDCTL_STDOUT=$(endpoint_status 1003 1002 true)
      When call get_etcd_role
      The status should be success
      The output should eq "learner"
    End

    It "propagates an etcdctl failure"
      ROLEPROBE_ETCDCTL_RC=23
      ROLEPROBE_ETCDCTL_STDERR="controlled etcdctl failure"
      When call get_etcd_role
      The status should be failure
      The output should eq ""
      The stderr should include "controlled etcdctl failure"
      The stderr should include "Failed to get endpoint status"
    End

    It "rejects a missing MemberID"
      When call assert_role_failure $'"Leader" : 1002\n"IsLearner" : false'
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End

    It "rejects a missing Leader"
      When call assert_role_failure $'"MemberID" : 1002\n"IsLearner" : false'
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End

    It "rejects a missing IsLearner"
      When call assert_role_failure $'"MemberID" : 1002\n"Leader" : 1002'
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End

    It "rejects a MemberID suffix"
      When call assert_role_failure "$(endpoint_status 1002garbage 1002 false)"
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End

    It "rejects a Leader suffix"
      When call assert_role_failure "$(endpoint_status 1002 1002garbage false)"
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End

    It "rejects an invalid learner boolean"
      When call assert_role_failure "$(endpoint_status 1002 1002 falsegarbage)"
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End

    It "rejects duplicate MemberID fields"
      When call assert_role_failure $'"MemberID" : 1002\n"MemberID" : 1003\n"Leader" : 1002\n"IsLearner" : false'
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End

    It "rejects a repeated identical Leader field"
      When call assert_role_failure $'"MemberID" : 1002\n"Leader" : 1002\n"Leader" : 1002\n"IsLearner" : false'
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End

    It "rejects conflicting duplicate Leader fields"
      When call assert_role_failure $'"MemberID" : 1002\n"Leader" : 1002\n"Leader" : 1003\n"IsLearner" : false'
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End

    It "rejects conflicting duplicate IsLearner fields"
      When call assert_role_failure $'"MemberID" : 1002\n"Leader" : 1002\n"IsLearner" : false\n"IsLearner" : true'
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End
  End

  Describe "production roleprobe entrypoint"
    It "emits the classified role"
      ROLEPROBE_ETCDCTL_STDOUT=$(endpoint_status 1002 1002 false)
      When call run_roleprobe_entrypoint
      The status should be success
      The output should eq "leader"
      The stderr should eq ""
    End

    It "emits follower from the official field shape"
      ROLEPROBE_ETCDCTL_STDOUT=$(endpoint_status 1001 1002 false)
      When call run_roleprobe_entrypoint
      The status should be success
      The output should eq "follower"
      The stderr should eq ""
    End

    It "emits learner from the official field shape"
      ROLEPROBE_ETCDCTL_STDOUT=$(endpoint_status 1003 1002 true)
      When call run_roleprobe_entrypoint
      The status should be success
      The output should eq "learner"
      The stderr should eq ""
    End

    It "propagates etcdctl rc and keeps stdout empty"
      ROLEPROBE_ETCDCTL_RC=23
      ROLEPROBE_ETCDCTL_STDERR="controlled entrypoint failure"
      When call run_roleprobe_entrypoint
      The status should be failure
      The output should eq ""
      The stderr should include "controlled entrypoint failure"
      The stderr should include "Failed to get endpoint status"
    End

    It "fails closed on malformed rc0 status"
      ROLEPROBE_ETCDCTL_STDOUT=$'"MemberID" : 1002garbage\n"Leader" : 1002\n"IsLearner" : false'
      When call run_roleprobe_entrypoint
      The status should be failure
      The output should eq ""
      The stderr should include "Failed to extract role fields"
    End
  End
End
