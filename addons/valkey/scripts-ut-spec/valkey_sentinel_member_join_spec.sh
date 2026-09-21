# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_sentinel_member_join_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Sentinel Member-Join Bash Script Tests"
  Include $common_library_file
  Include ../scripts/valkey-sentinel-member-join.sh

  init() {
    ut_mode="true"
    export SERVICE_PORT="6379"
    export SENTINEL_SERVICE_PORT="26379"
    export VALKEY_COMPONENT_NAME="mycluster-valkey"
    export VALKEY_POD_NAME_LIST="mycluster-valkey-0,mycluster-valkey-1,mycluster-valkey-2"
    export VALKEY_POD_FQDN_LIST="mycluster-valkey-0.headless.default.svc.cluster.local,mycluster-valkey-1.headless.default.svc.cluster.local,mycluster-valkey-2.headless.default.svc.cluster.local"
    export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local,sentinel-1.headless.default.svc.cluster.local,sentinel-2.headless.default.svc.cluster.local"
    export VALKEY_DEFAULT_USER="default"
    export VALKEY_DEFAULT_PASSWORD="datapass"
    export SENTINEL_PASSWORD="sentpass"
    export CURRENT_POD_HOST_IP="10.0.0.7"
    export KB_JOIN_MEMBER_POD_NAME="valkey-sentinel-3"
    export KB_JOIN_MEMBER_POD_FQDN="valkey-sentinel-3.headless.default.svc.cluster.local"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SERVICE_PORT SENTINEL_SERVICE_PORT VALKEY_COMPONENT_NAME
    unset VALKEY_POD_NAME_LIST VALKEY_POD_FQDN_LIST SENTINEL_POD_FQDN_LIST
    unset VALKEY_DEFAULT_USER VALKEY_DEFAULT_PASSWORD SENTINEL_PASSWORD
    unset CURRENT_POD_HOST_IP KB_JOIN_MEMBER_POD_NAME KB_JOIN_MEMBER_POD_FQDN
    unset VALKEY_ADVERTISED_PORT
  }
  AfterAll "cleanup"

  Describe "build_data_cli() / build_sentinel_cli()"
    _print_cmd() {
      local cli_name="${1}"
      shift
      "${cli_name}" "$@"
      if [ "${cli_name}" = "build_data_cli" ]; then
        printf '%s\n' "${_data_cli_cmd[*]}"
      else
        printf '%s\n' "${_sentinel_cli_cmd[*]}"
      fi
    }

    It "builds the data cli with host, data port and auth password"
      When call _print_cmd build_data_cli "mycluster-valkey-0.headless.default.svc.cluster.local"
      The status should be success
      The stdout should include "--no-auth-warning"
      The stdout should include "-h mycluster-valkey-0.headless.default.svc.cluster.local"
      The stdout should include "-p 6379"
      The stdout should include "-a datapass"
      The stdout should not include "-p 26379"
    End

    It "builds the sentinel cli against the local sentinel with the sentinel password"
      When call _print_cmd build_sentinel_cli "valkey-sentinel-3.headless.default.svc.cluster.local"
      The status should be success
      The stdout should include "-h valkey-sentinel-3.headless.default.svc.cluster.local"
      The stdout should include "-p 26379"
      The stdout should include "-a sentpass"
    End

    Context "when no passwords are set"
      setup() {
        unset VALKEY_DEFAULT_PASSWORD
        unset SENTINEL_PASSWORD
      }
      Before "setup"

      teardown() {
        export VALKEY_DEFAULT_PASSWORD="datapass"
        export SENTINEL_PASSWORD="sentpass"
      }
      After "teardown"

      It "omits the -a flag entirely"
        When call _print_cmd build_sentinel_cli "127.0.0.1"
        The status should be success
        The stdout should not include " -a "
      End
    End
  End

  Describe "local_sentinel_host()"
    It "registers into the pod that just joined"
      When call local_sentinel_host
      The status should be success
      The stdout should eq "valkey-sentinel-3.headless.default.svc.cluster.local"
    End

    Context "outside of a lifecycle action"
      setup() {
        unset KB_JOIN_MEMBER_POD_FQDN
      }
      Before "setup"

      teardown() {
        export KB_JOIN_MEMBER_POD_FQDN="valkey-sentinel-3.headless.default.svc.cluster.local"
      }
      After "teardown"

      It "falls back to loopback"
        When call local_sentinel_host
        The status should be success
        The stdout should eq "127.0.0.1"
      End
    End
  End

  Describe "resolve_primary_fqdn()"
    Context "when a pod reports role:master"
      It "returns that pod instead of assuming the first pod is the primary"
        valkey-cli() {
          case "$*" in
            *"mycluster-valkey-1."*) echo "role:master" ;;
            *) echo "role:slave" ;;
          esac
        }
        When call resolve_primary_fqdn
        The status should be success
        The stdout should eq "mycluster-valkey-1.headless.default.svc.cluster.local"
      End
    End

    Context "when no pod answers"
      It "falls back to the min-lexicographical pod"
        valkey-cli() { echo ""; }
        When call resolve_primary_fqdn
        The status should be success
        The stderr should include "WARNING: no data pod reported role:master"
        The stdout should eq "mycluster-valkey-0.headless.default.svc.cluster.local"
      End
    End

    Context "when neither the role probe nor the fallback can resolve an address"
      It "fails closed instead of registering a guessed address"
        valkey-cli() { echo ""; }
        unset VALKEY_POD_NAME_LIST
        When call resolve_primary_fqdn
        The status should be failure
        The stderr should include "cannot determine the primary"
        export VALKEY_POD_NAME_LIST="mycluster-valkey-0,mycluster-valkey-1,mycluster-valkey-2"
      End
    End
  End

  Describe "resolve_monitor_address()"
    It "uses the pod fqdn and the data port by default"
      When call resolve_monitor_address "mycluster-valkey-1.headless.default.svc.cluster.local"
      The status should be success
      The stdout should eq "mycluster-valkey-1.headless.default.svc.cluster.local 6379"
    End

    It "prefers the NodePort address of that pod so both registration paths agree"
      export VALKEY_ADVERTISED_PORT="mycluster-valkey-advertised-0:32024,mycluster-valkey-advertised-1:31318,mycluster-valkey-advertised-2:31000"
      When call resolve_monitor_address "mycluster-valkey-1.headless.default.svc.cluster.local"
      The status should be success
      The stdout should eq "10.0.0.7 31318"
      unset VALKEY_ADVERTISED_PORT
    End
  End

  Describe "calculate_sentinel_monitor_quorum()"
    It "uses the majority of the current Sentinel set"
      When call calculate_sentinel_monitor_quorum
      The status should be success
      The stdout should eq "2"
    End

    It "tightens the quorum after a scale-out to five Sentinels"
      export SENTINEL_POD_FQDN_LIST="s-0.headless.default.svc.cluster.local,s-1.headless.default.svc.cluster.local,s-2.headless.default.svc.cluster.local,s-3.headless.default.svc.cluster.local,s-4.headless.default.svc.cluster.local"
      When call calculate_sentinel_monitor_quorum
      The status should be success
      The stdout should eq "3"
      export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local,sentinel-1.headless.default.svc.cluster.local,sentinel-2.headless.default.svc.cluster.local"
    End

    It "fails when the Sentinel peer list is empty"
      unset SENTINEL_POD_FQDN_LIST
      When call calculate_sentinel_monitor_quorum
      The status should be failure
      The stderr should include "SENTINEL_POD_FQDN_LIST is empty"
      export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local,sentinel-1.headless.default.svc.cluster.local,sentinel-2.headless.default.svc.cluster.local"
    End
  End

  Describe "register_master_locally()"
    Context "when the local sentinel has no monitor yet"
      It "issues SENTINEL MONITOR plus the shared failover tunables and verifies the result"
        monitor_issued="false"
        valkey-cli() {
          case "$*" in
            *"get-master-addr-by-name"*)
              if [ "${monitor_issued}" = "true" ]; then
                echo "mycluster-valkey-1.headless.default.svc.cluster.local 6379"
              else
                echo "(nil)"
              fi ;;
            *"PING"*) echo "PONG" ;;
            *"SENTINEL MONITOR"*) monitor_issued="true"; echo "OK" ;;
            *"SENTINEL SET"*) echo "OK" ;;
            *) echo "CMD: $*" ;;
          esac
        }
        When call register_master_locally "mycluster-valkey-1.headless.default.svc.cluster.local" "6379"
        The status should be success
        The stdout should include "INFO: registering mycluster-valkey at mycluster-valkey-1.headless.default.svc.cluster.local:6379 (quorum 2)."
        The stdout should include "Registered mycluster-valkey at mycluster-valkey-1.headless.default.svc.cluster.local 6379 with the local Sentinel."
      End
    End

    Context "when the local sentinel already monitors the master"
      It "skips SENTINEL MONITOR but still applies the tunables"
        valkey-cli() {
          case "$*" in
            *"get-master-addr-by-name"*) echo "mycluster-valkey-1.headless.default.svc.cluster.local 6379" ;;
            *"PING"*) echo "PONG" ;;
            *"SENTINEL MONITOR"*) echo "UNEXPECTED SENTINEL MONITOR" ;;
            *"SENTINEL SET"*) echo "OK" ;;
            *) echo "CMD: $*" ;;
          esac
        }
        When call register_master_locally "mycluster-valkey-1.headless.default.svc.cluster.local" "6379"
        The status should be success
        The stdout should include "skip SENTINEL MONITOR"
        The stdout should not include "UNEXPECTED"
      End
    End

    Context "when the sentinel rejects a tunable"
      It "fails closed instead of reporting a half-configured monitor"
        valkey-cli() {
          case "$*" in
            *"get-master-addr-by-name"*) echo "(nil)" ;;
            *"PING"*) echo "PONG" ;;
            *"SENTINEL SET"*) echo "ERR unknown subcommand" ;;
            *) echo "OK" ;;
          esac
        }
        When call register_master_locally "mycluster-valkey-1.headless.default.svc.cluster.local" "6379"
        The status should be failure
        The stdout should include "INFO: registering mycluster-valkey"
        The stderr should include "SENTINEL SET mycluster-valkey down-after-milliseconds returned"
      End
    End

    Context "when the monitor registration does not take effect"
      It "fails closed when the sentinel still has no master afterwards"
        valkey-cli() {
          case "$*" in
            *"get-master-addr-by-name"*) echo "(nil)" ;;
            *"PING"*) echo "PONG" ;;
            *) echo "OK" ;;
          esac
        }
        When call register_master_locally "mycluster-valkey-1.headless.default.svc.cluster.local" "6379"
        The status should be failure
        The stdout should include "INFO: registering mycluster-valkey"
        The stderr should include "still has no master 'mycluster-valkey'"
      End
    End

    Context "when the local sentinel is not reachable"
      It "retries the PING and then fails closed"
        sleep() { :; }
        valkey-cli() {
          case "$*" in
            *"PING"*) echo "" ;;
            *) echo "OK" ;;
          esac
        }
        When call register_master_locally "mycluster-valkey-1.headless.default.svc.cluster.local" "6379"
        The status should be failure
        The stderr should include "is not answering PING"
      End
    End

    Context "when the data node has no password"
      It "does not configure auth-user / auth-pass on the monitor"
        cli_log=""
        unset VALKEY_DEFAULT_PASSWORD
        valkey-cli() {
          cli_log="${cli_log}$*"$'\n'
          case "$*" in
            *"get-master-addr-by-name"*) echo "mycluster-valkey-1.headless.default.svc.cluster.local 6379" ;;
            *"PING"*) echo "PONG" ;;
            *) echo "OK" ;;
          esac
        }
        _assert_no_auth_tunables() {
          register_master_locally "mycluster-valkey-1.headless.default.svc.cluster.local" "6379"
          if grep -q "auth-user\|auth-pass" <<<"${cli_log}"; then
            return 1
          fi
          return 0
        }
        When call _assert_no_auth_tunables
        The status should be success
        The stdout should include "skip SENTINEL MONITOR"
        export VALKEY_DEFAULT_PASSWORD="datapass"
      End
    End
  End

  Describe "ComponentDefinition / OpsDefinition contract"
    sentinel_cmpd="../templates/cmpd-valkey-sentinel.yaml"
    ops_definition="../templates/opsdefinition-register-to-sentinel.yaml"

    It "wires the memberJoin action to the sentinel member-join script"
      When call grep -F "/scripts/valkey-sentinel-member-join.sh" "${sentinel_cmpd}"
      The status should be success
      The stdout should include "/scripts/valkey-sentinel-member-join.sh"
    End

    It "declares a memberJoin lifecycle action on the sentinel component"
      When call grep -F "memberJoin:" "${sentinel_cmpd}"
      The status should be success
      The stdout should include "memberJoin:"
    End

    It "exposes the data pod name list and NodePort mapping to the sentinel pods"
      When call grep -c -E "name: VALKEY_POD_NAME_LIST|name: VALKEY_ADVERTISED_PORT" "${sentinel_cmpd}"
      The status should be success
      The stdout should eq "2"
    End

    It "ships a register-to-sentinel OpsDefinition for the valkey data component"
      When call grep -F "componentDefinitionName: ^valkey-\\d+$" "${ops_definition}"
      The status should be success
      The stdout should include "componentDefinitionName: ^valkey-\\d+$"
    End

    It "fails closed in every error path of the member-join script (no success-only early exit)"
      member_join_script="../scripts/valkey-sentinel-member-join.sh"
      no_silent_success_contract() {
        # every failure path must exit non-zero, so "exit 0" may only appear
        # together with the sourced-guard magic for the ut framework
        ! grep -qE '^[[:space:]]*exit[[:space:]]+0[[:space:]]*$' "${member_join_script}"
      }
      When call no_silent_success_contract
      The status should be success
    End
  End
End
