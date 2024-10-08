# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_register_to_sentinel_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe 'register_to_sentinel.sh'

  # load the scripts to be tested and dependencies
  Include ../scripts/redis-register-to-sentinel.sh
  Include $common_library_file

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "parse_redis_advertised_svc_if_exist()"
    It "parses redis advertised service correctly when matching svc is found"
      export REDIS_ADVERTISED_PORT="redis-redis-redis-advertised-0:31000,redis-redis-redis-advertised-1:32000"
      export CURRENT_POD_HOST_IP="10.0.0.1"
      When call parse_redis_advertised_svc_if_exist "redis-redis-0"
      The variable redis_advertised_svc_port_value should eq "31000"
      The variable redis_advertised_svc_host_value should eq "10.0.0.1"
      The stdout should include "Found matching svcName and port for podName 'redis-redis-0'"
    End

    It "exits with error when no matching svc is found"
      export REDIS_ADVERTISED_PORT="redis-redis-redis-advertised-0:31000,redis-redis-redis-advertised-1:32000"
      export CURRENT_POD_HOST_IP="10.0.0.2"
      When run parse_redis_advertised_svc_if_exist "redis-redis-2"
      The status should be failure
      The stdout should include "Error: No matching svcName and port found for podName 'redis-redis-2'"
    End

    It "ignores parsing when REDIS_ADVERTISED_PORT env is not set"
      unset REDIS_ADVERTISED_PORT
      When call parse_redis_advertised_svc_if_exist "redis-redis-0"
      The status should be success
      The stdout should include "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    End
  End

  Describe 'register_to_sentinel_if_needed()'
    It 'should execute register_to_sentinel_wrapper if SENTINEL_COMPONENT_NAME exists'
      register_to_sentinel_wrapper() {
        echo "mocked register_to_sentinel_wrapper"
      }
      SENTINEL_COMPONENT_NAME=redis-sentinel
      When call register_to_sentinel_if_needed
      The output should include 'redis sentinel component found, register to redis sentinel.'
      The status should be success
    End

    It 'should exit 0 if SENTINEL_COMPONENT_NAME does not exist'
      unset SENTINEL_COMPONENT_NAME
      When call register_to_sentinel_if_needed
      The output should include 'redis sentinel component not found, skip register to sentinel.'
      The status should be success
    End
  End

  Describe 'register_to_sentinel_wrapper()'
    register_to_sentinel() {
      # shellcheck disable=SC2145
      echo "mocked register_to_sentinel $@"
    }

    It 'registers with headless service when REDIS_ADVERTISED_PORT is not set'
      SENTINEL_POD_FQDN_LIST="redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local,redis-redis-sentinel-1.redis-redis-sentinel-headless.default.svc.cluster.local"
      REDIS_POD_NAME_LIST='redis-redis-0,redis-redis-1'
      REDIS_POD_FQDN_LIST="redis-redis-0.redis-redis.default.svc.cluster.local,redis-redis-1.redis-redis.default.svc.cluster.local"
      REDIS_COMPONENT_NAME='redis-redis'

      When call register_to_sentinel_wrapper
      The status should be success
      The stdout should include "register to sentinel:redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local with pod fqdn: redis_default_primary_pod_fqdn=redis-redis-0.redis-redis.default.svc.cluster.local, redis_default_service_port=6379"
      The stdout should include "register to sentinel:redis-redis-sentinel-1.redis-redis-sentinel-headless.default.svc.cluster.local with pod fqdn: redis_default_primary_pod_fqdn=redis-redis-0.redis-redis.default.svc.cluster.local, redis_default_service_port=6379"
    End

    It 'registers with advertised service when REDIS_ADVERTISED_PORT is set'
      SENTINEL_POD_FQDN_LIST="redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local,redis-redis-sentinel-1.redis-redis-sentinel-headless.default.svc.cluster.local"
      REDIS_POD_NAME_LIST='redis-redis-0,redis-redis-1'
      REDIS_ADVERTISED_PORT="redis-redis-redis-advertised-0:31001,redis-redis-redis-advertised-1:32002"
      CURRENT_POD_HOST_IP='10.0.0.1'
      REDIS_COMPONENT_NAME='redis-redis'

      When call register_to_sentinel_wrapper
      The status should be success
      The stdout should include "register to sentinel:redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local with advertised service: redis_advertised_svc_host_value=10.0.0.1, redis_advertised_svc_port_value=31001"
      The stdout should include "register to sentinel:redis-redis-sentinel-1.redis-redis-sentinel-headless.default.svc.cluster.local with advertised service: redis_advertised_svc_host_value=10.0.0.1, redis_advertised_svc_port_value=31001"
    End

    It 'fails if required env vars SENTINEL_POD_FQDN_LIST are not set'
      REDIS_COMPONENT_NAME='redis-redis'
      REDIS_POD_NAME_LIST='redis-redis-0,redis-redis-1'
      unset SENTINEL_POD_FQDN_LIST
      When call register_to_sentinel_wrapper
      The status should be failure
      The stdout should include "Required environment variable SENTINEL_POD_FQDN_LIST is not set"
    End

    It 'fails if required env vars REDIS_COMPONENT_NAME and REDIS_POD_NAME_LIST are not set'
      unset REDIS_COMPONENT_NAME REDIS_POD_NAME_LIST
      When call register_to_sentinel_wrapper
      The stdout should include "Required environment variable REDIS_COMPONENT_NAME and REDIS_POD_NAME_LIST is not set"
      The status should be failure
    End
  End

  Describe 'construct_sentinel_sub_command()'
    It 'constructs the sentinel monitor sub command correctly'
      When call construct_sentinel_sub_command "monitor" "redis-redis" "redis-redis-0.redis-redis.default.svc.cluster.local" "6379"
      The status should be success
      The output should eq "SENTINEL monitor redis-redis redis-redis-0.redis-redis.default.svc.cluster.local 6379 2"
    End

    It 'constructs the sentinel down-after-milliseconds sub command correctly'
      When call construct_sentinel_sub_command "down-after-milliseconds" "redis-redis" "redis-redis-0.redis-redis.default.svc.cluster.local" "6379"
      The status should be success
      The output should eq "SENTINEL set redis-redis down-after-milliseconds 5000"
    End

    It 'constructs the sentinel failover-timeout sub command correctly'
      When call construct_sentinel_sub_command "failover-timeout" "redis-redis" "redis-redis-0.redis-redis.default.svc.cluster.local" "6379"
      The status should be success
      The output should eq "SENTINEL set redis-redis failover-timeout 60000"
    End

    It 'constructs the sentinel parallel-syncs sub command correctly'
      When call construct_sentinel_sub_command "parallel-syncs" "redis-redis" "redis-redis-0.redis-redis.default.svc.cluster.local" "6379"
      The status should be success
      The output should eq "SENTINEL set redis-redis parallel-syncs 1"
    End

    It 'constructs the sentinel auth-user sub command correctly'
      REDIS_SENTINEL_USER="default"
      When call construct_sentinel_sub_command "auth-user" "redis-redis" "redis-redis-0.redis-redis.default.svc.cluster.local" "6379"
      The status should be success
      The output should eq "SENTINEL set redis-redis auth-user $REDIS_SENTINEL_USER"
    End

    It 'constructs the sentinel auth-pass sub command correctly'
      REDIS_SENTINEL_PASSWORD="sentinel_password"
      When call construct_sentinel_sub_command "auth-pass" "redis-redis" "redis-redis-0.redis-redis.default.svc.cluster.local" "6379"
      The status should be success
      The output should eq "SENTINEL set redis-redis auth-pass $REDIS_SENTINEL_PASSWORD"
    End
  End

  Describe 'register_to_sentinel()'
    It 'registers the redis primary to sentinel'
      sentinel_host="redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local"
      sentinel_port="26379"
      master_name="redis-redis"
      redis_primary_host="redis-redis-0.redis-redis.default.svc.cluster.local"
      redis_primary_port="6379"
      REDIS_SENTINEL_PASSWORD="sentinel_password"

      check_connectivity() {
        echo "Checking connectivity to $1 on port $2 with password $REDIS_SENTINEL_PASSWORD using redis-cli..."
        return 0
      }

      execute_sentinel_sub_command() {
        echo "host:$1, port:$2 Command:$3 executed successfully."
        return 0
      }

      get_master_addr_by_name(){
        output=""
        echo "$output"
        return 0
      }

      When call register_to_sentinel $sentinel_host $master_name $redis_primary_host $redis_primary_port
      The status should be success
      The output should include "host:redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local, port:26379 Command:SENTINEL monitor redis-redis redis-redis-0.redis-redis.default.svc.cluster.local 6379 2"
      The output should include "host:redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local, port:26379 Command:SENTINEL set redis-redis down-after-milliseconds 5000 executed successfully."
      The output should include "host:redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local, port:26379 Command:SENTINEL set redis-redis failover-timeout 60000"
      The output should include "host:redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local, port:26379 Command:SENTINEL set redis-redis parallel-syncs 1"
      The output should include "host:redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local, port:26379 Command:SENTINEL set redis-redis auth-user"
      The output should include "host:redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local, port:26379 Command:SENTINEL set redis-redis auth-pass sentinel_password"
      The output should include "redis sentinel register to redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local succeeded!"
    End

#    It 'fails when connectivity to sentinel host fails'
#      sentinel_host="redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local"
#      sentinel_port="26379"
#      master_name="redis-redis"
#      redis_primary_host="redis-redis-0.redis-redis.default.svc.cluster.local"
#      redis_primary_port="6379"
#
#      check_connectivity() {
#        echo "Checking connectivity to $1 on port $2 with password $REDIS_SENTINEL_PASSWORD using redis-cli..."
#        return 1
#      }
#
#      When call register_to_sentinel
#      The status should be failure
#      The output should include "Error: redis-redis-sentinel-0.redis-redis-sentinel-headless.default.svc.cluster.local is not reachable on port 26379."
#    End
  End
End