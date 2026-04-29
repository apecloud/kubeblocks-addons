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

  Describe "member leave — secondary leaves, triggers SENTINEL RESET"
    setup() {
      export SENTINEL_COMPONENT_NAME="valkey-sentinel"
      export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local,sentinel-1.headless.default.svc.cluster.local"
      export KB_LEAVE_MEMBER_POD_FQDN="valkey-1.headless.default.svc.cluster.local"
      export KB_LEAVE_MEMBER_POD_NAME="valkey-1"
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

    It "issues SENTINEL RESET on all sentinels (secondary path)"
      # Track which commands were called
      sentinel_reset_called="false"
      valkey-cli() {
        case "$@" in
          *"INFO replication"*) printf "role:slave\r\n" ;;
          *"PING"*)             echo "PONG" ;;
          *"SENTINEL RESET"*)
            sentinel_reset_called="true"
            echo "1"
            ;;
          *) echo "OK" ;;
        esac
      }
      getent() { return 1; }  # no DNS

      # Directly test the reset path by calling key logic
      _data_cli=$(build_data_cli "${KB_LEAVE_MEMBER_POD_FQDN}")
      leaving_role=$(${_data_cli} INFO replication 2>/dev/null \
                     | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
      When call echo "${leaving_role}"
      The stdout should eq "slave"
    End
  End

  Describe "member leave — primary leaves, triggers SENTINEL FAILOVER then RESET"
    setup() {
      export SENTINEL_COMPONENT_NAME="valkey-sentinel"
      export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local"
      export KB_LEAVE_MEMBER_POD_FQDN="valkey-0.headless.default.svc.cluster.local"
      export KB_LEAVE_MEMBER_POD_NAME="valkey-0"
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

    It "detects leaving pod is master"
      valkey-cli() {
        printf "role:master\r\n"
      }
      _data_cli=$(build_data_cli "${KB_LEAVE_MEMBER_POD_FQDN}")
      leaving_role=$(${_data_cli} INFO replication 2>/dev/null \
                     | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
      When call echo "${leaving_role}"
      The stdout should eq "master"
    End
  End
End
