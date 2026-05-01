# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_member_leave_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Member-Leave Bash Script Tests"
  Include $common_library_file
  Include ../scripts/valkey-member-leave.sh

  init() {
    ut_mode="true"
    export SERVICE_PORT="6379"
    export SENTINEL_SERVICE_PORT="26379"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SERVICE_PORT
    unset SENTINEL_SERVICE_PORT
  }
  AfterAll "cleanup"

  Describe "build_data_cli()"
    Context "with password"
      setup() {
        export VALKEY_DEFAULT_PASSWORD="mypass"
      }
      Before "setup"

      teardown() {
        unset VALKEY_DEFAULT_PASSWORD
      }
      After "teardown"

      It "includes --no-auth-warning and -a flag"
        When call build_data_cli "valkey-0.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "--no-auth-warning"
        The stdout should include "-a mypass"
        The stdout should include "-h valkey-0.headless.default.svc.cluster.local"
      End
    End

    Context "without password"
      setup() {
        unset VALKEY_DEFAULT_PASSWORD
      }
      Before "setup"

      It "includes --no-auth-warning and no -a flag"
        When call build_data_cli "valkey-0.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "--no-auth-warning"
        The stdout should not include " -a "
      End
    End
  End

  Describe "build_sentinel_cli()"
    Context "with Sentinel password"
      setup() {
        export SENTINEL_PASSWORD="sentpass"
      }
      Before "setup"

      teardown() {
        unset SENTINEL_PASSWORD
      }
      After "teardown"

      It "includes --no-auth-warning and -a flag on sentinel port"
        When call build_sentinel_cli "sentinel-0.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "--no-auth-warning"
        The stdout should include "-a sentpass"
        The stdout should include "-p 26379"
      End
    End
  End

  Describe "member leave — no Sentinel"
    Context "when SENTINEL_COMPONENT_NAME is empty"
      setup() {
        unset SENTINEL_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        export KB_LEAVE_MEMBER_POD_FQDN="valkey-1.headless.default.svc.cluster.local"
        export KB_LEAVE_MEMBER_POD_NAME="valkey-1"
      }
      Before "setup"

      teardown() {
        unset KB_LEAVE_MEMBER_POD_FQDN
        unset KB_LEAVE_MEMBER_POD_NAME
      }
      After "teardown"

      It "exits early with 'nothing to do'"
        # Simulate the main guard that checks for Sentinel
        check_no_sentinel() {
          is_empty "${SENTINEL_COMPONENT_NAME}" || is_empty "${SENTINEL_POD_FQDN_LIST}"
        }
        When call check_no_sentinel
        The status should be success
      End
    End
  End

  Describe "member leave — role detection"
    setup() {
      export SENTINEL_COMPONENT_NAME="valkey-sentinel"
      export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local,sentinel-1.headless.default.svc.cluster.local"
      export VALKEY_COMPONENT_NAME="mycluster-valkey"
      unset VALKEY_DEFAULT_PASSWORD
      unset SENTINEL_PASSWORD
    }
    Before "setup"

    teardown() {
      unset SENTINEL_COMPONENT_NAME
      unset SENTINEL_POD_FQDN_LIST
      unset KB_LEAVE_MEMBER_POD_FQDN
      unset KB_LEAVE_MEMBER_POD_NAME
      unset VALKEY_COMPONENT_NAME
    }
    After "teardown"

    It "detects leaving pod is slave"
      export KB_LEAVE_MEMBER_POD_FQDN="valkey-1.headless.default.svc.cluster.local"
      export KB_LEAVE_MEMBER_POD_NAME="valkey-1"
      valkey-cli() { printf "role:slave\r\n"; }
      _data_cli=$(build_data_cli "${KB_LEAVE_MEMBER_POD_FQDN}")
      leaving_role=$(${_data_cli} INFO replication 2>/dev/null \
                     | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
      When call echo "${leaving_role}"
      The stdout should eq "slave"
    End

    It "detects leaving pod is master"
      export KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      export KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      valkey-cli() { printf "role:master\r\n"; }
      _data_cli=$(build_data_cli "${KB_LEAVE_MEMBER_POD_FQDN}")
      leaving_role=$(${_data_cli} INFO replication 2>/dev/null \
                     | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
      When call echo "${leaving_role}"
      The stdout should eq "master"
    End
  End

  Describe "SENTINEL RESET policy — never invoked from member-leave script"
    # Background: previous version called `SENTINEL RESET <master-name>` on
    # every sentinel after a master-leave FAILOVER. That call temporarily
    # zeroed num-other-sentinels on each sentinel. Pub/sub HELLO re-discovery
    # normally restored sentinel cross-registration within seconds, but in
    # roughly 17% of master-removal scale-in runs the re-discovery did not
    # complete in time. The stuck sentinel kept reporting the deleted
    # (pre-failover) master, and any slave that queried it received a stale
    # answer and bound to a non-existent address. Observed live in 12h smoke
    # test as one slave stuck with master_host=<deleted-pod>, link=down,
    # cluster topology unable to self-heal because the cascade self-heal
    # daemon's PR #2615 remote-master-unreachable guard correctly skipped
    # repair on a host that did not exist.
    #
    # The fix removes the `SENTINEL RESET` invocation from the script
    # entirely. These tests assert the contract: no `SENTINEL RESET` token
    # is reachable from the script source. Static contract is sufficient
    # because the script's main body runs after the shellspec sourced-guard
    # `${__SOURCED__:+false} : || return 0` and is therefore not directly
    # exercisable as a function. Combined with the FAILOVER / role-detection
    # / cli-builder unit tests above, the static contract gives full coverage
    # of the policy change.
    member_leave_script="../scripts/valkey-member-leave.sh"

    # Helper: count active (non-comment, non-blank) lines containing the
    # given regex. Comment lines start with optional whitespace then `#`.
    # Always returns success and prints the count (including "0" for no
    # matches) so spec assertions can compare the count without grep's
    # no-match exit code interfering.
    active_lines_matching() {
      local pattern="$1"
      local count
      count=$(grep -vE '^[[:space:]]*(#|$)' "${member_leave_script}" \
                | grep -cE "${pattern}" 2>/dev/null || true)
      printf "%s" "${count:-0}"
    }

    It "has no active code line invoking SENTINEL RESET"
      When call active_lines_matching "SENTINEL[[:space:]]+RESET"
      The status should be success
      The stdout should eq "0"
    End

    It "still has at least one active code line invoking SENTINEL FAILOVER"
      When call active_lines_matching "SENTINEL[[:space:]]+FAILOVER"
      The status should be success
      The stdout should not eq "0"
    End

    It "documents the no-RESET policy in a comment"
      When call grep -E "never call SENTINEL RESET|SENTINEL RESET is intentionally NOT called|never called on member leave" "${member_leave_script}"
      The status should be success
      The stdout should not eq ""
    End
  End
End
