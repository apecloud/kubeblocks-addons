# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154
# shellcheck disable=SC2168

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_reset_master_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis Reset Master Script Tests"
  Include ../scripts/reset-master.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "reset_master_in_sentinels()"
    Context "when SENTINEL_POD_NAME_LIST is empty"
      setup() {
        export SENTINEL_POD_NAME_LIST=""
      }
      Before "setup"

      It "exits successfully with no action"
        When run reset_master_in_sentinels
        The status should be success
      End
    End

    Context "when single sentinel resets successfully"
      redis-cli() {
        echo "1"
        return 0
      }

      setup() {
        export SENTINEL_POD_NAME_LIST="sentinel-0"
        export SENTINEL_HEADLESS_SERVICE_NAME="redis-sentinel-headless"
        export CLUSTER_NAMESPACE="default"
        export REDIS_COMPONENT_NAME="redis"
        export SENTINEL_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        sentinel_service_port=26379
      }
      Before "setup"

      It "resets and exits successfully"
        When run reset_master_in_sentinels
        The status should be success
        The stdout should include "reset master in sentinel"
        The stdout should include "succeeded"
      End
    End

    Context "when first sentinel fails but second succeeds"
      call_count=0
      redis-cli() {
        call_count=$((call_count + 1))
        if [ "$call_count" -eq 1 ]; then
          echo "ERR No such master"
          return 1
        fi
        echo "1"
        return 0
      }

      setup() {
        export SENTINEL_POD_NAME_LIST="sentinel-0,sentinel-1"
        export SENTINEL_HEADLESS_SERVICE_NAME="redis-sentinel-headless"
        export CLUSTER_NAMESPACE="default"
        export REDIS_COMPONENT_NAME="redis"
        export SENTINEL_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        sentinel_service_port=26379
      }
      Before "setup"

      It "falls through to second sentinel"
        When run reset_master_in_sentinels
        The status should be success
        The stdout should include "succeeded"
      End
    End

    Context "when all sentinels fail"
      redis-cli() {
        echo "ERR No such master"
        return 1
      }

      setup() {
        export SENTINEL_POD_NAME_LIST="sentinel-0,sentinel-1"
        export SENTINEL_HEADLESS_SERVICE_NAME="redis-sentinel-headless"
        export CLUSTER_NAMESPACE="default"
        export REDIS_COMPONENT_NAME="redis"
        export SENTINEL_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        sentinel_service_port=26379
      }
      Before "setup"

      It "exits with failure"
        When run reset_master_in_sentinels
        The status should be failure
        The stdout should include "reset master in sentinel failed"
      End
    End

    Context "with sentinel password"
      redis-cli() {
        if echo "$*" | grep -q -- "-a sentinelpw"; then
          echo "1"
          return 0
        fi
        echo "NOAUTH"
        return 1
      }

      setup() {
        export SENTINEL_POD_NAME_LIST="sentinel-0"
        export SENTINEL_HEADLESS_SERVICE_NAME="redis-sentinel-headless"
        export CLUSTER_NAMESPACE="default"
        export REDIS_COMPONENT_NAME="redis"
        export SENTINEL_PASSWORD="sentinelpw"
        export REDIS_CLI_TLS_CMD=""
        sentinel_service_port=26379
      }
      Before "setup"

      It "includes -a flag with password"
        When run reset_master_in_sentinels
        The status should be success
        The stdout should include "succeeded"
      End
    End

    Context "without sentinel password"
      redis-cli() {
        if echo "$*" | grep -q -- "-a"; then
          echo "UNEXPECTED_AUTH"
          return 1
        fi
        echo "1"
        return 0
      }

      setup() {
        export SENTINEL_POD_NAME_LIST="sentinel-0"
        export SENTINEL_HEADLESS_SERVICE_NAME="redis-sentinel-headless"
        export CLUSTER_NAMESPACE="default"
        export REDIS_COMPONENT_NAME="redis"
        export SENTINEL_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        sentinel_service_port=26379
      }
      Before "setup"

      It "does not include -a flag"
        When run reset_master_in_sentinels
        The status should be success
        The stdout should include "succeeded"
        The stdout should not include "UNEXPECTED_AUTH"
      End
    End

    Context "with multiple sentinels in comma-separated list"
      redis-cli() {
        echo "1"
        return 0
      }

      setup() {
        export SENTINEL_POD_NAME_LIST="sentinel-0,sentinel-1,sentinel-2"
        export SENTINEL_HEADLESS_SERVICE_NAME="redis-sentinel-headless"
        export CLUSTER_NAMESPACE="default"
        export REDIS_COMPONENT_NAME="redis"
        export SENTINEL_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        sentinel_service_port=26379
      }
      Before "setup"

      It "exits after first successful reset"
        When run reset_master_in_sentinels
        The status should be success
        The stdout should include "succeeded"
      End
    End
  End
End
