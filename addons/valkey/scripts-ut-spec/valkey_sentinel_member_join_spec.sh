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
    MJ_TMP="$(mktemp -d /tmp/mj-spec.XXXXXX)"
    export MJ_TMP
  }
  BeforeAll "init"

  cleanup() {
    rm -rf "${MJ_TMP}"
    rm -f "${common_library_file}"
    unset SERVICE_PORT SENTINEL_SERVICE_PORT VALKEY_COMPONENT_NAME
    unset VALKEY_POD_NAME_LIST VALKEY_POD_FQDN_LIST SENTINEL_POD_FQDN_LIST
    unset VALKEY_DEFAULT_USER VALKEY_DEFAULT_PASSWORD SENTINEL_PASSWORD
    unset CURRENT_POD_HOST_IP KB_JOIN_MEMBER_POD_NAME KB_JOIN_MEMBER_POD_FQDN
    unset VALKEY_ADVERTISED_PORT VALKEY_LB_ADVERTISED_PORT VALKEY_LB_ADVERTISED_HOST
    unset CUSTOM_SENTINEL_MASTER_NAME
  }
  AfterAll "cleanup"

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

  Describe "parse_valkey_primary_announce_addr()"
    _announce_values() {
      parse_valkey_primary_announce_addr "$1"
      printf 'host=%s port=%s\n' "${valkey_announce_host_value}" "${valkey_announce_port_value}"
    }

    It "uses the pod fqdn and the data port when no advertised service exists"
      When call _announce_values "mycluster-valkey-1"
      The status should be success
      The stdout should include "host= port="
      The stdout should include "VALKEY_ADVERTISED_PORT not found. Ignoring."
    End

    It "prefers the NodePort address of the primary pod so both registration paths agree"
      export VALKEY_ADVERTISED_PORT="mycluster-valkey-advertised-0:32024,mycluster-valkey-advertised-1:31318,mycluster-valkey-advertised-2:31000"
      When call _announce_values "mycluster-valkey-1"
      The status should be success
      The stdout should include "host=10.0.0.7 port=31318"
      unset VALKEY_ADVERTISED_PORT
    End

    It "prefers the LoadBalancer host over the node ip and keeps the data port"
      export VALKEY_ADVERTISED_PORT="mycluster-valkey-advertised-0:32024,mycluster-valkey-advertised-1:31318"
      export VALKEY_LB_ADVERTISED_HOST="mycluster-valkey-advertised-0:203.0.113.7,mycluster-valkey-advertised-1:203.0.113.8"
      When call _announce_values "mycluster-valkey-1"
      The status should be success
      The stdout should include "host=203.0.113.8 port=6379"
      unset VALKEY_ADVERTISED_PORT VALKEY_LB_ADVERTISED_HOST
    End

    It "fails closed when the advertised list has no entry for the primary"
      export VALKEY_ADVERTISED_PORT="mycluster-valkey-advertised-0:32024"
      When call parse_valkey_primary_announce_addr "mycluster-valkey-9"
      The status should be failure
      The stderr should include "No matching svcName and port found"
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

  Describe "register_master_to_sentinel()"
    # The script invokes valkey-cli through an unquoted command string, so a
    # valkey-cli() function mock intercepts every call.  get-master-addr runs
    # inside a command substitution (subshell): state must live in a file.
    It "issues SENTINEL MONITOR plus the shared failover tunables on a fresh sentinel"
      GET_CALLS_FILE="${MJ_TMP}/get-calls.log"; echo 0 > "${GET_CALLS_FILE}"
      CLI_LOG="${MJ_TMP}/cli.log"; : > "${CLI_LOG}"
      valkey-cli() {
        printf '%s\n' "$*" >> "${CLI_LOG}"
        case "$*" in
          *"get-master-addr-by-name"*)
            local n
            n=$(cat "${GET_CALLS_FILE}")
            echo $((n + 1)) > "${GET_CALLS_FILE}"
            # first call: not monitored yet; later calls: registered
            if [ "${n}" -eq 0 ]; then echo ""; else echo "10.0.0.9"; echo "6379"; fi ;;
          *"SENTINEL MONITOR"*) echo "OK" ;;
          *) echo "OK" ;;
        esac
      }
      When call register_master_to_sentinel "mycluster-valkey" "10.0.0.9" "6379" "2" "20000" "60000" "1"
      The status should be success
      The stdout should include "register master mycluster-valkey to local sentinel succeeded!"
      The contents of file "${CLI_LOG}" should include "SENTINEL MONITOR mycluster-valkey 10.0.0.9 6379 2"
      The contents of file "${CLI_LOG}" should include "SENTINEL SET mycluster-valkey down-after-milliseconds 20000"
      The contents of file "${CLI_LOG}" should include "SENTINEL SET mycluster-valkey failover-timeout 60000"
      The contents of file "${CLI_LOG}" should include "SENTINEL SET mycluster-valkey parallel-syncs 1"
      The contents of file "${CLI_LOG}" should include "SENTINEL SET mycluster-valkey auth-user default"
      The contents of file "${CLI_LOG}" should include "SENTINEL SET mycluster-valkey auth-pass datapass"
    End

    It "skips SENTINEL MONITOR when the master is already monitored"
      CLI_LOG="${MJ_TMP}/cli.log"; : > "${CLI_LOG}"
      valkey-cli() {
        printf '%s\n' "$*" >> "${CLI_LOG}"
        case "$*" in
          *"get-master-addr-by-name"*) echo "10.0.0.9" ;;
          *"SENTINEL MONITOR"*) echo "UNEXPECTED SENTINEL MONITOR" ;;
          *) echo "OK" ;;
        esac
      }
      When call register_master_to_sentinel "mycluster-valkey" "10.0.0.9" "6379" "2" "20000" "60000" "1"
      The status should be success
      The stdout should include "already monitored, skip SENTINEL MONITOR"
      The contents of file "${CLI_LOG}" should not include "UNEXPECTED"
    End

    It "fails closed when the Sentinel rejects SENTINEL MONITOR (valkey-cli exits 0 on ERR replies)"
      CLI_LOG="${MJ_TMP}/cli.log"; : > "${CLI_LOG}"
      valkey-cli() {
        case "$*" in
          *"get-master-addr-by-name"*) echo "" ;;
          *"SENTINEL MONITOR"*) echo "ERR Invalid IP address or hostname specified" ;;
          *) echo "OK" ;;
        esac
      }
      When call register_master_to_sentinel "mycluster-valkey" "mycluster-valkey-0.headless.default.svc.cluster.local" "6379" "2" "20000" "60000" "1"
      The status should be failure
      The stderr should include "SENTINEL MONITOR returned 'ERR Invalid IP address or hostname specified'"
    End

    It "fails when a SENTINEL SET exits non-zero"
      CLI_LOG="${MJ_TMP}/cli.log"; : > "${CLI_LOG}"
      valkey-cli() {
        case "$*" in
          *"get-master-addr-by-name"*) echo "" ;;
          *"SENTINEL MONITOR"*) echo "OK" ;;
          *"SENTINEL SET"*) echo "ERR unknown error"; return 1 ;;
          *) echo "OK" ;;
        esac
      }
      When call register_master_to_sentinel "mycluster-valkey" "10.0.0.9" "6379" "2" "20000" "60000" "1"
      The status should be failure
      The stdout should include "ERR unknown error"
    End

    Context "when the data node has no password"
      It "does not configure auth-user / auth-pass on the monitor"
        CLI_LOG="${MJ_TMP}/cli.log"; : > "${CLI_LOG}"
        unset VALKEY_DEFAULT_PASSWORD
        valkey-cli() {
          printf '%s\n' "$*" >> "${CLI_LOG}"
          case "$*" in
            *"get-master-addr-by-name"*) echo "10.0.0.9" ;;
            *) echo "OK" ;;
          esac
        }
        When call register_master_to_sentinel "mycluster-valkey" "10.0.0.9" "6379" "2" "20000" "60000" "1"
        The status should be success
        The stdout should include "register master mycluster-valkey to local sentinel succeeded!"
        The contents of file "${CLI_LOG}" should not include "auth-user"
        The contents of file "${CLI_LOG}" should not include "auth-pass"
        export VALKEY_DEFAULT_PASSWORD="datapass"
        End
    End
  End

  Describe "recover_registered_valkey_servers()"
    It "probes the primary, resolves the NodePort address and registers it"
      GET_CALLS_FILE="${MJ_TMP}/get-calls.log"; echo 0 > "${GET_CALLS_FILE}"
      CLI_LOG="${MJ_TMP}/cli.log"; : > "${CLI_LOG}"
      export VALKEY_ADVERTISED_PORT="mycluster-valkey-advertised-0:32024,mycluster-valkey-advertised-1:31318,mycluster-valkey-advertised-2:31000"
      valkey-cli() {
        printf '%s\n' "$*" >> "${CLI_LOG}"
        case "$*" in
          *"INFO replication"*)
            case "$*" in
              *"mycluster-valkey-1."*) echo "role:master" ;;
              *) echo "role:slave" ;;
            esac ;;
          *"get-master-addr-by-name"*)
            local n
            n=$(cat "${GET_CALLS_FILE}")
            echo $((n + 1)) > "${GET_CALLS_FILE}"
            if [ "${n}" -eq 0 ]; then echo ""; else echo "10.0.0.7"; echo "31318"; fi ;;
          *"SENTINEL MONITOR"*) echo "OK" ;;
          *) echo "OK" ;;
        esac
      }
      When call recover_registered_valkey_servers
      The status should be success
      The stdout should include "register master mycluster-valkey to local sentinel succeeded!"
      The contents of file "${CLI_LOG}" should include "SENTINEL MONITOR mycluster-valkey 10.0.0.7 31318 2"
      unset VALKEY_ADVERTISED_PORT
    End
  End

  Describe "ComponentDefinition contract"
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

    It "declares the shared pod fieldRef env on the memberJoin action (kbagent merges action envs; the container's own env is invisible to actions)"
      # Regression: without CURRENT_POD_HOST_IP here the monitor address
      # degraded to the pod FQDN and a Sentinel without resolve-hostnames
      # rejected the registration.
      When call bash -c "sed -n '/memberJoin:/,/memberLeave:/p' '${sentinel_cmpd}' | grep -c 'name: CURRENT_POD_HOST_IP'"
      The status should be success
      The stdout should eq "1"
    End

    It "exposes the data pod list and the NodePort / LB mappings to the sentinel pods"
      When call grep -c -E "name: VALKEY_POD_NAME_LIST|name: VALKEY_ADVERTISED_PORT|name: VALKEY_LB_ADVERTISED_PORT|name: VALKEY_LB_ADVERTISED_HOST" "${sentinel_cmpd}"
      The status should be success
      The stdout should eq "4"
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
