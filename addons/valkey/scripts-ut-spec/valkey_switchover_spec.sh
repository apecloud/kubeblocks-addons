# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_switchover_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Switchover Bash Script Tests"
  Include $common_library_file
  Include ../scripts/switchover.sh

  init() {
    ut_mode="true"
    export SERVICE_PORT="6379"
    export COMPONENT_REPLICAS="3"
    export KB_SWITCHOVER_ROLE="primary"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SERVICE_PORT
    unset COMPONENT_REPLICAS
    unset KB_SWITCHOVER_ROLE
  }
  AfterAll "cleanup"

  Describe "get_role()"
    Context "when valkey-cli returns master"
      setup() {
        export VALKEY_DEFAULT_PASSWORD=""
      }
      Before "setup"

      It "returns 'master'"
        valkey-cli() {
          printf "# Replication\r\nrole:master\r\nconnected_slaves:1\r\n"
        }
        When call get_role "valkey-0.headless.default.svc.cluster.local"
        The status should be success
        The stdout should eq "master"
      End
    End

    Context "when valkey-cli returns slave"
      It "returns 'slave'"
        valkey-cli() {
          printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\n"
        }
        When call get_role "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should eq "slave"
      End
    End

    Context "when connection fails"
      It "returns empty string (exits 0 due to pipeline)"
        valkey-cli() {
          return 1
        }
        When call get_role "unreachable-host"
        The status should be success
        The stdout should eq ""
      End
    End
  End

  Describe "promote_replica()"
    Context "when REPLICAOF NO ONE succeeds"
      It "returns success"
        valkey-cli() {
          echo "OK"
        }
        When call promote_replica "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "Promoting"
      End
    End

    Context "when REPLICAOF NO ONE returns unexpected response"
      It "returns failure"
        valkey-cli() {
          echo "ERR This instance has cluster support disabled"
        }
        When call promote_replica "valkey-1.headless.default.svc.cluster.local"
        The status should be failure
        The stdout should include "Promoting"
        The stderr should include "returned unexpected response"
      End
    End
  End

  Describe "pick_any_secondary()"
    Context "when a secondary exists"
      setup() {
        export KB_SWITCHOVER_CURRENT_FQDN="valkey-0.headless.default.svc.cluster.local"
        export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local,valkey-2.headless.default.svc.cluster.local"
      }
      Before "setup"

      teardown() {
        unset KB_SWITCHOVER_CURRENT_FQDN
        unset VALKEY_POD_FQDN_LIST
      }
      After "teardown"

      It "returns the first slave found"
        get_role() {
          case "$1" in
            *"valkey-0"*) echo "master" ;;
            *"valkey-1"*) echo "slave" ;;
            *"valkey-2"*) echo "slave" ;;
          esac
        }
        When call pick_any_secondary
        The status should be success
        The stdout should include "valkey-1"
      End
    End

    Context "when no secondary is available"
      setup() {
        export KB_SWITCHOVER_CURRENT_FQDN="valkey-0.headless.default.svc.cluster.local"
        export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local"
      }
      Before "setup"

      teardown() {
        unset KB_SWITCHOVER_CURRENT_FQDN
        unset VALKEY_POD_FQDN_LIST
      }
      After "teardown"

      It "returns empty string"
        get_role() {
          echo "master"
        }
        When call pick_any_secondary
        The status should be success
        The stdout should eq ""
      End
    End
  End

  Describe "execute_sentinel_failover()"
    Context "when first Sentinel accepts the failover"
      setup() {
        export VALKEY_COMPONENT_NAME="mycluster-valkey"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local,sentinel-1.headless.default.svc.cluster.local"
        export SENTINEL_SERVICE_PORT="26379"
      }
      Before "setup"

      teardown() {
        unset VALKEY_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_SERVICE_PORT
      }
      After "teardown"

      It "returns success"
        valkey-cli() {
          echo "OK"
        }
        When call execute_sentinel_failover
        The status should be success
        The stdout should include "FAILOVER accepted"
      End
    End

    Context "when all Sentinels reject the failover"
      setup() {
        export VALKEY_COMPONENT_NAME="mycluster-valkey"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local"
        export SENTINEL_SERVICE_PORT="26379"
      }
      Before "setup"

      teardown() {
        unset VALKEY_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_SERVICE_PORT
      }
      After "teardown"

      It "returns failure"
        valkey-cli() {
          echo "(error) ERR No such master with that name"
        }
        When call execute_sentinel_failover
        The status should be failure
        The stderr should include "all Sentinel FAILOVER attempts failed"
      End
    End
  End

  Describe "set_replica_priority()"
    It "logs a warning when CONFIG SET returns unexpected output"
      valkey-cli() {
        echo "(error) ERR"
      }
      When call set_replica_priority "valkey-1.headless.default.svc.cluster.local" "1"
      The status should be success
      The stderr should include "WARNING"
    End

    It "succeeds silently when CONFIG SET returns OK"
      valkey-cli() {
        echo "OK"
      }
      When call set_replica_priority "valkey-1.headless.default.svc.cluster.local" "100"
      The status should be success
      The stderr should eq ""
    End
  End
End
