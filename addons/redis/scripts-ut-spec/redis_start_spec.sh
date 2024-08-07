#shellcheck shell=bash

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Start Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/redis-start.sh
  Include $common_library_file

  init() {
    # override name of redis related file defined in redis-start.sh because default conf /etc/redis/redis.conf does not exist
    redis_real_conf="./redis.conf"
    redis_acl_file="./users.acl"
    # set ut_mode to true to hack control flow in the script
    # shellcheck disable=SC2034
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f ./redis.conf;
    rm -f ./users.acl;
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "extract_ordinal_from_object_name()"
    It "extracts ordinal from object name correctly"
      When call extract_ordinal_from_object_name "pod-name-2"
      The status should be success
      The stdout should eq "2"
      The stderr should eq ""
    End

    It "extracts ordinal from object name with different format"
      When call extract_ordinal_from_object_name "3"
      The stdout should eq "3"
      The stderr should eq ""
    End
  End

  Describe "load_redis_template_conf()"
    It "appends include directive to redis.conf"
      When call load_redis_template_conf
      The contents of file "$redis_real_conf" should include "include /etc/conf/redis.conf"
    End
  End

  Describe "build_redis_default_accounts()"
    Context 'when all environment variables exist'
      setup() {
        echo "" > $redis_real_conf
        echo "" > $redis_acl_file
        REDIS_REPL_PASSWORD="repl_password"
        REDIS_SENTINEL_PASSWORD="sentinel_password"
        REDIS_DEFAULT_PASSWORD="default_password"
      }
      Before 'setup'

      un_setup() {
        unset REDIS_REPL_PASSWORD
        unset REDIS_SENTINEL_PASSWORD
        unset REDIS_DEFAULT_PASSWORD
      }
      After 'un_setup'

      It "builds default accounts correctly when all password envs are set"
        When call build_redis_default_accounts
        The status should be success
        The stdout should include "build default accounts succeeded!"
        The contents of file "$redis_real_conf" should include "masteruser $REDIS_REPL_USER"
        The contents of file "$redis_real_conf" should include "masterauth $REDIS_REPL_PASSWORD"
        The contents of file "$redis_real_conf" should include "protected-mode yes"
        The contents of file "$redis_real_conf" should include "aclfile /data/users.acl"
        The contents of file "$redis_acl_file" should include "user $REDIS_REPL_USER on +psync +replconf +ping >$REDIS_REPL_PASSWORD"
        The contents of file "$redis_acl_file" should include "user $REDIS_SENTINEL_USER on allchannels +multi +slaveof +ping +exec +subscribe +config|rewrite +role +publish +info +client|setname +client|kill +script|kill >$REDIS_SENTINEL_PASSWORD"
        The contents of file "$redis_acl_file" should include "user default on >$REDIS_DEFAULT_PASSWORD ~* &* +@all"
      End
    End

    Context 'when default password environment variables exist'
      setup() {
        echo "" > $redis_real_conf
        echo "" > $redis_acl_file
        REDIS_DEFAULT_PASSWORD="default_password"
      }
      Before 'setup'

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After 'un_setup'

      It "builds default accounts correctly when only default password env is set"
        When call build_redis_default_accounts
        The status should be success
        The stdout should include "build default accounts succeeded!"
        The contents of file "$redis_real_conf" should include "protected-mode yes"
        The contents of file "$redis_real_conf" should include "aclfile /data/users.acl"
        The contents of file "$redis_acl_file" should include "user default on >$REDIS_DEFAULT_PASSWORD ~* &* +@all"
      End
    End

    Context 'when all environment variables are not exist'
      setup() {
        echo "" > $redis_real_conf
        echo "" > $redis_acl_file
      }
      Before 'setup'

      It "disables protected mode when no password env is set"
        When call build_redis_default_accounts
        The status should be success
        The stdout should include "build default accounts succeeded!"
        The contents of file "$redis_real_conf" should include "protected-mode no"
      End
    End
  End

  Describe "build_announce_ip_and_port()"
    It "builds announce ip and port correctly when advertised svc is enabled"
      redis_advertised_svc_host_value="10.0.0.1"
      redis_advertised_svc_port_value="31000"
      When call build_announce_ip_and_port
      The contents of file "$redis_real_conf" should include "replica-announce-port $redis_advertised_svc_port_value"
      The contents of file "$redis_real_conf" should include "replica-announce-ip $redis_advertised_svc_host_value"
      The stdout should include "redis use nodeport $redis_advertised_svc_host_value:$redis_advertised_svc_port_value to announce"
    End

    It "builds announce ip and port correctly when advertised svc is not enabled"
      unset redis_advertised_svc_host_value
      unset redis_advertised_svc_port_value
      KB_POD_NAME="redis-redis-0"
      KB_CLUSTER_COMP_NAME="redis-redis"
      KB_NAMESPACE="default"
      When call build_announce_ip_and_port
      The contents of file "./redis.conf" should include "replica-announce-ip $KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
      The stdout should include "redis use kb pod fqdn $KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc to announce"
    End
  End

  Describe "build_redis_service_port()"
    It "builds redis service port correctly when SERVICE_PORT env is set"
      SERVICE_PORT="6380"
      When call build_redis_service_port
      The contents of file "$redis_real_conf" should include "port $SERVICE_PORT"
    End

    It "builds redis service port with default value when SERVICE_PORT env is not set"
      unset SERVICE_PORT
      When call build_redis_service_port
      The contents of file "$redis_real_conf" should include "port 6379"
      The stdout should include "false, SERVICE_PORT does not exist"
    End
  End

  Describe "parse_redis_advertised_svc_if_exist()"
    It "parses redis advertised service correctly when matching svc is found"
      REDIS_ADVERTISED_PORT="redis-redis-redis-advertised-0:31000,redis-redis-redis-advertised-1:32000"
      KB_HOST_IP="10.0.0.1"
      When call parse_redis_advertised_svc_if_exist "redis-redis-0"
      The variable redis_advertised_svc_port_value should eq "31000"
      The variable redis_advertised_svc_host_value should eq "10.0.0.1"
      The stdout should include "Found matching svcName and port for podName 'redis-redis-0'"
    End

    It "exits with error when no matching svc is found"
      # shellcheck disable=SC2034
      REDIS_ADVERTISED_PORT="redis-redis-redis-advertised-0:31000,redis-redis-redis-advertised-1:32000"
      # shellcheck disable=SC2034
      KB_HOST_IP="10.0.0.2"
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

  Describe "check_current_pod_is_primary()"
    Context 'mapping with pod name'
      un_setup() {
        unset KB_POD_NAME
        unset KB_CLUSTER_COMP_NAME
        unset primary
      }
      After 'un_setup'

      It "returns true when current pod name matches the primary"
        KB_POD_NAME="redis-redis-0"
        KB_CLUSTER_COMP_NAME="redis-redis"
        primary="redis-redis-0.redis-redis-headless.default"
        When call check_current_pod_is_primary
        The status should be success
        The stdout should include "current pod is primary with name mapping"
      End

      It "returns false when current pod does not match the primary"
        KB_POD_NAME="redis-redis-10"
        KB_CLUSTER_COMP_NAME="redis-redis"
        primary="redis-redis-0.redis-redis-headless.default"
        When call check_current_pod_is_primary
        The status should be failure
      End

      It "returns false when current pod does not match the primary"
        KB_POD_NAME="redis-redis-1"
        KB_CLUSTER_COMP_NAME="redis-redis"
        # shellcheck disable=SC2034
        primary="redis-redis-0.redis-redis-headless.default"
        When call check_current_pod_is_primary
        The status should be failure
      End
    End

    Context 'mapping with pod ip and service port'
      setup() {
        KB_POD_NAME="redis-redis-0"
        # shellcheck disable=SC2034
        KB_POD_IP="10.0.0.1"
        # shellcheck disable=SC2034
        service_port="6379"
        # shellcheck disable=SC2034
        primary="10.0.0.1"
        # shellcheck disable=SC2034
        primary_port="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_POD_IP
        unset KB_POD_NAME
        unset service_port
        unset primary
        unset primary_port
      }
      After 'un_setup'

      It "returns true when current pod IP and service port matches the primary"
        When call check_current_pod_is_primary
        The status should be success
        The stdout should include "current pod is primary with pod ip mapping"
      End
    End

    Context 'mapping with advertised svc host and port'
      setup() {
        KB_POD_NAME="redis-redis-0"
        # shellcheck disable=SC2034
        KB_POD_IP="10.0.0.1"
        # shellcheck disable=SC2034
        service_port="6379"
        redis_advertised_svc_host_value="172.0.0.1"
        redis_advertised_svc_port_value="31000"
      }
      Before "setup"

      un_setup() {
        unset KB_POD_IP
        unset service_port
        unset primary
        unset primary_port
      }
      After 'un_setup'

      It "returns false when current redis_advertised_svc_host_value and redis_advertised_svc_port_value exist but not match"
        # shellcheck disable=SC2034
        primary="172.0.0.1"
        # shellcheck disable=SC2034
        primary_port="32000"
        When call check_current_pod_is_primary
        The status should be failure
        The stdout should include "redis advertised svc host and port exist but not match"
      End

      It "returns true when current redis_advertised_svc_host_value and redis_advertised_svc_port_value matches the primary"
        # shellcheck disable=SC2034
        primary="172.0.0.1"
        # shellcheck disable=SC2034
        primary_port="31000"
        When call check_current_pod_is_primary
        The status should be success
        The stdout should include "current pod is primary with advertised svc mapping"
      End
    End
  End
End