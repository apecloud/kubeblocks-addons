# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_member_leave_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Member-Leave Bash Script Tests"
  Include $common_library_file
  Include ../scripts/sentinel-endpoint.sh
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
    cmpd_file="../templates/cmpd.yaml"

    It "returns success only after Sentinel reports a different primary"
      sentinel_master_state() { echo "different"; }
      When call handle_master_leave
      The status should be success
      The stdout should include "safe to continue"
    End

    It "defers after Sentinel accepts a new failover instead of waiting in-process"
      sentinel_master_state() { echo "leaving"; }
      run_selected_sentinel_cli() { echo "OK"; }
      When call handle_master_leave
      The status should be failure
      The stdout should include "SENTINEL FAILOVER response: OK"
      The stderr should include "phase: failover-issued"
      The stderr should include "next-retry-safe: yes"
    End

    It "classifies a rejected failover as operator attention"
      sentinel_master_state() { echo "leaving"; }
      run_selected_sentinel_cli() { echo "ERR no good replica"; }
      When call handle_master_leave
      The status should be failure
      The stdout should include "SENTINEL FAILOVER response: ERR no good replica"
      The stderr should include "phase: failover-rejected"
      The stderr should include "next-retry-safe: no"
    End

    It "requires a strict configured-Sentinel majority that still names the leaving primary"
      master_name="mycluster-valkey"
      KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      leaving_ip="10.0.0.10"
      canonicalize_sentinel_endpoints "sentinel-0,sentinel-1,sentinel-2"
      run_sentinel_cli_for_host() {
        case "$1" in
          sentinel-0|sentinel-1) printf "10.0.0.10\n6379\n" ;;
          sentinel-2) printf "10.0.0.11\n6379\n" ;;
        esac
      }
      When call sentinel_master_state
      The status should be success
      The stdout should eq "leaving"
    End

    It "accepts a strict configured-Sentinel majority that names the same replacement primary"
      master_name="mycluster-valkey"
      KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      leaving_ip="10.0.0.10"
      canonicalize_sentinel_endpoints "sentinel-0,sentinel-1,sentinel-2"
      run_sentinel_cli_for_host() {
        case "$1" in
          sentinel-0|sentinel-1) printf "10.0.0.11\n6379\n" ;;
          sentinel-2) printf "10.0.0.10\n6379\n" ;;
        esac
      }
      When call sentinel_master_state
      The status should be success
      The stdout should eq "different"
    End

    It "maps a NodePort Sentinel majority to the leaving pod identity"
      master_name="mycluster-valkey"
      KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local"
      VALKEY_ADVERTISED_PORT="valkey-advertised-0:31000,valkey-advertised-1:31001"
      leaving_ip="10.0.0.10"
      canonicalize_sentinel_endpoints "sentinel-0,sentinel-1,sentinel-2"
      run_sentinel_cli_for_host() {
        case "$1" in
          sentinel-0|sentinel-1) printf "10.0.0.20\n31000\n" ;;
          sentinel-2) printf "10.0.0.21\n31001\n" ;;
        esac
      }
      When call sentinel_master_state
      The status should be success
      The stdout should eq "leaving"
    End

    It "maps a LoadBalancer Sentinel majority to the leaving pod identity"
      master_name="mycluster-valkey"
      KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local"
      VALKEY_LB_ADVERTISED_PORT="valkey-lb-advertised-0:6379,valkey-lb-advertised-1:6379"
      VALKEY_LB_ADVERTISED_HOST="valkey-lb-advertised-0:lb-0.example.com,valkey-lb-advertised-1:lb-1.example.com"
      leaving_ip="10.0.0.10"
      canonicalize_sentinel_endpoints "sentinel-0,sentinel-1,sentinel-2"
      run_sentinel_cli_for_host() {
        case "$1" in
          sentinel-0|sentinel-1) printf "lb-0.example.com\n6379\n" ;;
          sentinel-2) printf "lb-1.example.com\n6379\n" ;;
        esac
      }
      When call sentinel_master_state
      The status should be success
      The stdout should eq "leaving"
    End

    It "treats duplicate NodePort mappings as unknown"
      master_name="mycluster-valkey"
      KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local"
      VALKEY_ADVERTISED_PORT="valkey-advertised-0:31000,valkey-advertised-1:31000"
      leaving_ip="10.0.0.10"
      canonicalize_sentinel_endpoints "sentinel-0,sentinel-1,sentinel-2"
      run_sentinel_cli_for_host() { printf "10.0.0.20\n31000\n"; }
      When call sentinel_master_state
      The status should be success
      The stdout should eq "unknown"
    End

    It "treats split Sentinel answers as unknown instead of already-safe"
      master_name="mycluster-valkey"
      KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      leaving_ip="10.0.0.10"
      canonicalize_sentinel_endpoints "sentinel-0,sentinel-1,sentinel-2"
      run_sentinel_cli_for_host() {
        case "$1" in
          sentinel-0) printf "10.0.0.10\n6379\n" ;;
          sentinel-1) printf "10.0.0.11\n6379\n" ;;
          sentinel-2) printf "10.0.0.12\n6379\n" ;;
        esac
      }
      When call sentinel_master_state
      The status should be success
      The stdout should eq "unknown"
    End

    It "counts unreachable and malformed replies against the configured majority"
      master_name="mycluster-valkey"
      KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      leaving_ip="10.0.0.10"
      canonicalize_sentinel_endpoints "sentinel-0,sentinel-1,sentinel-2"
      run_sentinel_cli_for_host() {
        case "$1" in
          sentinel-0) printf "10.0.0.11\n6379\n" ;;
          sentinel-1) return 1 ;;
          sentinel-2) printf "10.0.0.11\n6380\n" ;;
        esac
      }
      When call sentinel_master_state
      The status should be success
      The stdout should eq "unknown"
    End

    It "rejects duplicate or empty configured Sentinel endpoints"
      reject_invalid_sentinel_lists() {
        ! canonicalize_sentinel_endpoints "sentinel-0,sentinel-0" &&
          ! canonicalize_sentinel_endpoints "sentinel-0,,sentinel-2" &&
          ! canonicalize_sentinel_endpoints ",sentinel-1" &&
          ! canonicalize_sentinel_endpoints "sentinel-1,"
      }
      When call reject_invalid_sentinel_lists
      The status should be success
    End

    It "treats empty Sentinel master answers as unknown instead of already-safe"
      master_name="mycluster-valkey"
      KB_LEAVE_MEMBER_POD_NAME="valkey-0"
      KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      leaving_ip=""
      canonicalize_sentinel_endpoints "sentinel-0,sentinel-1,sentinel-2"
      run_sentinel_cli_for_host() { printf "(nil)\n"; }
      When call sentinel_master_state
      The status should be success
      The stdout should eq "unknown"
    End

    It "defers when Sentinel cannot yet name a concrete master"
      sentinel_master_state() { echo "unknown"; }
      When call handle_master_leave
      The status should be failure
      The stderr should include "phase: master-not-yet-observable"
      The stderr should include "next-retry-safe: yes"
    End

    It "has no active in-process convergence sleep loop"
      no_active_wait_loop() {
        ! grep -vE '^[[:space:]]*(#|$)' "${member_leave_script}" \
          | grep -E 'sleep_when_ut_mode_false|for .*seq' >/dev/null
      }
      When call no_active_wait_loop
      The status should be success
    End

    It "declares a truthful action timeout and retry policy"
      member_leave_action_contract() {
        awk '
          /^    memberLeave:/ { in_action=1; next }
          in_action && /^      timeoutSeconds: 50$/ { timeout=1 }
          in_action && /^      retryPolicy:/ { retry=1 }
          in_action && /^        maxRetries: 10$/ { retries=1 }
          in_action && /^        retryInterval: 3$/ { interval=1 }
          in_action && /^  runtime:/ {
            exit !(timeout && retry && retries && interval)
          }
          END {
            if (!(timeout && retry && retries && interval)) exit 1
          }
        ' "${cmpd_file}"
      }
      When call member_leave_action_contract
      The status should be success
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
