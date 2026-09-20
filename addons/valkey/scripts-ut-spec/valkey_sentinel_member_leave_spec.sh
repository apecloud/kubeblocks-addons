# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to
# validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_sentinel_member_leave_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files
# from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Sentinel Member Leave Script Tests"

  Include ../scripts/valkey-sentinel-member-leave.sh
  Include $common_library_file

  # Mock valkey-cli.  Calls are appended to $CLI_LOG (a file, not a variable:
  # calls made inside command substitutions run in a subshell, so only a file
  # survives).  `SENTINEL masters` answers come from $MOCK_MASTERS_OUTPUT;
  # per-host overrides are listed in $MOCK_MASTERS_BY_HOST ("<fragment>=<output>"
  # newline-separated, first match wins).  Everything else answers OK.
  valkey-cli() {
    printf '%s\n' "$*" >> "${CLI_LOG}"
    local entry fragment answer
    case "$*" in
      *"sentinel masters"*)
        if [ -n "${MOCK_MASTERS_BY_HOST:-}" ]; then
          while IFS= read -r entry; do
            [ -n "${entry}" ] || continue
            fragment="${entry%%=*}"
            if case "$*" in *"${fragment}"*) true ;; *) false ;; esac; then
              answer="${entry#*=}"
              printf '%b\n' "${answer}"
              return 0
            fi
          done <<< "${MOCK_MASTERS_BY_HOST}"
        fi
        printf '%b\n' "${MOCK_MASTERS_OUTPUT:-}"
        ;;
      *)
        printf 'OK\n' ;;
    esac
  }

  # cli_calls_for <fragment> — print the recorded calls that contain <fragment>.
  cli_calls_for() {
    grep -F "${1}" "${CLI_LOG}" || true
  }

  setup() {
    export KB_LEAVE_MEMBER_POD_FQDN="valkey-valkey-sentinel-2.valkey-valkey-sentinel-headless"
    export KB_LEAVE_MEMBER_POD_NAME="valkey-valkey-sentinel-2"
    export SENTINEL_POD_FQDN_LIST="valkey-valkey-sentinel-0.valkey-valkey-sentinel-headless,valkey-valkey-sentinel-1.valkey-valkey-sentinel-headless,valkey-valkey-sentinel-2.valkey-valkey-sentinel-headless"
    export SENTINEL_PASSWORD="sentinel_password"
    unset SENTINEL_SERVICE_PORT
    unset VALKEY_CLI_TLS_ARGS
    unset MOCK_MASTERS_OUTPUT MOCK_MASTERS_BY_HOST
    CLI_LOG="${PWD}/valkey-cli-mock.log"
    : > "${CLI_LOG}"
    other_sentinel_counts=()
    sentinel_member_get
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }
  BeforeAll "setup"

  cleanup() {
    unset KB_LEAVE_MEMBER_POD_FQDN
    unset KB_LEAVE_MEMBER_POD_NAME
    unset SENTINEL_POD_FQDN_LIST
    unset SENTINEL_PASSWORD
    unset MOCK_MASTERS_OUTPUT MOCK_MASTERS_BY_HOST
    rm -f $common_library_file "${CLI_LOG}";
  }
  AfterAll "cleanup"

  Describe "sentinel_member_get()"
    It "resolves the leaving member and splits the peer list"
      sentinel_leave_member_name=""
      sentinel_leave_member_fqdn=""
      sentinel_pod_list=()
      When call sentinel_member_get
      The status should be success
      The variable sentinel_leave_member_name should eq "valkey-valkey-sentinel-2"
      The variable sentinel_leave_member_fqdn should eq "valkey-valkey-sentinel-2.valkey-valkey-sentinel-headless"
      The variable sentinel_pod_list[0] should eq "valkey-valkey-sentinel-0.valkey-valkey-sentinel-headless"
      The variable sentinel_pod_list[1] should eq "valkey-valkey-sentinel-1.valkey-valkey-sentinel-headless"
      The variable sentinel_pod_list[2] should eq "valkey-valkey-sentinel-2.valkey-valkey-sentinel-headless"
    End

    It "fails closed when the leaving pod FQDN is missing"
      sentinel_member_get_exit_status() {
        local rc=0
        ( unset KB_LEAVE_MEMBER_POD_FQDN; sentinel_member_get ) >/dev/null 2>&1 || rc=$?
        printf '%s' "${rc}"
      }
      When call sentinel_member_get_exit_status
      The status should be success
      The stdout should eq "1"
    End
  End

  Describe "remove_monitor()"
    It "retries while a master reports the disconnected flag"
      export MOCK_MASTERS_OUTPUT='name\nmymaster\nflags\nmaster,disconnected'
      When call remove_monitor
      The status should be success
      The stdout should include "one or more masters are disconnected"
      The stdout should include "sentinel connect failed after 3 retries."
      The stdout should include "unable to connect to valkey sentinel"
    End

    It "removes the monitored master from the leaving sentinel when reachable"
      export MOCK_MASTERS_OUTPUT='name\nmymaster\nflags\nmaster'
      remove_monitor_and_show_calls() {
        remove_monitor
        echo "── recorded cli calls ──"
        cat "${CLI_LOG}"
      }
      When call remove_monitor_and_show_calls
      The status should be success
      The stdout should include "all masters are reachable."
      The stdout should include "sentinel no longer monitors mymaster"
      The stdout should include "SENTINEL REMOVE mymaster"
      The stdout should include "-h valkey-valkey-sentinel-2.valkey-valkey-sentinel-headless"
    End
  End

  Describe "reset_remaining_sentinels()"
    It "resets every remaining sentinel and skips the leaving one"
      reset_and_show_calls() {
        reset_remaining_sentinels
        echo "── recorded cli calls ──"
        cat "${CLI_LOG}"
      }
      When call reset_and_show_calls
      The status should be success
      The stdout should include "sentinel is resetting at valkey-valkey-sentinel-0.valkey-valkey-sentinel-headless"
      The stdout should include "sentinel is resetting at valkey-valkey-sentinel-1.valkey-valkey-sentinel-headless"
      The stdout should include "all remaining sentinels have been reset."
      The stdout should not include "sentinel is resetting at valkey-valkey-sentinel-2"
      The stdout should not include "-h valkey-valkey-sentinel-2.valkey-valkey-sentinel-headless -p 26379 -a sentinel_password SENTINEL RESET"
    End

    It "fails closed when a remaining sentinel stays unreachable"
      sentinel_reset_exit_status() {
        local rc=0
        ( valkey-cli() { return 1; }
          reset_remaining_sentinels ) >/dev/null 2>&1 || rc=$?
        printf '%s' "${rc}"
      }
      When call sentinel_reset_exit_status
      The status should be success
      The stdout should eq "1"
    End
  End

  Describe "check_all_sentinel_agreement()"
    setup() {
      : > "${CLI_LOG}"
      other_sentinel_counts=()
      export MOCK_MASTERS_OUTPUT='name\nmymaster\nflags\nmaster\nnum-other-sentinels\n1'
    }
    Before "setup"

    It "passes when all remaining sentinels report the same peer count"
      When call check_all_sentinel_agreement
      The status should be success
      The stdout should include "master name: mymaster, num-other-sentinels: 1"
      The stdout should include "all the sentinels agree about the number of sentinels currently active"
    End

    It "exits non-zero when the remaining sentinels disagree"
      # sentinel-0 answers num-other-sentinels=1, sentinel-1 answers 2 —
      # a disagreement that must fail the action.
      export MOCK_MASTERS_BY_HOST=$'valkey-valkey-sentinel-0=name\\nmymaster\\nflags\\nmaster\\nnum-other-sentinels\\n1\nvalkey-valkey-sentinel-1=name\\nmymaster\\nflags\\nmaster\\nnum-other-sentinels\\n2'
      check_agreement_exit_status() {
        local rc=0
        ( other_sentinel_counts=()
          check_all_sentinel_agreement ) >/dev/null 2>&1 || rc=$?
        printf '%s' "${rc}"
      }
      When call check_agreement_exit_status
      The status should be success
      The stdout should eq "1"
    End
  End
End
