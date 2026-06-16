# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_sentinel_post_start_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Sentinel Post-Start Script Tests"
  Include ../scripts/redis-sentinel-post-start.sh
  Include $common_library_file

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "acl_set_user_for_redis_sentinel()"
    setup_env() {
      export SENTINEL_PASSWORD="sentpass123"
      export SENTINEL_USER="sentinel_user"
      export SENTINEL_SERVICE_PORT="26379"
      export REDIS_CLI_TLS_CMD=""
    }

    cleanup_env() {
      unset SENTINEL_PASSWORD SENTINEL_USER SENTINEL_SERVICE_PORT REDIS_CLI_TLS_CMD
    }

    Context "when sentinel password is set"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "OK"
        return 0
      }

      It "sets ACL user and saves"
        When call acl_set_user_for_redis_sentinel
        The status should be success
        The output should include "redis sentinel user and password set successfully"
      End
    End

    Context "when sentinel password is not set"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      setup_no_password() {
        unset SENTINEL_PASSWORD
      }
      BeforeEach 'setup_no_password'

      It "does nothing"
        When call acl_set_user_for_redis_sentinel
        The status should be success
        The output should eq ""
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

      It "sets ACL user successfully"
        When call acl_set_user_for_redis_sentinel
        The status should be success
        The output should include "redis sentinel user and password set successfully"
      End
    End

    Context "when using default sentinel port"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      setup_default_port() {
        unset SENTINEL_SERVICE_PORT
      }
      BeforeEach 'setup_default_port'

      redis-cli() {
        echo "OK"
        return 0
      }

      It "defaults to port 26379"
        When call acl_set_user_for_redis_sentinel
        The status should be success
        The output should include "redis sentinel user and password set successfully"
      End
    End
  End
End
