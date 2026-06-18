# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154
# shellcheck disable=SC2168

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_twemproxy_setup_v2_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis Twemproxy Setup V2 Script Tests"
  Include ../scripts/redis-twemproxy-setup-v2.sh

  init() {
    ut_mode="true"
    TWEMPROXY_CONF_DIR=$(mktemp -d)
    export TWEMPROXY_CONF_PATH="$TWEMPROXY_CONF_DIR/nutcracker.conf"
  }

  cleanup() {
    rm -rf "$TWEMPROXY_CONF_DIR"
  }

  BeforeAll "init"
  AfterAll "cleanup"

  reset_env() {
    unset REDIS_SERVICE_NAMES
    unset REDIS_SERVICE_PORTS
    unset REDIS_DEFAULT_PASSWORD
    for var in $(env | grep -oE '^REDIS_DEFAULT_PASSWORD_[^=]*' 2>/dev/null); do
      unset "$var"
    done
  }

  build_and_show_config() {
    build_redis_twemproxy_conf
    echo "---CONFIG_START---"
    cat "$TWEMPROXY_CONF_PATH"
    echo ""
    echo "---CONFIG_END---"
  }

  Describe "convert_to_array()"
    It "returns single value unchanged"
      When call convert_to_array "hello"
      The output should equal "hello"
    End

    It "splits comma-separated values into space-separated words"
      When call convert_to_array "a,b,c"
      The output should equal "a b c"
    End

    It "handles key:value format"
      When call convert_to_array "redis0:redis-redis0-redis"
      The output should equal "redis0:redis-redis0-redis"
    End

    It "splits multiple key:value pairs"
      When call convert_to_array "redis0:redis-redis0-redis,redis1:redis-redis1-redis"
      The output should equal "redis0:redis-redis0-redis redis1:redis-redis1-redis"
    End

    It "handles empty input"
      When call convert_to_array ""
      The output should equal ""
    End
  End

  Describe "build_redis_twemproxy_conf()"
    Context "when REDIS_SERVICE_NAMES is empty"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES=""
        export REDIS_SERVICE_PORTS="6379"
      }
      Before "setup"

      It "exits with failure"
        When run build_redis_twemproxy_conf
        The status should be failure
        The stdout should include "REDIS_SERVICE_NAMES and REDIS_SERVICE_PORTS must be set"
        The stderr should be defined
      End
    End

    Context "when REDIS_SERVICE_PORTS is empty"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES="redis-redis0-redis"
        export REDIS_SERVICE_PORTS=""
      }
      Before "setup"

      It "exits with failure"
        When run build_redis_twemproxy_conf
        The status should be failure
        The stdout should include "REDIS_SERVICE_NAMES and REDIS_SERVICE_PORTS must be set"
        The stderr should be defined
      End
    End

    Context "when both service env vars are empty"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES=""
        export REDIS_SERVICE_PORTS=""
      }
      Before "setup"

      It "exits with failure"
        When run build_redis_twemproxy_conf
        The status should be failure
        The stdout should include "REDIS_SERVICE_NAMES and REDIS_SERVICE_PORTS must be set"
        The stderr should be defined
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is not set"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES="redis-redis0-redis"
        export REDIS_SERVICE_PORTS="6379"
      }
      Before "setup"

      It "exits with failure"
        When run build_redis_twemproxy_conf
        The status should be failure
        The stdout should include "No environment variable starting with REDIS_DEFAULT_PASSWORD found"
        The stderr should be defined
      End
    End

    Context "with conflicting REDIS_DEFAULT_PASSWORD values"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES="redis0:redis-redis0-redis,redis1:redis-redis1-redis"
        export REDIS_SERVICE_PORTS="redis0:6379,redis1:6379"
        export REDIS_DEFAULT_PASSWORD_redis0="password1"
        export REDIS_DEFAULT_PASSWORD_redis1="password2"
      }
      Before "setup"

      It "exits with failure"
        When run build_redis_twemproxy_conf
        The status should be failure
        The stdout should include "Error conflicting env"
        The stdout should include "all the components' password of redis server must be the same"
        The stderr should be defined
      End
    End

    Context "with single shard format"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES="redis-redis0-redis"
        export REDIS_SERVICE_PORTS="6379"
        export REDIS_DEFAULT_PASSWORD="testpassword123"
      }
      Before "setup"

      It "generates config successfully"
        When run build_and_show_config
        The status should be success
        The stdout should include "build redis twemproxy conf done!"
        The stdout should include "redis_auth: testpassword123"
        The stdout should include "- redis-redis0-redis:6379:1"
        The stdout should include "listen: 0.0.0.0:22121"
        The stdout should include "hash: fnv1a_64"
        The stdout should include "distribution: ketama"
        The stderr should be defined
      End
    End

    Context "with single shard key:value format"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES="redis0:redis-redis0-redis"
        export REDIS_SERVICE_PORTS="redis0:6379"
        export REDIS_DEFAULT_PASSWORD="singleshardpw"
      }
      Before "setup"

      It "strips key prefix for single shard"
        When run build_and_show_config
        The status should be success
        The stdout should include "build redis twemproxy conf done!"
        The stdout should include "- redis-redis0-redis:6379:1"
        The stdout should include "redis_auth: singleshardpw"
        The stderr should be defined
      End
    End

    Context "with multiple shards"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES="redis0:redis-redis0-redis,redis1:redis-redis1-redis"
        export REDIS_SERVICE_PORTS="redis0:6379,redis1:6379"
        export REDIS_DEFAULT_PASSWORD="multishardpw"
      }
      Before "setup"

      It "generates config with all shard servers"
        When run build_and_show_config
        The status should be success
        The stdout should include "build redis twemproxy conf done!"
        The stdout should include "- redis-redis0-redis:6379:1"
        The stdout should include "- redis-redis1-redis:6379:1"
        The stdout should include "redis_auth: multishardpw"
        The stderr should be defined
      End
    End

    Context "with three shards and different ports"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES="shard0:redis-shard0-redis,shard1:redis-shard1-redis,shard2:redis-shard2-redis"
        export REDIS_SERVICE_PORTS="shard0:6379,shard1:6380,shard2:6381"
        export REDIS_DEFAULT_PASSWORD="threeshardpw"
      }
      Before "setup"

      It "matches each shard name with its port"
        When run build_and_show_config
        The status should be success
        The stdout should include "- redis-shard0-redis:6379:1"
        The stdout should include "- redis-shard1-redis:6380:1"
        The stdout should include "- redis-shard2-redis:6381:1"
        The stderr should be defined
      End
    End

    Context "with consistent multi-component passwords"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES="redis-redis0-redis"
        export REDIS_SERVICE_PORTS="6379"
        export REDIS_DEFAULT_PASSWORD_redis0="samepw"
        export REDIS_DEFAULT_PASSWORD_redis1="samepw"
      }
      Before "setup"

      It "accepts matching passwords"
        When run build_redis_twemproxy_conf
        The status should be success
        The stdout should include "build redis twemproxy conf done!"
        The stderr should be defined
      End
    End

    Context "with unmatched shard keys between names and ports"
      setup() {
        reset_env
        export REDIS_SERVICE_NAMES="redis0:redis-redis0-redis,redis1:redis-redis1-redis"
        export REDIS_SERVICE_PORTS="redis0:6379,redis2:6380"
        export REDIS_DEFAULT_PASSWORD="mismatchpw"
      }
      Before "setup"

      It "only includes servers where keys match"
        When run build_and_show_config
        The status should be success
        The stdout should include "- redis-redis0-redis:6379:1"
        The stdout should not include "- redis-redis1-redis"
        The stderr should be defined
      End
    End
  End
End
