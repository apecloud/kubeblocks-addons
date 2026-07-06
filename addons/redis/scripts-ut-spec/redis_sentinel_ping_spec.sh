# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154
# shellcheck disable=SC2168

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
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "check_redis_sentinel_ok()"
    Context "when ping succeeds without password"
      setup() {
        unset SENTINEL_PASSWORD
        unset SENTINEL_SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      It "returns success when redis-cli returns PONG"
        redis-cli() {
          echo "PONG"
          return 0
        }
        When call check_redis_sentinel_ok
        The status should be success
      End
    End

    Context "when ping succeeds with password"
      setup() {
        SENTINEL_PASSWORD="mypassword"
        unset SENTINEL_SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      After 'unset SENTINEL_PASSWORD'

      It "returns success and uses -a flag"
        redis-cli() {
          if [[ " $* " == *" -a mypassword "* ]]; then
            echo "PONG"
            return 0
          fi
          echo "ERR"
          return 1
        }
        When call check_redis_sentinel_ok
        The status should be success
      End
    End

    Context "when ping returns non-PONG response"
      setup() {
        unset SENTINEL_PASSWORD
        unset SENTINEL_SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      It "returns failure with error message"
        redis-cli() {
          echo "LOADING Redis is loading the dataset in memory"
          return 0
        }
        When call check_redis_sentinel_ok
        The status should be failure
        The stderr should include "redis sentinel ping failed"
      End
    End

    Context "when ping times out with exit code 124"
      setup() {
        unset SENTINEL_PASSWORD
        unset SENTINEL_SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      It "returns failure with timeout message"
        redis-cli() {
          return 124
        }
        When call check_redis_sentinel_ok
        The status should be failure
        The stderr should include "redis sentinel ping timed out"
      End
    End

    Context "when custom port is set"
      setup() {
        unset SENTINEL_PASSWORD
        SENTINEL_SERVICE_PORT="36379"
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      After 'unset SENTINEL_SERVICE_PORT'

      It "uses the custom port"
        redis-cli() {
          if [[ " $* " == *" -p 36379 "* ]]; then
            echo "PONG"
            return 0
          fi
          echo "ERR wrong port"
          return 1
        }
        When call check_redis_sentinel_ok
        The status should be success
      End
    End

    Context "when default port is used"
      setup() {
        unset SENTINEL_PASSWORD
        unset SENTINEL_SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      It "uses port 26379"
        redis-cli() {
          if [[ " $* " == *" -p 26379 "* ]]; then
            echo "PONG"
            return 0
          fi
          echo "ERR wrong port"
          return 1
        }
        When call check_redis_sentinel_ok
        The status should be success
      End
    End

    Context "when TLS flags are set"
      setup() {
        unset SENTINEL_PASSWORD
        unset SENTINEL_SERVICE_PORT
        REDIS_CLI_TLS_CMD="--tls --cert /certs/tls.crt --key /certs/tls.key --cacert /certs/ca.crt"
      }
      Before 'setup'

      After 'unset REDIS_CLI_TLS_CMD'

      It "includes TLS flags in the command"
        redis-cli() {
          if [[ " $* " == *" --tls "* ]]; then
            echo "PONG"
            return 0
          fi
          echo "ERR no tls"
          return 1
        }
        When call check_redis_sentinel_ok
        The status should be success
      End
    End
  End

  Describe "retry_check_redis_sentinel_ok()"
    # call_func_with_retry uses real sleep; mock it to avoid 12s delay
    sleep() { :; }

    Context "when check succeeds on first try"
      setup() {
        unset SENTINEL_PASSWORD
        unset SENTINEL_SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      It "returns success"
        redis-cli() {
          echo "PONG"
          return 0
        }
        When call retry_check_redis_sentinel_ok
        The status should be success
      End
    End

    Context "when all retries fail"
      setup() {
        unset SENTINEL_PASSWORD
        unset SENTINEL_SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      It "returns failure with not running message"
        redis-cli() {
          echo "ERR"
          return 1
        }
        When call retry_check_redis_sentinel_ok
        The status should be failure
        The stderr should include "Redis sentinel is not running."
      End
    End
  End
End
