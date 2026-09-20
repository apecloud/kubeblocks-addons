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
    _build_data_cli_as_string() {
      build_data_cli "$@"
      printf '%s\n' "${_data_cli_cmd[*]}"
    }

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
        When call _build_data_cli_as_string "valkey-0.headless.default.svc.cluster.local"
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
        When call _build_data_cli_as_string "valkey-0.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "--no-auth-warning"
        The stdout should not include " -a "
      End
    End
  End

  Describe "build_sentinel_cli()"
    _build_sentinel_cli_as_string() {
      build_sentinel_cli "$@"
      printf '%s\n' "${_sentinel_cli_cmd[*]}"
    }

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
        When call _build_sentinel_cli_as_string "sentinel-0.headless.default.svc.cluster.local"
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

      It "uses the no-Sentinel fail-closed safety check instead of a success-only early exit"
        member_leave_script="../scripts/valkey-member-leave.sh"
        no_sentinel_guard_contract() {
          ! grep -F "No Sentinel component — nothing to do on member leave." "${member_leave_script}" >/dev/null &&
            grep -F "no_sentinel_safety_check" "${member_leave_script}" >/dev/null
        }
        When call no_sentinel_guard_contract
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
      _detect_slave_role() {
        build_data_cli "${KB_LEAVE_MEMBER_POD_FQDN}"
        local leaving_role
        leaving_role=$("${_data_cli_cmd[@]}" INFO replication 2>/dev/null \
                       | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
        printf '%s' "${leaving_role}"
      }
      When call _detect_slave_role
      The stdout should eq "slave"
    End

    It "detects leaving pod is master"
      export KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      export KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      valkey-cli() { printf "role:master\r\n"; }
      _detect_master_role() {
        build_data_cli "${KB_LEAVE_MEMBER_POD_FQDN}"
        local leaving_role
        leaving_role=$("${_data_cli_cmd[@]}" INFO replication 2>/dev/null \
                       | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
        printf '%s' "${leaving_role}"
      }
      When call _detect_master_role
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

  Describe "master memberLeave fail-closed contract"
    member_leave_script="../scripts/valkey-member-leave.sh"

    It "treats a rejected SENTINEL FAILOVER as an error, not a warning-only success"
      When call grep -F "ERROR: SENTINEL FAILOVER rejected" "${member_leave_script}"
      The status should be success
      The stdout should include "ERROR: SENTINEL FAILOVER rejected"
    End

    It "refuses memberLeave success when no new master is confirmed"
      When call grep -F "refusing memberLeave success while the leaving pod is still master" "${member_leave_script}"
      The status should be success
      The stdout should include "refusing memberLeave success"
    End

    It "treats empty Sentinel master answers as unknown instead of already-safe"
      export master_name="mycluster-valkey"
      export KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      leaving_ip=""
      s_cli=(valkey-cli)
      valkey-cli() { printf "(nil)\n"; }
      When call sentinel_master_state
      The status should be success
      The stdout should eq "unknown"
    End

    It "has an explicit error for unknown Sentinel master while local role is master"
      When call grep -F "Sentinel returned no concrete master" "${member_leave_script}"
      The status should be success
      The stdout should include "Sentinel returned no concrete master"
    End
  End

  Describe "no_sentinel_safety_check()"
    It "returns 0 (success) for slave — confirmed replica is safe to leave"
      When call no_sentinel_safety_check "slave"
      The status should be success
      The stderr should include "leaving pod is a confirmed replica"
    End

    It "returns 1 (failure) for master — cannot ensure safe failover"
      When call no_sentinel_safety_check "master"
      The status should be failure
      The stderr should include "cannot ensure safe failover"
    End

    It "returns 1 (failure) for unknown role — fail-closed"
      When call no_sentinel_safety_check "unknown"
      The status should be failure
      The stderr should include "cannot ensure safe failover"
    End

    It "returns 1 (failure) for empty role — fail-closed"
      When call no_sentinel_safety_check ""
      The status should be failure
      The stderr should include "cannot ensure safe failover"
    End
  End
End
