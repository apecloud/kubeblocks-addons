# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_switchover_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Switchover Bash Script Tests (redis-aligned)"
  Include $common_library_file
  Include ../scripts/switchover.sh

  switchover_script="../scripts/switchover.sh"
  CLI_LOG="${PWD}/valkey-cli-switchover-mock.log"

  # ── valkey-cli mock ─────────────────────────────────────────────────────
  # Calls are appended to $CLI_LOG: the script invokes valkey-cli inside
  # command substitutions, so only a file survives the subshell.
  #   MOCK_ROLE               default role answered by `info replication`
  #   MOCK_ROLE_OVERRIDES     "host=role,host=role" per-host role
  #   MOCK_PRIORITIES         default replica-priority
  #   MOCK_PRIORITY_OVERRIDES "host=prio,host=prio"
  #   MOCK_CONFIG_SET_FAIL / MOCK_FAILOVER_FAIL  make those answers fail
  host_of_args() {
    printf '%s' "${1}" | sed -E 's/.*-h ([^ ]+).*/\1/'
  }

  override_for_host() {
    local csv="${1}" host="${2}" entry
    [ -n "${csv}" ] || return 1
    local IFS=','
    for entry in ${csv}; do
      if [ "${entry%%=*}" = "${host}" ]; then
        printf '%s' "${entry#*=}"
        return 0
      fi
    done
    return 1
  }

  valkey-cli() {
    printf '%s\n' "$*" >> "${CLI_LOG}"
    local args="$*" host role prio
    host="$(host_of_args "${args}")"
    case "${args}" in
      *"info replication"*)
        role="$(override_for_host "${MOCK_ROLE_OVERRIDES:-}" "${host}")" || role="${MOCK_ROLE:-}"
        [ -n "${role}" ] && printf 'role:%s\n' "${role}"
        ;;
      *"CONFIG GET replica-priority"*)
        prio="$(override_for_host "${MOCK_PRIORITY_OVERRIDES:-}" "${host}")" || prio="${MOCK_PRIORITIES:-100}"
        printf 'replica-priority\n%s\n' "${prio}"
        ;;
      *"CONFIG SET replica-priority "*)
        if [ "${MOCK_CONFIG_SET_FAIL:-}" = "1" ]; then
          printf '(error) ERR CONFIG SET failed\n'
        else
          printf 'OK\n'
        fi
        ;;
      *"SENTINEL FAILOVER"*)
        if [ "${MOCK_FAILOVER_FAIL:-}" = "1" ]; then
          printf '(error) ERR No such master with that name\n'
        else
          printf 'OK\n'
        fi
        ;;
      *)
        printf 'OK\n'
        ;;
    esac
  }

  env_setup() {
    export SERVICE_PORT="6379"
    export COMPONENT_REPLICAS="3"
    export KB_SWITCHOVER_ROLE="primary"
    export VALKEY_POD_FQDN_LIST="valkey-0.h,valkey-1.h,valkey-2.h"
    export VALKEY_COMPONENT_NAME="mycluster-valkey"
    export SENTINEL_COMPONENT_NAME="mycluster-valkey-sentinel"
    export SENTINEL_POD_FQDN_LIST="sentinel-0.h,sentinel-1.h"
    export SENTINEL_SERVICE_PORT="26379"
    export KB_SWITCHOVER_CURRENT_FQDN="valkey-0.h"
    export KB_SWITCHOVER_CANDIDATE_FQDN="valkey-2.h"
    unset VALKEY_DEFAULT_PASSWORD
    unset VALKEY_CLI_TLS_ARGS
    unset SENTINEL_PASSWORD
  }
  Before "env_setup"

  reset_state() {
    : > "${CLI_LOG}"
    unset MOCK_ROLE MOCK_ROLE_OVERRIDES MOCK_PRIORITIES MOCK_PRIORITY_OVERRIDES
    unset MOCK_CONFIG_SET_FAIL MOCK_FAILOVER_FAIL
    _orig_prio_fqdns=()
    _orig_prio_values=()
  }
  Before "reset_state"

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}" "${CLI_LOG}"
  }
  AfterAll "cleanup"

  # run_and_show_calls <cmd> [args...] — run it in this shell, then print the
  # recorded valkey-cli calls.  The command's exit status is propagated: a
  # trailing `cat` must not turn a failure into success.
  run_and_show_calls() {
    local rc=0
    "$@" || rc=$?
    echo "── recorded cli calls ──"
    cat "${CLI_LOG}"
    return "${rc}"
  }

  # ══ valkey_role() ═══════════════════════════════════════════════════════
  Describe "valkey_role()"
    It "returns 'master' for a primary"
      export MOCK_ROLE="master"
      When call valkey_role "valkey-0.h"
      The status should be success
      The stdout should eq "master"
    End

    It "returns 'slave' for a replica"
      export MOCK_ROLE="slave"
      When call valkey_role "valkey-1.h"
      The status should be success
      The stdout should eq "slave"
    End

    It "returns nothing when the pod does not answer"
      export MOCK_ROLE=""
      When call valkey_role "valkey-1.h"
      The stdout should eq ""
    End
  End

  # ══ build_cli() / sentinel_cli_for() ════════════════════════════════════
  Describe "build_cli()"
    It "uses the data port and no auth when no password is set"
      build_cli_string() { build_cli "valkey-0.h"; printf '%s' "${_cli[*]}"; }
      When call build_cli_string
      The status should be success
      The stdout should include "-h valkey-0.h -p 6379"
      The stdout should not include "-a "
    End

    It "appends the password and the TLS args built by the component vars"
      export VALKEY_DEFAULT_PASSWORD="datapass"
      export VALKEY_CLI_TLS_ARGS="--tls --cacert /etc/pki/tls/ca.crt"
      build_cli_string() { build_cli "valkey-0.h"; printf '%s' "${_cli[*]}"; }
      When call build_cli_string
      The status should be success
      The stdout should include "-a datapass"
      The stdout should include "--tls --cacert /etc/pki/tls/ca.crt"
    End
  End

  Describe "sentinel_cli_for()"
    It "targets the Sentinel port with the Sentinel password"
      export SENTINEL_PASSWORD="sentinelpass"
      sentinel_cli_string() { sentinel_cli_for "sentinel-0.h"; printf '%s' "${_sentinel_cli[*]}"; }
      When call sentinel_cli_string
      The status should be success
      The stdout should include "-h sentinel-0.h -p 26379"
      The stdout should include "-a sentinelpass"
    End

    It "honours a custom Sentinel port"
      export SENTINEL_SERVICE_PORT="26380"
      sentinel_cli_string() { sentinel_cli_for "sentinel-0.h"; printf '%s' "${_sentinel_cli[*]}"; }
      When call sentinel_cli_string
      The status should be success
      The stdout should include "-p 26380"
    End
  End

  # ══ valkey_kernel_status() ══════════════════════════════════════════════
  Describe "valkey_kernel_status()"
    It "returns the single primary"
      export MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-1.h=slave,valkey-2.h=slave"
      When call valkey_kernel_status
      The status should be success
      The stdout should eq "valkey-0.h"
    End

    It "fails on a split brain (two primaries)"
      export MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-1.h=master,valkey-2.h=slave"
      When call valkey_kernel_status
      The status should be failure
      The stderr should include "multiple primaries detected"
    End

    It "fails when no pod reports master"
      export MOCK_ROLE="slave"
      When call valkey_kernel_status
      The status should be failure
      The stderr should include "no primary found"
    End

    It "skips unreachable pods"
      export MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-1.h=,valkey-2.h=slave"
      When call valkey_kernel_status
      The status should be success
      The stdout should eq "valkey-0.h"
    End
  End

  # ══ pod_fqdns_with_candidate() ══════════════════════════════════════════
  Describe "pod_fqdns_with_candidate()"
    It "appends a candidate missing from a stale pod list"
      export VALKEY_POD_FQDN_LIST="valkey-0.h,valkey-1.h"
      When call pod_fqdns_with_candidate "valkey-2.h"
      The status should be success
      The stdout should eq "valkey-0.h,valkey-1.h,valkey-2.h"
    End

    It "does not duplicate a candidate already in the list"
      When call pod_fqdns_with_candidate "valkey-2.h"
      The status should be success
      The stdout should eq "valkey-0.h,valkey-1.h,valkey-2.h"
    End
  End

  # ══ priority bias ═══════════════════════════════════════════════════════
  Describe "bias_replica_priorities()"
    It "sets the candidate to 1 and the other replicas to 100"
      When call run_and_show_calls bias_replica_priorities "valkey-2.h" "valkey-1.h,valkey-2.h"
      The status should be success
      The stdout should include "-h valkey-2.h -p 6379 CONFIG SET replica-priority 1"
      The stdout should include "-h valkey-1.h -p 6379 CONFIG SET replica-priority 100"
    End

    It "leaves a never-promote replica (priority 0) untouched"
      export MOCK_PRIORITY_OVERRIDES="valkey-1.h=0"
      capture_then_bias() {
        capture_replica_priorities "valkey-1.h,valkey-2.h"
        bias_replica_priorities "valkey-2.h" "valkey-1.h,valkey-2.h"
      }
      When call run_and_show_calls capture_then_bias
      The status should be success
      The stdout should include "Preserving never-promote replica-priority=0 on valkey-1.h"
      The stdout should not include "CONFIG SET replica-priority 100"
    End

    It "fails when a CONFIG SET does not answer OK"
      export MOCK_CONFIG_SET_FAIL="1"
      run_bias() {
        ( sleep() { :; }
          bias_replica_priorities "valkey-2.h" "valkey-1.h,valkey-2.h" )
      }
      When call run_bias
      The status should be failure
      The stderr should include "failed to apply the replica-priority bias"
    End
  End

  Describe "capture/replace/restore replica priorities"
    It "restores the captured values instead of a hardcoded 100"
      export MOCK_PRIORITY_OVERRIDES="valkey-1.h=50,valkey-2.h=20"
      capture_replica_priorities "valkey-1.h,valkey-2.h"
      restore_and_show_calls() {
        restore_replica_priorities
        cat "${CLI_LOG}"
      }
      When call restore_and_show_calls
      The status should be success
      The stdout should include "Restoring replica-priorities"
      The stdout should include "CONFIG SET replica-priority 50"
      The stdout should include "CONFIG SET replica-priority 20"
    End

    It "records the engine default when a pod cannot be reached"
      MOCK_PRIORITY_OVERRIDES="" MOCK_PRIORITIES="" \
        capture_replica_priorities "valkey-1.h"
      When call captured_replica_priority "valkey-1.h"
      The status should be success
      The stdout should eq "100"
    End
  End

  # ══ sentinel failover ═══════════════════════════════════════════════════
  Describe "execute_sentinel_failover()"
    It "issues SENTINEL FAILOVER against the master name"
      When call run_and_show_calls execute_sentinel_failover "mycluster-valkey"
      The status should be success
      The stdout should include "Sentinel FAILOVER accepted by sentinel-0.h"
      The stdout should include "SENTINEL FAILOVER mycluster-valkey"
      The stdout should include "-p 26379"
    End

    It "defaults the master name to VALKEY_COMPONENT_NAME"
      When call run_and_show_calls execute_sentinel_failover
      The status should be success
      The stdout should include "SENTINEL FAILOVER mycluster-valkey"
    End

    It "fails when every Sentinel rejects the failover"
      export MOCK_FAILOVER_FAIL="1"
      When call run_and_show_calls execute_sentinel_failover "mycluster-valkey"
      The status should be failure
      The stderr should include "all Sentinel FAILOVER attempts failed"
      The stdout should include "-h sentinel-1.h"
    End
  End

  # ══ data-plane verification ═════════════════════════════════════════════
  Describe "check_switchover_result()"
    It "succeeds once the requested candidate reports master"
      check_and_show() {
        ( export MOCK_ROLE_OVERRIDES="valkey-0.h=slave,valkey-1.h=slave,valkey-2.h=master"
          check_switchover_result "valkey-2.h" "valkey-0.h" )
      }
      When call check_and_show
      The status should be success
      The stdout should include "Switchover successful: valkey-2.h is now the primary."
    End

    It "ignores the old primary still reporting master while stepping down"
      check_and_show() {
        ( export MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-1.h=slave,valkey-2.h=master"
          check_switchover_result "valkey-2.h" "valkey-0.h" )
      }
      When call check_and_show
      The status should be success
      The stdout should include "valkey-2.h is now the primary."
    End

    It "succeeds for any new primary when no candidate was requested"
      check_and_show() {
        ( export MOCK_ROLE_OVERRIDES="valkey-0.h=slave,valkey-1.h=master,valkey-2.h=slave"
          check_switchover_result "" "valkey-0.h" )
      }
      When call check_and_show
      The status should be success
      The stdout should include "Switchover successful: new primary is valkey-1.h."
    End

    It "keeps waiting and fails when a different replica was promoted"
      check_and_show() {
        ( export MOCK_ROLE_OVERRIDES="valkey-0.h=slave,valkey-1.h=master,valkey-2.h=slave"
          check_switchover_result "valkey-2.h" "valkey-0.h" )
      }
      When call check_and_show
      The status should be failure
      The stdout should include "Waiting for valkey-2.h to be promoted"
      The stderr should include "valkey-2.h is not the primary"
    End
  End

  # ══ switchover flows ════════════════════════════════════════════════════
  Describe "switchover_with_candidate()"
    It "is an idempotent success when the candidate is already master"
      run_flow() {
        ( export MOCK_ROLE_OVERRIDES="valkey-0.h=slave,valkey-1.h=slave,valkey-2.h=master"
          switchover_with_candidate "valkey-2.h" )
        echo "── recorded cli calls ──"
        cat "${CLI_LOG}"
      }
      When call run_flow
      The status should be success
      The stdout should include "already the primary"
      The stdout should not include "SENTINEL FAILOVER"
    End

    It "fails closed when the candidate role cannot be determined"
      run_flow() {
        ( export MOCK_ROLE=""
          sleep() { :; }
          switchover_with_candidate "valkey-2.h" )
      }
      When call run_flow
      The status should be failure
      The stderr should include "could not determine the role of valkey-2.h"
    End

    It "aborts when the candidate reports an unexpected role"
      run_flow() {
        ( export MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-2.h=connecting"
          switchover_with_candidate "valkey-2.h" )
      }
      When call run_flow
      The status should be failure
      The stderr should include "expected 'slave'"
    End

    It "biases, fails over, verifies and restores on the happy path"
      run_flow() {
        ( export MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-1.h=slave,valkey-2.h=slave"
          bias_replica_priorities() { echo "bias applied"; return 0; }
          execute_sentinel_failover() { echo "Sentinel FAILOVER accepted by sentinel-0.h"; return 0; }
          check_switchover_result() { echo "Switchover successful: $1 is now the primary."; return 0; }
          restore_replica_priorities() { echo "Restoring replica-priorities..."; }
          switchover_with_candidate "valkey-2.h" )
      }
      When call run_flow
      The status should be success
      The stdout should include "Biasing Sentinel toward candidate valkey-2.h"
      The stdout should include "Sentinel FAILOVER accepted"
      The stdout should include "Switchover successful"
      The stdout should include "Restoring replica-priorities"
    End

    It "restores the priorities and fails when the bias cannot be applied"
      run_flow() {
        local rc=0
        ( export MOCK_CONFIG_SET_FAIL="1" MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-2.h=slave"
          sleep() { :; }
          switchover_with_candidate "valkey-2.h" ) || rc=$?
        echo "── recorded cli calls ──"
        cat "${CLI_LOG}"
        return "${rc}"
      }
      When call run_flow
      The status should be failure
      The stdout should include "Restoring replica-priorities"
      The stdout should not include "SENTINEL FAILOVER"
      The stderr should include "failed to apply the replica-priority bias"
    End

    It "restores the priorities when Sentinel rejects the failover"
      run_flow() {
        ( export MOCK_FAILOVER_FAIL="1" MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-2.h=slave"
          switchover_with_candidate "valkey-2.h" )
      }
      When call run_flow
      The status should be failure
      The stdout should include "Restoring replica-priorities"
      The stderr should include "all Sentinel FAILOVER attempts failed"
    End

    It "restores the priorities when the new primary is not confirmed"
      run_flow() {
        ( export MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-2.h=slave"
          check_switchover_result() { return 1; }
          switchover_with_candidate "valkey-2.h" )
      }
      When call run_flow
      The status should be failure
      The stdout should include "Restoring replica-priorities"
    End
  End

  Describe "switchover_without_candidate()"
    It "fails over and waits for any new primary"
      run_flow() {
        ( export MOCK_ROLE_OVERRIDES="valkey-0.h=master,valkey-1.h=slave,valkey-2.h=slave"
          check_switchover_result() { echo "Switchover successful: new primary is valkey-1.h"; return 0; }
          switchover_without_candidate )
      }
      When call run_flow
      The status should be success
      The stdout should include "Sentinel FAILOVER accepted"
      The stdout should include "Switchover successful"
    End

    It "fails when the kernel status is unhealthy"
      run_flow() {
        ( export MOCK_ROLE="slave"
          switchover_without_candidate )
      }
      When call run_flow
      The status should be failure
      The stderr should include "no primary found"
    End
  End

  # ══ environment pre-checks ══════════════════════════════════════════════
  Describe "check_environment_exist()"
    It "is a no-op for a single-replica component"
      run_check() {
        ( export COMPONENT_REPLICAS="1"
          check_environment_exist )
      }
      When call run_check
      The status should be success
      The stdout should include "nothing to switch over"
    End

    It "is a no-op when the role is not primary"
      run_check() {
        ( export KB_SWITCHOVER_ROLE="secondary"
          check_environment_exist )
      }
      When call run_check
      The status should be success
      The stdout should include "switchover not for primary role"
    End
  End

  # ══ contract ═══════════════════════════════════════════════════════════
  # The Sentinel replica cache is NOT an authority in advertised-address
  # topologies: a Sentinel names its replicas "<node-ip>:<nodeport>", not by pod
  # FQDN, so a cache-based confirmation can never succeed there — that is what
  # made targeted switchover fail with "did not confirm full targeted priority
  # bias".  Guard against reintroducing such a check.
  Describe "contract"
    It "never parses the Sentinel replica cache"
      When call grep -F "SENTINEL REPLICAS" "${switchover_script}"
      The status should be failure
    End

    It "verifies the result on the data plane"
      When call grep -F "info replication" "${switchover_script}"
      The status should be success
      The stdout should include "info replication"
    End

    It "delegates the promotion to Sentinel"
      When call grep -F "SENTINEL FAILOVER" "${switchover_script}"
      The status should be success
      The stdout should include "SENTINEL FAILOVER"
    End

    It "keeps the never-promote guard for non-candidate replicas"
      When call grep -F "Preserving never-promote replica-priority=0 on" "${switchover_script}"
      The status should be success
      The stdout should include "never-promote"
    End

    It "fails closed without Sentinel"
      When call grep -F "switchover is unsupported without Sentinel" "${switchover_script}"
      The status should be success
      The stdout should include "unsupported without Sentinel"
    End
  End
End
