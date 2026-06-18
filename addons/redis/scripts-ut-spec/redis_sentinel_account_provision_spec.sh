# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_sentinel_account_provision_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis Sentinel Account Provision Script Tests"
  Include ../scripts/redis-sentinel-account-provision.sh

  init() {
    ut_mode="true"
    export SENTINEL_SERVICE_PORT="26379"
    export SENTINEL_PASSWORD="sentpass"
    export REDIS_CLI_TLS_CMD=""
    export KB_ACCOUNT_STATEMENT="ACL SETUSER testuser on >password ~* +@all"
  }
  BeforeAll "init"

  cleanup() {
    unset SENTINEL_SERVICE_PORT SENTINEL_PASSWORD REDIS_CLI_TLS_CMD KB_ACCOUNT_STATEMENT
  }
  AfterAll "cleanup"

  Describe "provision_sentinel_account()"
    Context "when redis-cli succeeds for both statement and acl save"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "returns success"
        When call provision_sentinel_account
        The status should be success
      End
    End

    Context "when account statement returns ERR output"
      redis-cli() {
        if echo "$*" | grep -q "acl save"; then
          echo "OK"
          return 0
        fi
        echo "ERR unknown command"
        return 0
      }

      It "returns failure with error message"
        When call provision_sentinel_account
        The status should be failure
        The stderr should include "sentinel account provision failed"
      End
    End

    Context "when account statement returns a Redis auth or ACL error with zero exit"
      redis-cli() {
        if echo "$*" | grep -q "acl save"; then
          echo "OK"
          return 0
        fi
        echo "$REDIS_ERROR_REPLY"
        return 0
      }

      Parameters
        "NOAUTH Authentication required."
        "WRONGPASS invalid username-password pair"
        "NOPERM this user has no permissions to run the 'acl' command"
      End

      It "returns failure for $1"
        REDIS_ERROR_REPLY="$1"
        When call provision_sentinel_account
        The status should be failure
        The stderr should include "sentinel account provision failed"
        The stderr should include "$1"
      End
    End

    Context "when redis-cli connection fails on statement"
      redis-cli() {
        if echo "$*" | grep -q "acl save"; then
          echo "OK"
          return 0
        fi
        echo "Could not connect to Redis" >&2
        return 1
      }

      It "returns failure"
        When call provision_sentinel_account
        The status should be failure
        The stderr should include "sentinel account provision failed"
        The stderr should include "connection error"
      End
    End

    Context "when acl save connection fails"
      redis-cli() {
        if echo "$*" | grep -q "acl save"; then
          return 1
        fi
        echo "OK"
        return 0
      }

      It "returns failure with acl save connection error"
        When call provision_sentinel_account
        The status should be failure
        The stderr should include "acl save connection error"
      End
    End

    Context "when acl save returns Redis error with zero exit"
      redis-cli() {
        if echo "$*" | grep -q "acl save"; then
          echo "ERR operation not permitted"
          return 0
        fi
        echo "OK"
        return 0
      }

      It "returns failure with acl save error"
        When call provision_sentinel_account
        The status should be failure
        The stderr should include "acl save error"
      End
    End
  End
End
