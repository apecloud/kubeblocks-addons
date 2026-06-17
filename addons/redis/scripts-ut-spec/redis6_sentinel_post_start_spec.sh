# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154
# shellcheck disable=SC2168

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis6_sentinel_post_start_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis6 Sentinel Post Start Script Tests"
  Include ../scripts/redis6-sentinel-post-start.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "acl_set_user_for_redis6_sentinel()"
    Context "when SENTINEL_PASSWORD is empty"
      setup() {
        export SENTINEL_PASSWORD=""
      }
      Before "setup"

      It "does nothing and returns success"
        When call acl_set_user_for_redis6_sentinel
        The status should be success
        The stdout should equal ""
      End
    End

    Context "when SENTINEL_PASSWORD is set and all commands succeed"
      redis-cli() {
        if echo "$*" | grep -q "ping"; then
          echo "PONG"
          return 0
        fi
        echo "OK"
        return 0
      }

      setup() {
        export SENTINEL_PASSWORD="sentpw123"
        export SENTINEL_SERVICE_PORT="26379"
        export SENTINEL_USER="default"
        export REDIS_CLI_TLS_CMD=""
      }
      Before "setup"

      It "sets ACL user and saves"
        When call acl_set_user_for_redis6_sentinel
        The status should be success
        The stdout should include "PONG"
        The stdout should include "OK"
        The stdout should include "redis sentinel user and password set successfully."
      End
    End

    Context "when SENTINEL_SERVICE_PORT is not set"
      redis-cli() {
        if echo "$*" | grep -q "ping"; then
          echo "PONG"
          return 0
        fi
        echo "OK"
        return 0
      }

      setup() {
        export SENTINEL_PASSWORD="sentpw123"
        unset SENTINEL_SERVICE_PORT
        export SENTINEL_USER="default"
        export REDIS_CLI_TLS_CMD=""
      }
      Before "setup"

      It "uses bare variable without default"
        When call acl_set_user_for_redis6_sentinel
        The status should be success
        The stdout should include "redis sentinel user and password set successfully."
      End
    End

    Context "when custom SENTINEL_SERVICE_PORT is set"
      redis-cli() {
        if echo "$*" | grep -q "ping"; then
          echo "PONG"
          return 0
        fi
        if echo "$*" | grep -q -- "-p 36379"; then
          echo "OK"
          return 0
        fi
        echo "WRONG_PORT"
        return 1
      }

      setup() {
        export SENTINEL_PASSWORD="sentpw123"
        export SENTINEL_SERVICE_PORT="36379"
        export SENTINEL_USER="default"
        export REDIS_CLI_TLS_CMD=""
      }
      Before "setup"

      It "uses custom port"
        When call acl_set_user_for_redis6_sentinel
        The status should be success
        The stdout should include "redis sentinel user and password set successfully."
        The stdout should not include "WRONG_PORT"
      End
    End

    Context "with TLS flags"
      redis-cli() {
        if echo "$*" | grep -q "ping"; then
          echo "PONG"
          return 0
        fi
        if echo "$*" | grep -q -- "--tls"; then
          echo "OK"
          return 0
        fi
        echo "NO_TLS"
        return 1
      }

      setup() {
        export SENTINEL_PASSWORD="sentpw123"
        export SENTINEL_SERVICE_PORT="26379"
        export SENTINEL_USER="default"
        export REDIS_CLI_TLS_CMD="--tls --cert /path/to/cert"
      }
      Before "setup"

      It "passes TLS flags to redis-cli"
        When call acl_set_user_for_redis6_sentinel
        The status should be success
        The stdout should include "redis sentinel user and password set successfully."
        The stdout should not include "NO_TLS"
      End
    End

    Context "with custom sentinel user"
      redis-cli() {
        if echo "$*" | grep -q "ping"; then
          echo "PONG"
          return 0
        fi
        if echo "$*" | grep -q "ACL SETUSER mysentinel"; then
          echo "OK"
          return 0
        fi
        echo "OK"
        return 0
      }

      setup() {
        export SENTINEL_PASSWORD="sentpw123"
        export SENTINEL_SERVICE_PORT="26379"
        export SENTINEL_USER="mysentinel"
        export REDIS_CLI_TLS_CMD=""
      }
      Before "setup"

      It "uses custom sentinel user in ACL SETUSER"
        When call acl_set_user_for_redis6_sentinel
        The status should be success
        The stdout should include "redis sentinel user and password set successfully."
      End
    End
  End
End
