# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_sentinel_ping_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Sentinel Ping Script Tests"
  Include ../scripts/redis-sentinel-ping.sh
  Include $common_library_file

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "check_redis_sentinel_ok()"
    setup_env() {
      export SENTINEL_SERVICE_PORT="26379"
      export SENTINEL_PASSWORD="sentinelpass"
      export REDIS_CLI_TLS_CMD=""
    }

    cleanup_env() {
      unset SENTINEL_SERVICE_PORT SENTINEL_PASSWORD REDIS_CLI_TLS_CMD
    }

    Context "when sentinel returns PONG with password"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "PONG"
        return 0
      }

      It "returns success"
        When call check_redis_sentinel_ok
        The status should be success
      End
    End

    Context "when sentinel returns PONG without password"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      setup_no_password() {
        unset SENTINEL_PASSWORD
      }
      BeforeEach 'setup_no_password'

      redis-cli() {
        echo "PONG"
        return 0
      }

      It "returns success"
        When call check_redis_sentinel_ok
        The status should be success
      End
    End

    Context "when sentinel returns non-PONG response"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "NOAUTH Authentication required."
        return 0
      }

      It "returns failure with error"
        When call check_redis_sentinel_ok
        The status should be failure
        The stderr should include "redis sentinel ping failed"
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
        When call check_redis_sentinel_ok
        The status should be failure
        The stderr should include "timed out"
      End
    End

    Context "when using default port"
      cleanup_env_no_port() {
        unset SENTINEL_SERVICE_PORT SENTINEL_PASSWORD REDIS_CLI_TLS_CMD
      }
      BeforeEach 'cleanup_env_no_port'
      AfterEach 'cleanup_env_no_port'

      redis-cli() {
        echo "PONG"
        return 0
      }

      It "defaults to port 26379"
        When call check_redis_sentinel_ok
        The status should be success
      End
    End
  End

  Describe "retry_check_redis_sentinel_ok()"
    setup_env() {
      export SENTINEL_SERVICE_PORT="26379"
      export SENTINEL_PASSWORD="sentinelpass"
      export REDIS_CLI_TLS_CMD=""
    }

    cleanup_env() {
      unset SENTINEL_SERVICE_PORT SENTINEL_PASSWORD REDIS_CLI_TLS_CMD
    }

    Context "when sentinel is healthy"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "PONG"
        return 0
      }

      It "returns success"
        When call retry_check_redis_sentinel_ok
        The status should be success
      End
    End

    Context "when sentinel is permanently down"
      BeforeEach 'setup_env'
      AfterEach 'cleanup_env'

      redis-cli() {
        echo "Could not connect" >&2
        return 1
      }

      It "returns failure after retries"
        When call retry_check_redis_sentinel_ok
        The status should be failure
        The stderr should include "Redis sentinel is not running"
      End
    End
  End
End
