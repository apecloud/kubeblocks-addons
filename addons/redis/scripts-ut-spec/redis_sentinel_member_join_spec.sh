# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_sentinel_member_join_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Sentinel Member Join Script Tests"

  Include ../scripts/redis-sentinel-member-join.sh
  Include $common_library_file

  init() {
    redis_sentinel_real_conf="./redis_sentinel.conf"
    redis_sentinel_real_conf_bak="./redis_sentinel.conf.bak"
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f ./redis_sentinel.conf;
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "recover_registered_redis_servers()"
    Context "register master with pod fqdn"
      setup() {
          REDIS_COMPONENT_NAME="redis-redis"
          REDIS_POD_NAME_LIST="redis-redis-0,redis-redis-1"
          REDIS_POD_FQDN_LIST="redis-redis-0.redis-redis-headless.test.svc,redis-redis-1.redis-redis-headless.test.svc"
          REDIS_SENTINEL_USER="sentinel_user"
          REDIS_SENTINEL_PASSWORD="redis_sentinel_password"
          SENTINEL_PASSWORD="sentinel_password"
          SERVICE_VERSION="7.2.4"
      }
      Before 'setup'

      un_setup() {
        unset REDIS_COMPONENT_NAME
        unset REDIS_POD_NAME_LIST
        unset REDIS_POD_FQDN_LIST
        unset REDIS_SENTINEL_USER
        unset REDIS_SENTINEL_PASSWORD
        unset SENTINEL_PASSWORD
        unset SERVICE_VERSION
        unset REDIS_ADVERTISED_PORT
        unset REDIS_LB_ADVERTISED_PORT
        unset REDIS_LB_ADVERTISED_HOST
        unset CURRENT_POD_HOST_IP
        redis_announce_host_value=""
        redis_announce_port_value=""
      }
      After 'un_setup'

      It "registers the default primary pod fqdn as master to local sentinel"
        redis-cli() {
          if [[ "$*" == *"get-master-addr-by-name"* ]]; then
            return 0
          fi
          echo "CMD: $*"
          return 0
        }
        When call recover_registered_redis_servers
        The status should be success
        The stdout should include "SENTINEL MONITOR redis-redis redis-redis-0.redis-redis-headless.test.svc 6379 2"
        The stdout should include "SENTINEL SET redis-redis down-after-milliseconds 20000"
        The stdout should include "SENTINEL SET redis-redis failover-timeout 60000"
        The stdout should include "SENTINEL SET redis-redis parallel-syncs 1"
        The stdout should include "SENTINEL SET redis-redis auth-user sentinel_user"
        The stdout should include "SENTINEL SET redis-redis auth-pass redis_sentinel_password"
        The stdout should include "register master redis-redis to local sentinel succeeded!"
      End

      It "registers master with the advertised address when REDIS_ADVERTISED_PORT is set"
        REDIS_ADVERTISED_PORT="redis-redis-advertised-0:32024,redis-redis-advertised-1:31318"
        CURRENT_POD_HOST_IP="10.13.25.17"
        redis-cli() {
          if [[ "$*" == *"get-master-addr-by-name"* ]]; then
            return 0
          fi
          echo "CMD: $*"
          return 0
        }
        When call recover_registered_redis_servers
        The status should be success
        The stdout should include "SENTINEL MONITOR redis-redis 10.13.25.17 32024 2"
      End

      It "skips SENTINEL MONITOR when the master is already monitored"
        redis-cli() {
          if [[ "$*" == *"get-master-addr-by-name"* ]]; then
            echo "redis-redis-0.redis-redis-headless.test.svc 6379"
            return 0
          fi
          echo "CMD: $*"
          return 0
        }
        When call recover_registered_redis_servers
        The status should be success
        The stdout should include "master redis-redis is already monitored, skip SENTINEL MONITOR"
        The stdout should include "SENTINEL SET redis-redis down-after-milliseconds 20000"
        The stdout should not include "SENTINEL MONITOR redis-redis redis-redis-0.redis-redis-headless.test.svc 6379 2"
      End
    End

    Context "on redis 5"
      setup() {
          REDIS_COMPONENT_NAME="redis-redis"
          REDIS_POD_NAME_LIST="redis-redis-0,redis-redis-1"
          REDIS_POD_FQDN_LIST="redis-redis-0.redis-redis-headless.test.svc,redis-redis-1.redis-redis-headless.test.svc"
          REDIS_SENTINEL_USER="sentinel_user"
          REDIS_SENTINEL_PASSWORD="redis_sentinel_password"
          SENTINEL_PASSWORD="sentinel_password"
          SERVICE_VERSION="5.0.12"
      }
      Before 'setup'

      un_setup() {
        unset REDIS_COMPONENT_NAME
        unset REDIS_POD_NAME_LIST
        unset REDIS_POD_FQDN_LIST
        unset REDIS_SENTINEL_USER
        unset REDIS_SENTINEL_PASSWORD
        unset SENTINEL_PASSWORD
        unset SERVICE_VERSION
        unset REDIS_ADVERTISED_PORT
        unset REDIS_LB_ADVERTISED_PORT
        unset REDIS_LB_ADVERTISED_HOST
        unset CURRENT_POD_HOST_IP
        redis_announce_host_value=""
        redis_announce_port_value=""
      }
      After 'un_setup'
      It "skips sentinel auth-user for redis 5"
        redis-cli() {
          if [[ "$*" == *"get-master-addr-by-name"* ]]; then
            return 0
          fi
          echo "CMD: $*"
          return 0
        }
        When call recover_registered_redis_servers
        The status should be success
        The stdout should include "SENTINEL MONITOR redis-redis redis-redis-0.redis-redis-headless.test.svc 6379 2"
        The stdout should include "SENTINEL SET redis-redis auth-pass redis_sentinel_password"
        The stdout should not include "auth-user"
      End
    End

    Context "when required environment variables are missing"
      It "fails when REDIS_COMPONENT_NAME is not set"
        unset REDIS_COMPONENT_NAME
        unset REDIS_POD_NAME_LIST
        unset REDIS_POD_FQDN_LIST
        When call recover_registered_redis_servers
        The status should be failure
        The stderr should include "REDIS_COMPONENT_NAME, REDIS_POD_NAME_LIST and REDIS_POD_FQDN_LIST is not set"
      End
    End
  End

  Describe "sentinel ACL sync contract"
    # A joining Sentinel starts with only the "default" user (written by
    # redis-sentinel-start-v2.sh from SENTINEL_PASSWORD) and Sentinel never
    # replicates ACLs between peers, so memberJoin has to push the fleet ACL.
    It "runs the sentinel ACL sync after the master registration"
      When call grep -F "redis-sentinel-sync-acl.sh" "../scripts/redis-sentinel-member-join.sh"
      The status should be success
      The stdout should include "redis-sentinel-sync-acl.sh"
    End

    It "fails the action when the ACL sync fails"
      When call grep -F "sentinel ACL sync failed" "../scripts/redis-sentinel-member-join.sh"
      The status should be success
      The stdout should include "sentinel ACL sync failed"
    End
  End
End