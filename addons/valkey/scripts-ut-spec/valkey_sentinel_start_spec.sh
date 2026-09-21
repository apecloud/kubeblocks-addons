# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_sentinel_start_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Sentinel Start Bash Script Tests"
  Include $common_library_file
  Include ../scripts/valkey-sentinel-start.sh

  init() {
    ut_mode="true"
    export SENTINEL_SERVICE_PORT="26379"
    export SERVICE_PORT="6379"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SENTINEL_SERVICE_PORT
    unset SERVICE_PORT
  }
  AfterAll "cleanup"

  Describe "_register_monitor()"
    setup() {
      export VALKEY_COMPONENT_NAME="mycluster-valkey"
      export SENTINEL_POD_FQDN_LIST="s-0.h.ns.svc,s-1.h.ns.svc,s-2.h.ns.svc"
      _sentinel_calls_file=$(mktemp)
      # Record every sentinel command issued; always succeed.
      _sentinel_cli() { echo "$*" >> "${_sentinel_calls_file}"; echo "OK"; }
    }
    Before "setup"

    teardown() {
      rm -f "${_sentinel_calls_file}"
      unset VALKEY_COMPONENT_NAME SENTINEL_POD_FQDN_LIST VALKEY_DEFAULT_PASSWORD
    }
    After "teardown"

    Context "with data password set"
      It "registers the monitor and applies the same failover tunables as register-to-sentinel.sh"
        export VALKEY_DEFAULT_PASSWORD="datapass"
        When call _register_monitor "valkey-0.h.ns.svc"
        The status should be success
        The stdout should include "OK"
        The stderr should include "registering master"
        The contents of file "${_sentinel_calls_file}" should include "SENTINEL MONITOR mycluster-valkey valkey-0.h.ns.svc 6379 2"
        The contents of file "${_sentinel_calls_file}" should include "SENTINEL SET mycluster-valkey down-after-milliseconds 20000"
        The contents of file "${_sentinel_calls_file}" should include "SENTINEL SET mycluster-valkey failover-timeout 60000"
        The contents of file "${_sentinel_calls_file}" should include "SENTINEL SET mycluster-valkey parallel-syncs 1"
        The contents of file "${_sentinel_calls_file}" should include "SENTINEL SET mycluster-valkey auth-user default"
        The contents of file "${_sentinel_calls_file}" should include "SENTINEL SET mycluster-valkey auth-pass datapass"
      End
    End

    Context "without data password"
      It "registers the monitor and tunables but skips auth-user/auth-pass"
        unset VALKEY_DEFAULT_PASSWORD
        When call _register_monitor "valkey-0.h.ns.svc"
        The status should be success
        The stdout should include "OK"
        The stderr should include "registering master"
        The contents of file "${_sentinel_calls_file}" should include "SENTINEL MONITOR mycluster-valkey valkey-0.h.ns.svc 6379 2"
        The contents of file "${_sentinel_calls_file}" should include "SENTINEL SET mycluster-valkey down-after-milliseconds 20000"
        The contents of file "${_sentinel_calls_file}" should not include "auth-pass"
        The contents of file "${_sentinel_calls_file}" should not include "auth-user"
      End
    End

    Context "when VALKEY_COMPONENT_NAME is missing"
      It "fails closed without issuing sentinel commands"
        unset VALKEY_COMPONENT_NAME
        When call _register_monitor "valkey-0.h.ns.svc"
        The status should be failure
        The stderr should include "VALKEY_COMPONENT_NAME is not set"
        The contents of file "${_sentinel_calls_file}" should eq ""
      End
    End
  End

  Describe "calculate_sentinel_monitor_quorum()"
    It "computes strict majority and ignores empty entries"
      export SENTINEL_POD_FQDN_LIST="s-0.h.ns.svc,,s-1.h.ns.svc,s-2.h.ns.svc,"
      When call calculate_sentinel_monitor_quorum
      The status should be success
      The stdout should eq "2"
    End

    It "fails when the list is empty"
      export SENTINEL_POD_FQDN_LIST=""
      When call calculate_sentinel_monitor_quorum
      The status should be failure
      The stderr should include "cannot compute Sentinel monitor quorum"
    End
  End
End
