# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_ping_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Ping Script Tests"
  Include ../scripts/redis-ping.sh
  Include $common_library_file

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "check_redis_ok()"
    setup_env() {
      export SERVICE_PORT="6379"
      export REDIS_DEFAULT_PASSWORD="testpass"
      export REDIS_CLI_TLS_CMD=""
    }

    cleanup_env() {
      unset SERVICE_PORT REDIS_DEFAULT_PASSWORD REDIS_CLI_TLS_CMD
    }

    Context "when redis returns PONG with password"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "PONG"
        return 0
      }

      It "returns success"
        When call check_redis_ok
        The status should be success
        The output should include "Redis is ok"
      End
    End

    Context "when redis returns PONG without password"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      setup_no_password() {
        unset REDIS_DEFAULT_PASSWORD
      }
      BeforeEach 'setup_no_password'

      redis-cli() {
        echo "PONG"
        return 0
      }

      It "returns success"
        When call check_redis_ok
        The status should be success
        The output should include "Redis is ok"
      End
    End

    Context "when redis returns non-PONG response"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "NOAUTH Authentication required."
        return 0
      }

      It "returns failure with error"
        When call check_redis_ok
        The status should be failure
        The stderr should include "redis ping failed"
        The stderr should include "NOAUTH"
      End
    End

    Context "when redis-cli times out (exit 124)"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        return 124
      }

      It "returns failure with timeout message"
        When call check_redis_ok
        The status should be failure
        The stderr should include "Timed out"
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
        echo "PONG"
        return 0
      }

      It "returns success"
        When call check_redis_ok
        The status should be success
        The output should include "Redis is ok"
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
        echo "PONG"
        return 0
      }

      It "returns success"
        When call check_redis_ok
        The status should be success
        The output should include "Redis is ok"
      End
    End
  End

  Describe "retry_check_redis_ok()"
    setup_env() {
      export SERVICE_PORT="6379"
      export REDIS_DEFAULT_PASSWORD="testpass"
      export REDIS_CLI_TLS_CMD=""
    }

    cleanup_env() {
      unset SERVICE_PORT REDIS_DEFAULT_PASSWORD REDIS_CLI_TLS_CMD
    }

    Context "when redis is healthy"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "PONG"
        return 0
      }

      It "returns success"
        When call retry_check_redis_ok
        The status should be success
        The output should include "Redis is ok"
      End
    End

    Context "when redis is permanently down"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "Could not connect" >&2
        return 1
      }

      It "returns failure after retries"
        When call retry_check_redis_ok
        The status should be failure
        The stderr should include "Redis is not running"
      End
    End
  End
End
