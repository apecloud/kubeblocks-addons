# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154
# shellcheck disable=SC2168

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_sentinel_account_provision_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis Sentinel Account Provision Script Tests"
  Include ../scripts/redis-sentinel-account-provision.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "redis_sentinel_account_provision()"
    Context "when executing account statement"
      redis-cli() {
        echo "OK"
        return 0
      }

      setup() {
        export SENTINEL_SERVICE_PORT="26379"
        export SENTINEL_PASSWORD="sentpw"
        export KB_ACCOUNT_STATEMENT="ACL SETUSER testuser ON >password ~* +@all"
        export REDIS_CLI_TLS_CMD=""
      }
      Before "setup"

      It "runs statement and saves ACL"
        When run redis_sentinel_account_provision
        The status should be success
        The stdout should include "OK"
      End
    End

    Context "when password is included in command"
      redis-cli() {
        if echo "$*" | grep -q -- "-a sentpw"; then
          echo "OK"
          return 0
        fi
        echo "NOAUTH"
        return 1
      }

      setup() {
        export SENTINEL_SERVICE_PORT="26379"
        export SENTINEL_PASSWORD="sentpw"
        export KB_ACCOUNT_STATEMENT="ACL SETUSER testuser ON >pw ~* +@all"
        export REDIS_CLI_TLS_CMD=""
      }
      Before "setup"

      It "includes -a flag with sentinel password"
        When run redis_sentinel_account_provision
        The status should be success
        The stdout should include "OK"
        The stdout should not include "NOAUTH"
      End
    End

    Context "with TLS flags"
      redis-cli() {
        if echo "$*" | grep -q -- "--tls"; then
          echo "OK"
          return 0
        fi
        echo "NO_TLS"
        return 1
      }

      setup() {
        export SENTINEL_SERVICE_PORT="26379"
        export SENTINEL_PASSWORD="sentpw"
        export KB_ACCOUNT_STATEMENT="ACL SETUSER testuser ON >pw ~* +@all"
        export REDIS_CLI_TLS_CMD="--tls --cert /certs/tls.crt"
      }
      Before "setup"

      It "passes TLS flags to redis-cli"
        When run redis_sentinel_account_provision
        The status should be success
        The stdout should include "OK"
        The stdout should not include "NO_TLS"
      End
    End

    Context "with custom sentinel port"
      redis-cli() {
        if echo "$*" | grep -q -- "-p 36379"; then
          echo "OK"
          return 0
        fi
        echo "WRONG_PORT"
        return 1
      }

      setup() {
        export SENTINEL_SERVICE_PORT="36379"
        export SENTINEL_PASSWORD="sentpw"
        export KB_ACCOUNT_STATEMENT="ACL SETUSER testuser ON >pw ~* +@all"
        export REDIS_CLI_TLS_CMD=""
      }
      Before "setup"

      It "uses custom sentinel port"
        When run redis_sentinel_account_provision
        The status should be success
        The stdout should include "OK"
        The stdout should not include "WRONG_PORT"
      End
    End
  End
End
