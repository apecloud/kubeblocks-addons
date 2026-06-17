# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis5_sentinel_start_v2_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis5 Sentinel Start V2 Script Tests"
  Include ../scripts/redis5-sentinel-start-v2.sh
  Include $common_library_file

  init() {
    redis_sentinel_conf_dir="."
    redis_sentinel_real_conf="./redis_sentinel.conf"
    redis_sentinel_real_conf_bak="./redis_sentinel.conf.bak"
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f ./redis_sentinel.conf
    rm -f ./redis_sentinel.conf.bak
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "extract_lb_host_by_svc_name()"
    It "extracts LB host for matching sentinel svc"
      export REDIS_SENTINEL_LB_ADVERTISED_HOST="sentinel-0:10.0.0.1,sentinel-1:10.0.0.2"
      When call extract_lb_host_by_svc_name "sentinel-0"
      The output should eq "10.0.0.1"
    End

    It "returns empty when no match"
      export REDIS_SENTINEL_LB_ADVERTISED_HOST="sentinel-0:10.0.0.1"
      When call extract_lb_host_by_svc_name "sentinel-5"
      The output should eq ""
    End
  End

  Describe "parse_redis_sentinel_announce_addr()"
    It "parses advertised port with matching ordinal"
      export REDIS_SENTINEL_ADVERTISED_PORT="sentinel-advertised-0:31000,sentinel-advertised-1:32000"
      export CURRENT_POD_HOST_IP="10.0.0.1"
      When call parse_redis_sentinel_announce_addr "redis-sentinel-0"
      The variable redis_sentinel_announce_port_value should eq "31000"
      The variable redis_sentinel_announce_host_value should eq "10.0.0.1"
      The stdout should include "Found matching svcName and port for podName 'redis-sentinel-0'"
    End

    It "exits with error when no matching ordinal"
      export REDIS_SENTINEL_ADVERTISED_PORT="sentinel-advertised-0:31000"
      When run parse_redis_sentinel_announce_addr "redis-sentinel-5"
      The status should be failure
      The stdout should include "Error: No matching svcName and port found for podName 'redis-sentinel-5'"
    End

    It "ignores when advertised port is not set"
      unset REDIS_SENTINEL_ADVERTISED_PORT
      unset REDIS_SENTINEL_LB_ADVERTISED_PORT
      When call parse_redis_sentinel_announce_addr "redis-sentinel-0"
      The status should be success
      The stdout should include "Environment variable REDIS_SENTINEL_ADVERTISED_PORT not found. Ignoring."
    End

    It "uses host network port when available"
      unset REDIS_SENTINEL_ADVERTISED_PORT
      unset REDIS_SENTINEL_LB_ADVERTISED_PORT
      export REDIS_SENTINEL_HOST_NETWORK_PORT="26380"
      export CURRENT_POD_HOST_IP="192.168.1.100"
      When call parse_redis_sentinel_announce_addr "redis-sentinel-0"
      The status should be success
      The variable redis_sentinel_announce_port_value should eq "26380"
      The variable redis_sentinel_announce_host_value should eq "192.168.1.100"
      The stdout should include "redis sentinel is in host network mode"
    End

    It "uses LB host when available"
      export REDIS_SENTINEL_ADVERTISED_PORT="sentinel-advertised-0:31000"
      export REDIS_SENTINEL_LB_ADVERTISED_HOST="sentinel-advertised-0:lb.example.com"
      export CURRENT_POD_HOST_IP="10.0.0.1"
      When call parse_redis_sentinel_announce_addr "redis-sentinel-0"
      The variable redis_sentinel_announce_host_value should eq "lb.example.com"
      The variable redis_sentinel_announce_port_value should eq "26379"
      The stdout should include "Found load balancer host"
    End

    It "falls back to LB advertised port"
      unset REDIS_SENTINEL_ADVERTISED_PORT
      export REDIS_SENTINEL_LB_ADVERTISED_PORT="sentinel-advertised-0:31000"
      export CURRENT_POD_HOST_IP="10.0.0.1"
      When call parse_redis_sentinel_announce_addr "redis-sentinel-0"
      The variable redis_sentinel_announce_port_value should eq "31000"
      The stdout should include "Found matching svcName and port for podName 'redis-sentinel-0'"
    End
  End

  Describe "reset_redis_sentinel_conf()"
    Context "when conf file exists with announce lines"
      setup() {
        mkdir -p "$(dirname "$redis_sentinel_real_conf")"
        {
          echo "port 26379"
          echo "sentinel announce-ip 10.0.0.1"
          echo "sentinel announce-port 26379"
          echo "requirepass oldpass"
          echo "sentinel monitor mymaster 10.0.0.1 6379 2"
        } > $redis_sentinel_real_conf
        export SENTINEL_PASSWORD="newpass"
      }
      Before 'setup'

      un_setup() {
        unset SENTINEL_PASSWORD
      }
      After 'un_setup'

      It "removes announce-ip, announce-port, requirepass, and port lines"
        When call reset_redis_sentinel_conf
        The status should be success
        The stdout should include "reset redis sentinel conf"
        The contents of file "$redis_sentinel_real_conf" should not include "sentinel announce-ip"
        The contents of file "$redis_sentinel_real_conf" should not include "sentinel announce-port"
        The contents of file "$redis_sentinel_real_conf" should not include "requirepass"
        The contents of file "$redis_sentinel_real_conf" should not include "port 26379"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel monitor mymaster"
      End
    End

    Context "when conf file does not exist"
      setup() {
        rm -f $redis_sentinel_real_conf
        rm -f $redis_sentinel_real_conf_bak
        unset SENTINEL_PASSWORD
      }
      Before 'setup'

      It "creates the directory"
        When call reset_redis_sentinel_conf
        The status should be success
        The stdout should include "reset redis sentinel conf"
      End
    End

    Context "when using custom sentinel port"
      setup() {
        mkdir -p "$(dirname "$redis_sentinel_real_conf")"
        {
          echo "port 36379"
          echo "sentinel monitor mymaster 10.0.0.1 6379 2"
        } > $redis_sentinel_real_conf
        export SENTINEL_SERVICE_PORT="36379"
        unset SENTINEL_PASSWORD
      }
      Before 'setup'

      un_setup() {
        unset SENTINEL_SERVICE_PORT
      }
      After 'un_setup'

      It "removes the custom port line"
        When call reset_redis_sentinel_conf
        The status should be success
        The stdout should include "reset redis sentinel conf"
        The contents of file "$redis_sentinel_real_conf" should not include "port 36379"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel monitor mymaster"
      End
    End
  End

  Describe "build_redis_sentinel_conf()"
    Context "when announce host and port are set"
      setup() {
        echo "" > $redis_sentinel_real_conf
        sentinel_port="26379"
        redis_sentinel_announce_host_value="172.0.0.1"
        redis_sentinel_announce_port_value="31000"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.headless,sentinel-1.headless"
        export SENTINEL_PASSWORD="sentpass"
      }
      Before 'setup'

      un_setup() {
        unset redis_sentinel_announce_host_value
        unset redis_sentinel_announce_port_value
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_PASSWORD
      }
      After 'un_setup'

      It "uses nodeport announce with requirepass (Redis 5 style, no sentinel-user/sentinel-pass)"
        When call build_redis_sentinel_conf
        The status should be success
        The stdout should include "build redis sentinel conf succeeded!"
        The contents of file "$redis_sentinel_real_conf" should include "port 26379"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel announce-ip 172.0.0.1"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel announce-port 31000"
        The contents of file "$redis_sentinel_real_conf" should include "requirepass sentpass"
        The contents of file "$redis_sentinel_real_conf" should not include "sentinel sentinel-user"
        The contents of file "$redis_sentinel_real_conf" should not include "sentinel sentinel-pass"
        The contents of file "$redis_sentinel_real_conf" should not include "resolve-hostnames"
        The contents of file "$redis_sentinel_real_conf" should not include "announce-hostnames"
      End
    End

    Context "when using pod IP (no advertise)"
      setup() {
        echo "" > $redis_sentinel_real_conf
        sentinel_port="26379"
        unset redis_sentinel_announce_host_value
        unset redis_sentinel_announce_port_value
        export CURRENT_POD_IP="10.42.0.5"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.headless"
        unset SENTINEL_PASSWORD
        unset FIXED_POD_IP_ENABLED
      }
      Before 'setup'

      un_setup() {
        unset CURRENT_POD_IP
        unset SENTINEL_POD_FQDN_LIST
      }
      After 'un_setup'

      It "uses pod IP for announce (Redis 5 no hostname support)"
        When call build_redis_sentinel_conf
        The status should be success
        The stdout should include "build redis sentinel conf succeeded!"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel announce-ip 10.42.0.5"
        The contents of file "$redis_sentinel_real_conf" should include "sentinel announce-port 26379"
        The contents of file "$redis_sentinel_real_conf" should not include "requirepass"
      End
    End

    Context "when fixed pod IP is enabled"
      setup() {
        echo "" > $redis_sentinel_real_conf
        sentinel_port="26379"
        unset redis_sentinel_announce_host_value
        unset redis_sentinel_announce_port_value
        export FIXED_POD_IP_ENABLED="true"
        export CURRENT_POD_IP="10.42.0.7"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.headless"
        unset SENTINEL_PASSWORD
      }
      Before 'setup'

      un_setup() {
        unset FIXED_POD_IP_ENABLED
        unset CURRENT_POD_IP
        unset SENTINEL_POD_FQDN_LIST
      }
      After 'un_setup'

      It "uses fixed pod IP for announce"
        When call build_redis_sentinel_conf
        The status should be success
        The contents of file "$redis_sentinel_real_conf" should include "sentinel announce-ip 10.42.0.7"
        The stdout should include "redis sentinel use the fixed pod ip"
      End
    End

    Context "when SENTINEL_POD_FQDN_LIST is not set"
      setup() {
        echo "" > $redis_sentinel_real_conf
        sentinel_port="26379"
        unset SENTINEL_POD_FQDN_LIST
      }
      Before 'setup'

      It "exits with error"
        When run build_redis_sentinel_conf
        The status should be failure
        The stdout should include "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set."
      End
    End
  End
End
