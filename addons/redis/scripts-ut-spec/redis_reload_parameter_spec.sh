# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154
# shellcheck disable=SC2168

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_reload_parameter_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis Reload Parameter Script Tests"
  Include ../scripts/reload-parameter.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "reload_redis_parameter()"
    Context "with simple key-value in single argument"
      redis-cli() {
        echo "OK"
        return 0
      }

      setup() {
        export REDIS_DEFAULT_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
      }
      Before "setup"

      It "parses param name and value correctly"
        When run reload_redis_parameter "maxmemory 100mb"
        The status should be success
        The stdout should include "OK"
      End
    End

    Context "with multi-word value in single argument"
      redis-cli() {
        echo "OK"
        return 0
      }

      setup() {
        export REDIS_DEFAULT_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
      }
      Before "setup"

      It "joins multi-word values"
        When run reload_redis_parameter "save 900 1 300 10"
        The status should be success
        The stdout should include "OK"
      End
    End

    Context "with empty-string value (double-quoted empty)"
      redis-cli() {
        echo "OK"
        return 0
      }

      setup() {
        export REDIS_DEFAULT_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
      }
      Before "setup"

      It "converts quoted empty string to empty value"
        When run reload_redis_parameter 'requirepass ""'
        The status should be success
        The stdout should include "OK"
      End
    End

    Context "with password set"
      redis-cli() {
        if echo "$*" | grep -q -- "-a mypassword"; then
          echo "OK"
        else
          echo "NOAUTH"
        fi
        return 0
      }

      setup() {
        export REDIS_DEFAULT_PASSWORD="mypassword"
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
      }
      Before "setup"

      It "includes -a flag with password"
        When run reload_redis_parameter "maxmemory 100mb"
        The status should be success
        The stdout should include "OK"
      End
    End

    Context "without password"
      redis-cli() {
        if echo "$*" | grep -q -- "-a"; then
          echo "UNEXPECTED_AUTH"
        else
          echo "OK"
        fi
        return 0
      }

      setup() {
        export REDIS_DEFAULT_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
      }
      Before "setup"

      It "does not include -a flag"
        When run reload_redis_parameter "maxmemory 100mb"
        The status should be success
        The stdout should include "OK"
        The stdout should not include "UNEXPECTED_AUTH"
      End
    End

    Context "with custom service port"
      redis-cli() {
        if echo "$*" | grep -q -- "-p 6380"; then
          echo "OK"
        else
          echo "WRONG_PORT"
        fi
        return 0
      }

      setup() {
        export REDIS_DEFAULT_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        service_port=6380
      }
      Before "setup"

      It "uses custom port"
        When run reload_redis_parameter "maxmemory 100mb"
        The status should be success
        The stdout should include "OK"
        The stdout should not include "WRONG_PORT"
      End
    End

    Context "with TLS command"
      redis-cli() {
        if echo "$*" | grep -q -- "--tls --cert"; then
          echo "OK"
        else
          echo "NO_TLS"
        fi
        return 0
      }

      setup() {
        export REDIS_DEFAULT_PASSWORD=""
        export REDIS_CLI_TLS_CMD="--tls --cert /path/to/cert"
        service_port=6379
      }
      Before "setup"

      It "includes TLS command flags"
        When run reload_redis_parameter "maxmemory 100mb"
        The status should be success
        The stdout should include "OK"
        The stdout should not include "NO_TLS"
      End
    End

    Context "when redis-cli fails"
      redis-cli() {
        echo "ERR unknown command"
        return 1
      }

      setup() {
        export REDIS_DEFAULT_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
      }
      Before "setup"

      It "propagates failure"
        When run reload_redis_parameter "invalidparam value"
        The status should be failure
        The stdout should include "ERR"
      End
    End

    Context "with param name only in first arg and value in remaining args"
      redis-cli() {
        echo "OK"
        return 0
      }

      setup() {
        export REDIS_DEFAULT_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
      }
      Before "setup"

      It "takes value from remaining positional args"
        When run reload_redis_parameter "maxmemory" "100mb"
        The status should be success
        The stdout should include "OK"
      End
    End
  End
End
