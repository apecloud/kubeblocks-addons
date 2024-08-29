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
    setup() {
        REDIS_SENTINEL_PASSWORD="redis_sentinel_password"
    }
    Before 'setup'

    un_setup() {
      unset REDIS_SENTINEL_PASSWORD
    }
    After 'un_setup'
    Context "one redis master monitor"
      setup() {
          SENTINEL_POD_FQDN_LIST="redis-redis-sentinel-0.redis-redis-sentinel-headless.test.svc,\
          redis-redis-sentinel-1.redis-redis-sentinel-headless.test.svc,\
          redis-redis-sentinel-2.redis-redis-sentinel-headless.test.svc"
          REDIS_SENTINEL_USER="sentinel_user"
          REDIS_SENTINEL_PASSWORD="redis_sentinel_password"
          SENTINEL_PASSWORD="sentinel_password"
          CLUSTER_NAME="redis"
      }
      Before 'setup'

      un_setup() {
        unset SENTINEL_POD_FQDN_LIST
        unset REDIS_SENTINEL_USER
        unset REDIS_SENTINEL_PASSWORD
        unset SENTINEL_PASSWORD
      }
      After 'un_setup'


      It "when one redis master monitor and is reachable"
        redis_sentinel_get_masters() {
          temp_output="name
          mymaster
          ip
          172.20.0.1
          port
          30746
          flags
          master
          down-after-milliseconds
          5000
          quorum
          2
          failover-timeout
          60000
          parallel-syncs
          1"
        }
        When call recover_registered_redis_servers
        The status should be success
        The stdout should include "all masters are reachable"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel monitor mymaster 172.20.0.1 30746 2"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel down-after-milliseconds mymaster 5000"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel failover-timeout mymaster 60000"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel parallel-syncs mymaster 1"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel auth-user mymaster $REDIS_SENTINEL_USER"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel auth-pass mymaster $REDIS_SENTINEL_PASSWORD"
      End

      It "when one master are disconnected"
        redis_sentinel_get_masters() {
          temp_output="flags
          master,disconnected"
        }
        When call recover_registered_redis_servers
        The stdout should include "one or more masters are disconnected"
      End
    End
    Context "mutil redis matser monitor"
      setup() {
          SENTINEL_POD_FQDN_LIST="redis-redis-sentinel-0.redis-redis-sentinel-headless.test.svc,\
          redis-redis-sentinel-1.redis-redis-sentinel-headless.test.svc,\
          redis-redis-sentinel-2.redis-redis-sentinel-headless.test.svc"
          REDIS_SENTINEL_USER="sentinel_user"
          REDIS_SENTINEL_PASSWORD="redis_sentinel_password"
          SENTINEL_PASSWORD="sentinel_password"
          REDIS_SENTINEL_PASSWORD_REDIS0="redis0_sentinel_password"
          REDIS_SENTINEL_PASSWORD_REDIS1="redis1_sentinel_password"
          CLUSTER_NAME="redis"
      }
      Before 'setup'

      un_setup() {
        unset SENTINEL_POD_FQDN_LIST
        unset REDIS_SENTINEL_USER
        unset REDIS_SENTINEL_PASSWORD
        unset SENTINEL_PASSWORD
        unset REDIS_SENTINEL_PASSWORD_REDIS0
        unset REDIS_SENTINEL_PASSWORD_REDIS1
        unset CLUSTER_NAME
      }
      After 'un_setup'
      It "when mutil redis master monitor and is reachable"
        redis_sentinel_get_masters() {
          temp_output="name
          redis-redis0
          ip
          172.20.0.1
          port
          30746
          flags
          master
          down-after-milliseconds
          5000
          quorum
          2
          failover-timeout
          60000
          parallel-syncs
          1
          name
          redis-redis1
          ip
          172.20.0.2
          port
          30747
          flags
          master
          down-after-milliseconds
          5000
          quorum
          2
          failover-timeout
          60000
          parallel-syncs
          1"
        }
        When call recover_registered_redis_servers
        The status should be success
        The stdout should include "all masters are reachable"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel monitor redis-redis0 172.20.0.1 30746 2"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel down-after-milliseconds redis-redis0 5000"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel failover-timeout redis-redis0 60000"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel parallel-syncs redis-redis0 1"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel auth-user redis-redis0 $REDIS_SENTINEL_USER"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel auth-pass redis-redis0 $REDIS_SENTINEL_PASSWORD_REDIS0"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel monitor redis-redis1 172.20.0.2 30747 2"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel down-after-milliseconds redis-redis1 5000"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel failover-timeout redis-redis1 60000"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel parallel-syncs redis-redis1 1"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel auth-user redis-redis1 $REDIS_SENTINEL_USER"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel auth-pass redis-redis1 $REDIS_SENTINEL_PASSWORD_REDIS1"
      End
    End
  End
End