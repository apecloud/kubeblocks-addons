#shellcheck shell=bash

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Start Sentinel Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/redis-sentinel-start-v2.sh
  Include $common_library_file

  init() {
    redis_sentinel_real_conf="./redis_sentinel.conf"
    # set ut_mode to true to hack control flow in the script
    # shellcheck disable=SC2034
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f ./redis_sentinel.conf;
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "build_redis_sentinel_conf()"
    setup() {
        echo "" > $redis_sentinel_real_conf
        sentinel_port="26379"
        CURRENT_POD_NAME="redis-redis-sentinel-0"
        SENTINEL_POD_FQDN_LIST="redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local,redis-redis-sentinel-1.redis-redis-sentinel-headless.default.svc.cluster.local"
        SENTINEL_USER="default"
        SENTINEL_PASSWORD="sentinel_password"
      }
      Before 'setup'

      un_setup() {
        unset sentinel_port
        unset CURRENT_POD_NAME
        unset SENTINEL_USER
        unset SENTINEL_PASSWOR
      }
      After 'un_setup'

    It "build redis sentinel conf when sentinel_password are set"
      When call build_redis_sentinel_conf
      The status should be success
      The stdout should include "build redis sentinel conf succeeded!"
      The contents of file "$redis_sentinel_real_conf" should include "port $sentinel_port"
      The contents of file "$redis_sentinel_real_conf" should include "sentinel announce-ip $CURRENT_POD_NAME.redis-redis-sentinel-headless.default.svc.cluster.local"
      The contents of file "$redis_sentinel_real_conf" should include "resolve-hostnames yes"
      The contents of file "$redis_sentinel_real_conf" should include "announce-hostnames yes"
      The contents of file "$redis_sentinel_real_conf" should include "sentinel sentinel-user $SENTINEL_USER"
      The contents of file "$redis_sentinel_real_conf" should include "sentinel sentinel-pass $SENTINEL_PASSWORD"
    End
  End

  Describe "recover_registered_redis_servers()"
    setup() {
        REDIS_SENTINEL_PASSWORD="redis_sentinel_password"
    }
    Before 'setup'

    un_setup() {
      unset REDIS_SENTINEL_PASSWORD
    }
    After 'un_setup'
    Context "one redis matser monitor"
      setup() {
          SENTINEL_POD_FQDN_LIST="redis-redis-sentinel-0.redis-redis-sentinel-headless.test.svc,\
          redis-redis-sentinel-1.redis-redis-sentinel-headless.test.svc,\
          redis-redis-sentinel-2.redis-redis-sentinel-headless.test.svc"
          REDIS_SENTINEL_USER="sentinel_user"
          REDIS_SENTINEL_PASSWORD="redis_sentinel_password"
          SENTINEL_PASSWORD="sentinel_password"
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
          KB_CLUSTER_NAME="redis"
      }
      Before 'setup'

      un_setup() {
        unset SENTINEL_POD_FQDN_LIST
        unset REDIS_SENTINEL_USER
        unset REDIS_SENTINEL_PASSWORD
        unset SENTINEL_PASSWORD
        unset REDIS_SENTINEL_PASSWORD_REDIS0
        unset REDIS_SENTINEL_PASSWORD_REDIS1
        unset KB_CLUSTER_NAME
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