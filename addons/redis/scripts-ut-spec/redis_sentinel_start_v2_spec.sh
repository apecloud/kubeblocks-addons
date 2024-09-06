# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_sentinel_start_v2_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Start Sentinel Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/redis-sentinel-start-v2.sh
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
End