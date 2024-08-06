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
        The stdout should eq "build default accounts succeeded!"
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
        The stdout should eq "build default accounts succeeded!"
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
        The stdout should eq "build default accounts succeeded!"
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
      The stdout should eq "redis use nodeport $redis_advertised_svc_host_value:$redis_advertised_svc_port_value to announce"
    End

    It "builds announce ip and port correctly when advertised svc is not enabled"
      unset redis_advertised_svc_host_value
      unset redis_advertised_svc_port_value
      KB_POD_NAME="redis-redis-0"
      KB_CLUSTER_COMP_NAME="redis-redis"
      KB_NAMESPACE="default"
      When call build_announce_ip_and_port
      The contents of file "./redis.conf" should include "replica-announce-ip $KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
      The stdout should eq "redis use kb pod fqdn $KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc to announce"
    End
  End
End