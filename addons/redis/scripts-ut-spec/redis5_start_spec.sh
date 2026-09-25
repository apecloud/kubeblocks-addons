# shellcheck shell=bash
# shellcheck disable=SC2034

should_skip_when_shell_type_and_version_invalid() {
  if validate_shell_type_and_version "bash" 4 &>/dev/null; then
    return 1
  fi
  echo "redis5_start_spec.sh skip case because dependency bash version 4 or higher is not installed."
  return 0
}

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis5 Start Bash Script Tests"
  Include ../scripts/redis5-start.sh
  Include $common_library_file

  init() {
    redis_real_conf="./redis.conf"
    redis_acl_file="./users.acl"
    redis_acl_file_bak="./users.acl.bak"
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $redis_real_conf
    rm -f $redis_acl_file
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "build_redis_default_accounts()"
    Context "when REDIS_DEFAULT_PASSWORD is set"
      setup() {
        echo "" > $redis_real_conf
        export REDIS_DEFAULT_PASSWORD="mypass123"
      }
      Before 'setup'

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After 'un_setup'

      It "uses requirepass and masterauth (Redis 5 style, no ACL)"
        When call build_redis_default_accounts
        The status should be success
        The stdout should include "build default accounts succeeded!"
        The contents of file "$redis_real_conf" should include "protected-mode yes"
        The contents of file "$redis_real_conf" should include "requirepass mypass123"
        The contents of file "$redis_real_conf" should include "masterauth mypass123"
        The contents of file "$redis_real_conf" should not include "aclfile"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is not set"
      setup() {
        echo "" > $redis_real_conf
        unset REDIS_DEFAULT_PASSWORD
      }
      Before 'setup'

      It "disables protected mode"
        When call build_redis_default_accounts
        The status should be success
        The stdout should include "build default accounts succeeded!"
        The contents of file "$redis_real_conf" should include "protected-mode no"
        The contents of file "$redis_real_conf" should not include "requirepass"
        The contents of file "$redis_real_conf" should not include "masterauth"
      End
    End
  End

  Describe "build_announce_ip_and_port()"
    Context "when advertised svc host and port are set"
      setup() {
        echo "" > $redis_real_conf
        redis_announce_host_value="172.0.0.1"
        redis_announce_port_value="31000"
      }
      Before 'setup'

      un_setup() {
        unset redis_announce_host_value
        unset redis_announce_port_value
      }
      After 'un_setup'

      It "uses nodeport announce"
        When call build_announce_ip_and_port
        The contents of file "$redis_real_conf" should include "replica-announce-port 31000"
        The contents of file "$redis_real_conf" should include "replica-announce-ip 172.0.0.1"
        The stdout should include "redis use nodeport 172.0.0.1:31000 to announce"
      End
    End

    Context "when fixed pod IP is enabled"
      setup() {
        echo "" > $redis_real_conf
        unset redis_announce_host_value
        unset redis_announce_port_value
        export FIXED_POD_IP_ENABLED="true"
        export CURRENT_POD_IP="10.42.0.5"
      }
      Before 'setup'

      un_setup() {
        unset FIXED_POD_IP_ENABLED
        unset CURRENT_POD_IP
        rm -f /data/.fixed_pod_ip_enabled 2>/dev/null
      }
      After 'un_setup'

      It "uses fixed pod IP for announce"
        When call build_announce_ip_and_port
        The contents of file "$redis_real_conf" should include "replica-announce-ip 10.42.0.5"
        The stdout should include "redis use immutable pod ip 10.42.0.5 to announce"
        The stderr should be defined
      End
    End

    Context "when no advertise and no fixed IP (Redis 5 uses pod IP, not fqdn)"
      setup() {
        echo "" > $redis_real_conf
        unset redis_announce_host_value
        unset redis_announce_port_value
        unset FIXED_POD_IP_ENABLED
        export CURRENT_POD_IP="10.42.0.6"
      }
      Before 'setup'

      un_setup() {
        unset CURRENT_POD_IP
      }
      After 'un_setup'

      It "uses pod IP for announce (Redis 5 sentinel does not support hostnames)"
        When call build_announce_ip_and_port
        The contents of file "$redis_real_conf" should include "replica-announce-ip 10.42.0.6"
        The stdout should include "redis use kb pod fqdn"
      End
    End
  End

  Describe "build_redis_service_port()"
    Context "when SERVICE_PORT env is set"
      setup() {
        echo "" > $redis_real_conf
        export SERVICE_PORT="6380"
      }
      Before 'setup'

      un_setup() {
        unset SERVICE_PORT
      }
      After 'un_setup'

      It "uses the custom port"
        When call build_redis_service_port
        The contents of file "$redis_real_conf" should include "port 6380"
      End
    End

    Context "when SERVICE_PORT env is not set"
      setup() {
        echo "" > $redis_real_conf
        unset SERVICE_PORT
      }
      Before 'setup'

      It "defaults to port 6379"
        When call build_redis_service_port
        The contents of file "$redis_real_conf" should include "port 6379"
        The stdout should be defined
      End
    End
  End

  Describe "extract_lb_host_by_svc_name()"
    It "extracts LB host for matching svc name"
      export REDIS_LB_ADVERTISED_HOST="redis-0:10.0.0.1,redis-1:10.0.0.2"
      When call extract_lb_host_by_svc_name "redis-0"
      The output should eq "10.0.0.1"
    End

    It "extracts LB host for second svc"
      export REDIS_LB_ADVERTISED_HOST="redis-0:10.0.0.1,redis-1:10.0.0.2"
      When call extract_lb_host_by_svc_name "redis-1"
      The output should eq "10.0.0.2"
    End

    It "returns empty when no match"
      export REDIS_LB_ADVERTISED_HOST="redis-0:10.0.0.1,redis-1:10.0.0.2"
      When call extract_lb_host_by_svc_name "redis-2"
      The output should eq ""
    End
  End

  Describe "parse_redis_announce_addr()"
    It "parses advertised port with matching pod ordinal"
      export REDIS_ADVERTISED_PORT="redis-redis-advertised-0:31000,redis-redis-advertised-1:32000"
      export CURRENT_POD_HOST_IP="10.0.0.1"
      When call parse_redis_announce_addr "redis-redis-0"
      The variable redis_announce_port_value should eq "31000"
      The variable redis_announce_host_value should eq "10.0.0.1"
      The stdout should include "Found matching svcName and port for podName 'redis-redis-0'"
    End

    It "exits with error when no matching pod ordinal"
      export REDIS_ADVERTISED_PORT="redis-redis-advertised-0:31000,redis-redis-advertised-1:32000"
      export CURRENT_POD_HOST_IP="10.0.0.2"
      When run parse_redis_announce_addr "redis-redis-2"
      The status should be failure
      The stdout should include "Error: No matching svcName and port found for podName 'redis-redis-2'"
    End

    It "ignores when REDIS_ADVERTISED_PORT is not set"
      unset REDIS_ADVERTISED_PORT
      When call parse_redis_announce_addr "redis-redis-0"
      The status should be success
      The stdout should include "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    End

    It "uses host network port when available and no advertised port"
      unset REDIS_ADVERTISED_PORT
      export REDIS_HOST_NETWORK_PORT="6380"
      export CURRENT_POD_HOST_IP="192.168.1.100"
      When call parse_redis_announce_addr "redis-redis-0"
      The status should be success
      The variable redis_announce_port_value should eq "6380"
      The variable redis_announce_host_value should eq "192.168.1.100"
      The stdout should include "redis is in host network mode"
    End

    It "uses LB host when available"
      export REDIS_ADVERTISED_PORT="redis-redis-advertised-0:31000"
      export REDIS_LB_ADVERTISED_HOST="redis-redis-advertised-0:lb.example.com"
      export CURRENT_POD_HOST_IP="10.0.0.1"
      When call parse_redis_announce_addr "redis-redis-0"
      The variable redis_announce_host_value should eq "lb.example.com"
      The variable redis_announce_port_value should eq "6379"
      The stdout should include "Found load balancer host"
    End
  End

  Describe "check_current_pod_is_primary()"
    Context "matching with pod name"
      un_setup() {
        unset CURRENT_POD_NAME
        unset REDIS_COMPONENT_NAME
        unset primary
      }
      After 'un_setup'

      It "returns true when pod name prefix matches primary"
        export CURRENT_POD_NAME="redis-redis-0"
        export REDIS_COMPONENT_NAME="redis-redis"
        primary="redis-redis-0.redis-redis-headless.default"
        When call check_current_pod_is_primary
        The status should be success
        The stdout should include "current pod is primary with name mapping"
      End

      It "returns false when pod name does not match"
        export CURRENT_POD_NAME="redis-redis-1"
        export REDIS_COMPONENT_NAME="redis-redis"
        primary="redis-redis-0.redis-redis-headless.default"
        When call check_current_pod_is_primary
        The status should be failure
      End
    End

    Context "matching with pod IP"
      setup() {
        export CURRENT_POD_NAME="redis-redis-0"
        export CURRENT_POD_IP="10.0.0.1"
        export REDIS_COMPONENT_NAME="redis-redis"
        service_port="6379"
        primary="10.0.0.1"
        primary_port="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_POD_IP
        unset CURRENT_POD_NAME
        unset REDIS_COMPONENT_NAME
        unset service_port
        unset primary
        unset primary_port
      }
      After 'un_setup'

      It "returns true when pod IP and service port match"
        When call check_current_pod_is_primary
        The status should be success
        The stdout should include "current pod is primary with pod ip mapping"
      End
    End

    Context "matching with advertised svc"
      setup() {
        export CURRENT_POD_NAME="redis-redis-0"
        export CURRENT_POD_IP="10.0.0.1"
        export REDIS_COMPONENT_NAME="redis-redis"
        service_port="6379"
        redis_announce_host_value="172.0.0.1"
        redis_announce_port_value="31000"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_POD_IP
        unset CURRENT_POD_NAME
        unset REDIS_COMPONENT_NAME
        unset service_port
        unset primary
        unset primary_port
        unset redis_announce_host_value
        unset redis_announce_port_value
      }
      After 'un_setup'

      It "returns true when advertised host and port match"
        primary="172.0.0.1"
        primary_port="31000"
        When call check_current_pod_is_primary
        The status should be success
        The stdout should include "current pod is primary with advertised svc mapping"
      End

      It "returns false when advertised host and port do not match"
        primary="172.0.0.1"
        primary_port="32000"
        When call check_current_pod_is_primary
        The status should be failure
        The stdout should include "redis advertised svc host and port exist but not match"
      End
    End
  End

  Describe "build_sentinel_get_master_addr_by_name_command()"
    It "builds command without password"
      export REDIS_COMPONENT_NAME="redis-redis"
      export SENTINEL_SERVICE_PORT="26379"
      unset SENTINEL_PASSWORD
      When call build_sentinel_get_master_addr_by_name_command "sentinel1.headless"
      The output should eq "timeout 5 redis-cli -h sentinel1.headless -p 26379 sentinel get-master-addr-by-name redis-redis"
    End

    It "builds command with password"
      export REDIS_COMPONENT_NAME="redis-redis"
      export SENTINEL_SERVICE_PORT="26379"
      export SENTINEL_PASSWORD="mysentpass"
      When call build_sentinel_get_master_addr_by_name_command "sentinel1.headless"
      The output should eq "timeout 5 redis-cli -h sentinel1.headless -p 26379 -a mysentpass sentinel get-master-addr-by-name redis-redis"
    End
  End

  Describe "get_master_addr_by_name_from_sentinel()"
    It "retrieves primary info successfully"
      build_sentinel_get_master_addr_by_name_command() {
        echo "echo '172.18.0.3 31081'"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.headless"
      The status should be success
      The stdout should include "Successfully retrieved primary info from sentinel"
    End

    It "handles empty primary info"
      build_sentinel_get_master_addr_by_name_command() {
        echo "echo ''"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.headless"
      The status should be failure
      The stdout should include "Empty primary info retrieved from sentinel"
    End

    It "masks password in log output"
      SENTINEL_PASSWORD="secretpass"
      build_sentinel_get_master_addr_by_name_command() {
        echo "echo 'secretpass'"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.headless"
      The status should be failure
      The stdout should include "********"
      The stdout should not include "secretpass"
    End

    It "handles timeout (exit 124)"
      build_sentinel_get_master_addr_by_name_command() {
        echo "return 124"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.headless"
      The status should be failure
      The stdout should include "Timeout occurred while retrieving primary info from sentinel"
    End

    It "handles other errors"
      build_sentinel_get_master_addr_by_name_command() {
        echo "return 1"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.headless"
      The status should be failure
      The stdout should include "Error occurred while retrieving primary info from sentinel"
    End
  End

  Describe "get_default_initialize_primary_node()"
    Context "when min lex pod fqdn exists"
      setup() {
        export REDIS_POD_NAME_LIST="redis-2,redis-1,redis-0"
        export REDIS_POD_FQDN_LIST="redis-2.redis-headless.default,redis-1.redis-headless.default,redis-0.redis-headless.default"
        service_port="6379"
      }
      Before "setup"

      un_setup() {
        unset REDIS_POD_NAME_LIST
        unset REDIS_POD_FQDN_LIST
        unset service_port
      }
      After "un_setup"

      It "selects the min lex pod as primary"
        When call get_default_initialize_primary_node
        The variable primary should eq "redis-0.redis-headless.default"
        The variable primary_port should eq "6379"
        The stdout should include "get the minimum lexicographical order pod name"
      End
    End

    Context "when min lex pod fqdn does not exist"
      setup() {
        export REDIS_POD_NAME_LIST="redis-2,redis-1,redis-0"
        export REDIS_POD_FQDN_LIST="redis-2.redis-headless.default,redis-1.redis-headless.default"
        service_port="6379"
      }
      Before "setup"

      un_setup() {
        unset REDIS_POD_NAME_LIST
        unset REDIS_POD_FQDN_LIST
        unset service_port
      }
      After "un_setup"

      It "exits with error"
        When run get_default_initialize_primary_node
        The status should be failure
        The stdout should include "Error: Failed to get min lexicographical order pod"
      End
    End
  End

  Describe "build_redis_conf()"
    Context "when config file has stale content from CONFIG REWRITE"
      setup() {
        echo "loadmodule /opt/redis-stack/lib/redisearch.so" > "$redis_real_conf"
        echo "loadmodule /opt/redis-stack/lib/redistimeseries.so" >> "$redis_real_conf"
        echo "" > "$redis_acl_file"
        redis_template_conf="/etc/conf/redis.conf"
        load_redis_template_conf() {
          echo "include $redis_template_conf" >> "$redis_real_conf"
        }
        build_announce_ip_and_port() { :; }
        build_redis_service_port() { :; }
        build_replicaof_config() { :; }
        rebuild_redis_acl_file() { :; }
        build_redis_default_accounts() { :; }
      }
      Before "setup"

      un_setup() {
        rm -f "$redis_real_conf"
      }
      After "un_setup"

      It "truncates stale content before building"
        Skip if "shell type and version unmatch, please check!" should_skip_when_shell_type_and_version_invalid
        When call build_redis_conf
        The status should be success
        The contents of file "$redis_real_conf" should not include "loadmodule"
        The contents of file "$redis_real_conf" should include "include /etc/conf/redis.conf"
      End
    End
  End

  Describe "init_or_get_primary_from_redis_sentinel()"
    Context "when SENTINEL_COMPONENT_NAME is not set"
      setup() {
        primary=""
        primary_port=""
        unset SENTINEL_COMPONENT_NAME
      }
      Before "setup"

      It "falls back to default primary"
        Skip if "shell type and version unmatch, please check!" should_skip_when_shell_type_and_version_invalid
        get_default_initialize_primary_node() {
          primary="fake-primary"
          primary_port="fake-port"
        }
        When call init_or_get_primary_from_redis_sentinel
        The status should be success
        The stdout should include "SENTINEL_COMPONENT_NAME env is not set"
        The variable primary should eq "fake-primary"
      End
    End

    Context "when SENTINEL_POD_FQDN_LIST is not set"
      setup() {
        export SENTINEL_COMPONENT_NAME="redis-sentinel"
        unset SENTINEL_POD_FQDN_LIST
      }
      Before "setup"

      un_setup() {
        unset SENTINEL_COMPONENT_NAME
      }
      After "un_setup"

      It "exits with error"
        Skip if "shell type and version unmatch, please check!" should_skip_when_shell_type_and_version_invalid
        When run init_or_get_primary_from_redis_sentinel
        The status should be failure
        The stdout should include "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set."
      End
    End

    Context "when sentinel is configured but no sentinel returns primary info"
      setup() {
        export REDIS_DATA_DIR="./redis5-data"
        export SENTINEL_COMPONENT_NAME="redis-sentinel"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.redis-sentinel-headless,sentinel-1.redis-sentinel-headless"
        mkdir -p "$REDIS_DATA_DIR"
        echo "persisted" > "$REDIS_DATA_DIR/dump.rdb"
      }
      Before "setup"

      un_setup() {
        unset SENTINEL_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset REDIS_DATA_DIR
        rm -rf ./redis5-data
      }
      After "un_setup"

      It "fails closed instead of falling back to default primary when Redis data exists"
        Skip if "shell type and version unmatch, please check!" should_skip_when_shell_type_and_version_invalid
        getent() {
          echo "10.0.0.1 $2"
        }
        retry_get_master_addr_by_name_from_sentinel() {
          return 1
        }
        get_default_initialize_primary_node() {
          echo "SHOULD_NOT_FALLBACK"
        }
        When run init_or_get_primary_from_redis_sentinel
        The status should be failure
        The stdout should include "Failed to retrieve primary info from sentinel: sentinel-0.redis-sentinel-headless"
        The stdout should include "Failed to retrieve primary info from sentinel: sentinel-1.redis-sentinel-headless"
        The stdout should include "Error: no primary node found from all redis sentinels and Redis data already exists; refusing to use default primary while sentinel is configured."
        The stdout should not include "SHOULD_NOT_FALLBACK"
      End
    End

    Context "when no sentinel returns primary info before first bootstrap"
      setup() {
        service_port="6379"
        export REDIS_POD_NAME_LIST="redis-1,redis-0"
        export REDIS_POD_FQDN_LIST="redis-1.redis-headless.default,redis-0.redis-headless.default"
        export REDIS_DATA_DIR="./redis5-data-empty"
        export SENTINEL_COMPONENT_NAME="redis-sentinel"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.redis-sentinel-headless"
        mkdir -p "$REDIS_DATA_DIR"
        echo "placeholder" > "$REDIS_DATA_DIR/users.acl"
      }
      Before "setup"

      un_setup() {
        unset REDIS_POD_NAME_LIST
        unset REDIS_POD_FQDN_LIST
        unset REDIS_DATA_DIR
        unset SENTINEL_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset service_port
        rm -rf ./redis5-data-empty
      }
      After "un_setup"

      It "allows default primary fallback for first bootstrap"
        Skip if "shell type and version unmatch, please check!" should_skip_when_shell_type_and_version_invalid
        getent() {
          echo "10.0.0.1 $2"
        }
        retry_get_master_addr_by_name_from_sentinel() {
          return 1
        }
        When call init_or_get_primary_from_redis_sentinel
        The status should be success
        The stdout should include "no primary node found from all redis sentinels and Redis data dir is empty, use default primary node for first bootstrap."
        The variable primary should eq "redis-0.redis-headless.default"
        The variable primary_port should eq "6379"
      End
    End
  End
End
