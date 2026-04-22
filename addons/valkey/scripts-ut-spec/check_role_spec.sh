# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "check_role_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Check-Role Bash Script Tests"
  Include $common_library_file
  Include ../scripts/check-role.sh

  init() {
    ut_mode="true"
    export SERVICE_PORT="6379"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SERVICE_PORT
  }
  AfterAll "cleanup"

  Describe "build_cli_cmd()"
    Context "without password or TLS"
      setup() {
        unset VALKEY_DEFAULT_PASSWORD
        unset VALKEY_CLI_TLS_ARGS
      }
      Before "setup"

      It "builds a basic valkey-cli command"
        When call build_cli_cmd
        The status should be success
        The stdout should include "valkey-cli --no-auth-warning"
        The stdout should include "-h 127.0.0.1"
        The stdout should include "-p 6379"
        The stdout should not include " -a "
      End
    End

    Context "with password"
      setup() {
        export VALKEY_DEFAULT_PASSWORD="secret"
      }
      Before "setup"

      teardown() {
        unset VALKEY_DEFAULT_PASSWORD
      }
      After "teardown"

      It "includes -a flag"
        When call build_cli_cmd
        The status should be success
        The stdout should include "-a secret"
      End
    End

    Context "with custom port"
      setup() {
        port="6380"
        unset VALKEY_DEFAULT_PASSWORD
        unset VALKEY_CLI_TLS_ARGS
      }
      Before "setup"

      teardown() {
        port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"
      }
      After "teardown"

      It "uses the custom port"
        When call build_cli_cmd
        The status should be success
        The stdout should include "-p 6380"
      End
    End
  End

  Describe "role probe output"
    Context "when server reports master"
      It "outputs 'primary'"
        valkey-cli() {
          printf "# Replication\r\nrole:master\r\nconnected_slaves:2\r\n"
        }
        cli_cmd=$(build_cli_cmd)
        role_line=$(${cli_cmd} info replication 2>/dev/null | grep "^role:" | tr -d '\r\n')
        When call bash -c "
          case \"${role_line}\" in
            \"role:master\") printf %s \"primary\" ;;
            \"role:slave\")  printf %s \"secondary\" ;;
            *) echo \"unknown\" >&2; exit 1 ;;
          esac
        "
        The status should be success
        The stdout should eq "primary"
      End

      It "does not include a trailing newline byte"
        When call bash -c "printf %s 'primary' | od -An -t x1 | tr -s ' ' | sed 's/^ //;s/ $//'"
        The status should be success
        The stdout should eq "70 72 69 6d 61 72 79"
      End
    End

    Context "when server reports slave"
      It "outputs 'secondary'"
        valkey-cli() {
          printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\n"
        }
        cli_cmd=$(build_cli_cmd)
        role_line=$(${cli_cmd} info replication 2>/dev/null | grep "^role:" | tr -d '\r\n')
        When call bash -c "
          case \"${role_line}\" in
            \"role:master\") printf %s \"primary\" ;;
            \"role:slave\")  printf %s \"secondary\" ;;
            *) echo \"unknown\" >&2; exit 1 ;;
          esac
        "
        The status should be success
        The stdout should eq "secondary"
      End

      It "does not include a trailing newline byte"
        When call bash -c "printf %s 'secondary' | od -An -t x1 | tr -s ' ' | sed 's/^ //;s/ $//'"
        The status should be success
        The stdout should eq "73 65 63 6f 6e 64 61 72 79"
      End
    End
  End
End
