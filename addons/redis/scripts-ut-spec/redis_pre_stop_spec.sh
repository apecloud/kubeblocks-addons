# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_pre_stop_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Pre-Stop Script Tests"
  Include ../scripts/redis-pre-stop.sh
  Include $common_library_file

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "acl_save_before_stop()"
    setup_env() {
      export SERVICE_PORT="6379"
      export REDIS_DEFAULT_PASSWORD="testpass123"
      export REDIS_CLI_TLS_CMD=""
    }

    cleanup_env() {
      unset SERVICE_PORT REDIS_DEFAULT_PASSWORD REDIS_CLI_TLS_CMD
    }

    Context "when acl save succeeds with password"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "OK"
        return 0
      }

      It "returns success and masks password in log"
        When call acl_save_before_stop
        The status should be success
        The output should include "acl save command:"
        The output should include "********"
        The output should not include "testpass123"
        The output should include "executed successfully"
      End
    End

    Context "when acl save succeeds without password"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      setup_no_password() {
        unset REDIS_DEFAULT_PASSWORD
      }
      BeforeEach 'setup_no_password'

      redis-cli() {
        echo "OK"
        return 0
      }

      It "returns success without -a flag"
        When call acl_save_before_stop
        The status should be success
        The output should include "acl save command:"
        The output should not include " -a "
        The output should include "executed successfully"
      End
    End

    Context "when acl save fails"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "ERR operation not permitted" >&2
        return 1
      }

      It "exits with failure"
        When run acl_save_before_stop
        The status should be failure
        The output should include "failed to execute acl save command"
      End
    End

    Context "when using custom port"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      setup_custom_port() {
        export SERVICE_PORT="6380"
      }
      BeforeEach 'setup_custom_port'

      redis-cli() {
        echo "OK"
        return 0
      }

      It "uses the custom port"
        When call acl_save_before_stop
        The status should be success
        The output should include "-p 6380"
      End
    End

    Context "when SERVICE_PORT is not set"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      setup_default_port() {
        unset SERVICE_PORT
      }
      BeforeEach 'setup_default_port'

      redis-cli() {
        echo "OK"
        return 0
      }

      It "defaults to port 6379"
        When call acl_save_before_stop
        The status should be success
        The output should include "-p 6379"
      End
    End

    Context "when TLS is enabled"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      setup_tls() {
        export REDIS_CLI_TLS_CMD="--tls --insecure"
      }
      BeforeEach 'setup_tls'

      redis-cli() {
        echo "OK"
        return 0
      }

      It "includes TLS flags in command"
        When call acl_save_before_stop
        The status should be success
        The output should include "--tls --insecure"
        The output should include "executed successfully"
      End
    End
  End
End
