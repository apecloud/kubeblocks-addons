# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_switchover_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Switchover Script Tests"

  Include ../scripts/redis-switchover.sh
  Include $common_library_file

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "switchover"
    setup() {
      export REDIS_DEFAULT_PASSWORD="redis_default_password"
      export SENTINEL_POD_FQDN_LIST="redis-redis-sentinel-0.redis-redis-sentinel-headless.test.svc,\
        redis-redis-sentinel-1.redis-redis-sentinel-headless.test.svc,\
        redis-redis-sentinel-2.redis-redis-sentinel-headless.test.svc"
      export KB_SWITCHOVER_CANDIDATE_FQDN="redis-redis-1.redis-redis-headless.default.svc.local"
      export REDIS_COMPONENT_NAME="redis-redis"
    }
    Before 'setup'

    un_setup() {
      unset REDIS_DEFAULT_PASSWORD
      unset SENTINEL_POD_FQDN_LIST
      unset KB_SWITCHOVER_CANDIDATE_FQDN
      unset REDIS_COMPONENT_NAME
    }
    After 'un_setup'

    Context "switchoverWithCandidate()"
      It "redis set recover replica priority should equal pre state and sentinel failover should start"
        check_connectivity() {
          echo "$KB_SWITCHOVER_CANDIDATE_FQDN is reachable on port 6379."
          return 0
        }
        redis_config_get() {
          echo -e "replica-priority\n100"
          return 0
        }
        execute_sub_command() {
          echo "Command executed successfully."
          return 0
        }
        When call switchoverWithCandidate
        The status should be success
        The stdout should include "Sentinel failover start with redis-redis-sentinel-0.redis-redis-sentinel-headless.test.svc, Switchover is processing"
        The stdout should include "Command executed successfully"
      End
    End
    Context "switchoverWithoutCandidate()"
      It "sentinel failover should start"
        execute_sub_command() {
          echo "Command executed successfully."
          return 0
        }
        When call switchoverWithoutCandidate
        The status should be success
        The stdout should include "Sentinel failover start with redis-redis-sentinel-0.redis-redis-sentinel-headless.test.svc, Switchover is processing"
        The stdout should include "Command executed successfully"
      End
    End
  End
End