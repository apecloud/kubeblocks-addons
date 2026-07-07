# shellcheck shell=bash
# shellcheck disable=SC2034

# we need bash 4 or higher to run this script in some cases
should_skip_when_shell_type_and_version_invalid() {
  # validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
  if validate_shell_type_and_version "bash" 4 &>/dev/null; then
    # should not skip
    return 1
  fi
  echo "redis_start_spec.sh skip case because dependency bash version 4 or higher is not installed."
  return 0
}

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
    redis_acl_file_bak="./users.acl.bak"
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $redis_real_conf;
    rm -f $redis_acl_file;
    rm -f $common_library_file;
  }
  AfterAll 'cleanup'

  Describe "extract_obj_ordinal()"
    It "extracts ordinal from object name correctly"
      When call extract_obj_ordinal "pod-name-2"
      The status should be success
      The stdout should eq "2"
      The stderr should eq ""
    End

    It "extracts ordinal from object name with different format"
      When call extract_obj_ordinal "3"
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
        export REDIS_REPL_PASSWORD="repl_password"
        export REDIS_SENTINEL_PASSWORD="sentinel_password"
        export REDIS_DEFAULT_PASSWORD="default_password"
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
        redis_repl_sha256=$(echo -n "$REDIS_REPL_PASSWORD" | sha256sum | cut -d' ' -f1)
        redis_password_sha256=$(echo -n "$REDIS_DEFAULT_PASSWORD" | sha256sum | cut -d' ' -f1)
        redis_sentinel_password_sha256=$(echo -n "$REDIS_SENTINEL_PASSWORD" | sha256sum | cut -d' ' -f1)
        The contents of file "$redis_acl_file" should include "user $REDIS_REPL_USER on +psync +replconf +ping #$redis_repl_sha256"
        The contents of file "$redis_acl_file" should include "user $REDIS_SENTINEL_USER on allchannels +multi +slaveof +ping +exec +subscribe +config|rewrite +role +publish +info +client|setname +client|kill +script|kill #$redis_sentinel_password_sha256"
        The contents of file "$redis_acl_file" should include "user default on #$redis_password_sha256 ~* &* +@all"
      End
    End

    Context 'when default password environment variables exist'
      setup() {
        echo "" > $redis_real_conf
        echo "" > $redis_acl_file
        export REDIS_DEFAULT_PASSWORD="default_password"
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
        redis_password_sha256=$(echo -n "$REDIS_DEFAULT_PASSWORD" | sha256sum | cut -d' ' -f1)
        The contents of file "$redis_acl_file" should include "user default on #$redis_password_sha256 ~* &* +@all"
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
      redis_announce_host_value="172.0.0.1"
      redis_announce_port_value="31000"
      When call build_announce_ip_and_port
      The contents of file "$redis_real_conf" should include "replica-announce-port $redis_announce_port_value"
      The contents of file "$redis_real_conf" should include "replica-announce-ip $redis_announce_host_value"
      The stdout should include "redis use nodeport $redis_announce_host_value:$redis_announce_port_value to announce"
    End

    It "builds announce ip and port correctly when advertised svc is not enabled"
      unset redis_announce_host_value
      unset redis_announce_port_value
      export CURRENT_POD_NAME="redis-redis-0"
      export REDIS_POD_FQDN_LIST="redis-redis-0.redis-redis.default.svc.cluster.local,redis-redis-1.redis-redis.default.svc.cluster.local"
      When call build_announce_ip_and_port
      The contents of file "$redis_real_conf" should include "replica-announce-ip redis-redis-0.redis-redis.default.svc.cluster.local"
      The stdout should include "redis use kb pod fqdn redis-redis-0.redis-redis.default.svc.cluster.local to announce"
    End

    It "exits with error when failed to get current pod fqdn"
      unset redis_announce_host_value
      unset redis_announce_port_value
      export CURRENT_POD_NAME="redis-redis-2"
      export REDIS_POD_FQDN_LIST="redis-redis-0.redis-redis.default,redis-redis-1.redis-redis.default"
      When run build_announce_ip_and_port
      The status should be failure
      The stdout should include "Error: Failed to get current pod: redis-redis-2 fqdn from redis pod fqdn list: redis-redis-0.redis-redis.default,redis-redis-1.redis-redis.default. Exiting."
    End
  End

  Describe "build_redis_service_port()"
    It "builds redis service port correctly when SERVICE_PORT env is set"
      export service_port="6380"
      When call build_redis_service_port
      The contents of file "$redis_real_conf" should include "port $SERVICE_PORT"
    End
  End

  Describe "parse_redis_announce_addr()"
    It "parses redis advertised service correctly when matching svc is found"
      export REDIS_ADVERTISED_PORT="redis-redis-redis-advertised-0:31000,redis-redis-redis-advertised-1:32000"
      export CURRENT_POD_HOST_IP="10.0.0.1"
      When call parse_redis_announce_addr "redis-redis-0"
      The variable redis_announce_port_value should eq "31000"
      The variable redis_announce_host_value should eq "10.0.0.1"
      The stdout should include "Found matching svcName and port for podName 'redis-redis-0'"
    End

    It "exits with error when no matching svc is found"
      export REDIS_ADVERTISED_PORT="redis-redis-redis-advertised-0:31000,redis-redis-redis-advertised-1:32000"
      export CURRENT_POD_HOST_IP="10.0.0.2"
      When run parse_redis_announce_addr "redis-redis-2"
      The status should be failure
      The stdout should include "Error: No matching svcName and port found for podName 'redis-redis-2'"
    End

    It "ignores parsing when REDIS_ADVERTISED_PORT env is not set"
      unset REDIS_ADVERTISED_PORT
      When call parse_redis_announce_addr "redis-redis-0"
      The status should be success
      The stdout should include "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    End
  End

  Describe "check_current_pod_is_primary()"
    Context 'mapping with pod name'
      un_setup() {
        unset CURRENT_POD_NAME
        unset REDIS_COMPONENT_NAME
        unset primary
      }
      After 'un_setup'

      It "returns true when current pod name matches the primary"
        export CURRENT_POD_NAME="redis-redis-0"
        export REDIS_COMPONENT_NAME="redis-redis"
        primary="redis-redis-0.redis-redis-headless.default"
        When call check_current_pod_is_primary
        The status should be success
        The stdout should include "current pod is primary with name mapping"
      End

      It "returns false when current pod does not match the primary"
        export CURRENT_POD_NAME="redis-redis-1"
        export REDIS_COMPONENT_NAME="redis-redis"
        primary="redis-redis-0.redis-redis-headless.default"
        When call check_current_pod_is_primary
        The status should be failure
      End
    End

    Context 'mapping with pod ip and service port'
      setup() {
        export CURRENT_POD_NAME="redis-redis-0"
        export CURRENT_POD_IP="10.0.0.1"
        service_port="6379"
        primary="10.0.0.1"
        primary_port="6379"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_POD_IP
        unset CURRENT_POD_NAME
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
        export CURRENT_POD_NAME="redis-redis-0"
        export CURRENT_POD_IP="10.0.0.1"
        service_port="6379"
        redis_announce_host_value="172.0.0.1"
        redis_announce_port_value="31000"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_POD_IP
        unset service_port
        unset primary
        unset primary_port
        unset redis_announce_host_value
        unset redis_announce_port_value
      }
      After 'un_setup'

      It "returns false when current redis_announce_host_value and redis_announce_port_value exist but not match"
        primary="172.0.0.1"
        primary_port="32000"
        When call check_current_pod_is_primary
        The status should be failure
        The stdout should include "redis advertised svc host and port exist but not match"
      End

      It "returns true when current redis_announce_host_value and redis_announce_port_value matches the primary"
        primary="172.0.0.1"
        primary_port="31000"
        When call check_current_pod_is_primary
        The status should be success
        The stdout should include "current pod is primary with advertised svc mapping"
      End
    End
  End

  Describe "rebuild_redis_acl_file()"
    It "rebuilds redis acl file by removing specific user lines"
      echo "user default on >default_password" > $redis_acl_file
      echo "user repl_user on >repl_password" >> $redis_acl_file
      echo "user sentinel_user on >sentinel_password" >> $redis_acl_file
      export REDIS_REPL_USER="repl_user"
      export REDIS_SENTINEL_USER="sentinel_user"
      When call rebuild_redis_acl_file
      The status should be success
      The contents of file "$redis_acl_file" should not include "user default on"
      The contents of file "$redis_acl_file" should not include "user repl_user on"
      The contents of file "$redis_acl_file" should not include "user sentinel_user on"
    End

    It "creates an empty redis acl file if it does not exist"
      rm -f $redis_acl_file
      When call rebuild_redis_acl_file
      The path "$redis_acl_file" should be exist
      The contents of file "$redis_acl_file" should eq ""
    End
  End

  Describe "build_sentinel_get_master_addr_by_name_command()"
    It "builds sentinel get-master-addr-by-name command correctly"
      export REDIS_COMPONENT_NAME="redis-redis"
      export SENTINEL_SERVICE_PORT="26379"
      When call build_sentinel_get_master_addr_by_name_command "sentinel1.redis-sentinel-headless"
      The output should eq "timeout 5 redis-cli  -h sentinel1.redis-sentinel-headless -p 26379 sentinel get-master-addr-by-name redis-redis"
    End

    It "builds sentinel get-master-addr-by-name command correctly"
      export REDIS_COMPONENT_NAME="redis-redis"
      export SENTINEL_SERVICE_PORT="26379"
      export SENTINEL_PASSWORD="sentinel_password"
      When call build_sentinel_get_master_addr_by_name_command "sentinel1.redis-sentinel-headless"
      The output should eq "timeout 5 redis-cli  -h sentinel1.redis-sentinel-headless -p 26379 -a sentinel_password sentinel get-master-addr-by-name redis-redis"
    End
  End

  Describe "get_master_addr_by_name_from_sentinel()"
    It "handles empty sentinel password"
      unset SENTINEL_PASSWORD
      build_sentinel_get_master_addr_by_name_command() {
        echo "echo $SENTINEL_PASSWORD 1111"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.redis-sentinel-headless"
      The status should be failure
      The stdout should include "Empty primary info retrieved from sentinel"
      The stdout should include "execute get-master-addr-by-name command: echo  1111"
    End

    It "handles not empty sentinel password"
      SENTINEL_PASSWORD="sentinel_password"
      build_sentinel_get_master_addr_by_name_command() {
        echo "echo $SENTINEL_PASSWORD"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.redis-sentinel-headless"
      The status should be failure
      The stdout should include "Empty primary info retrieved from sentinel"
      The stdout should include "execute get-master-addr-by-name command: echo ********"
    End

    It "retrieves primary info from sentinel successfully"
      # Mock the command to get redis master addr info from sentinel
      build_sentinel_get_master_addr_by_name_command() {
        mock_output="172.18.0.3 31081"
        # shellcheck disable=SC2028
        echo "echo '$mock_output'"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.redis-sentinel-headless"
      The status should be success
      The stdout should include "Successfully retrieved primary info from sentinel"
    End

    It "handles empty primary info from sentinel"
      build_sentinel_get_master_addr_by_name_command() {
        echo "echo ''"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.redis-sentinel-headless"
      The status should be failure
      The stdout should include "Empty primary info retrieved from sentinel"
    End

    It "retries on timeout error from sentinel"
      build_sentinel_get_master_addr_by_name_command() {
        echo "return 124"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.redis-sentinel-headless"
      The status should be failure
      The stdout should include "Timeout occurred while retrieving primary info from sentinel. Retrying..."
    End

    It "retries on other errors from sentinel"
      build_sentinel_get_master_addr_by_name_command() {
        echo "return 1"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.redis-sentinel-headless"
      The status should be failure
      The stdout should include "Error occurred while retrieving primary info from sentinel. Retrying..."
    End
  End

  Describe "retry_get_master_addr_by_name_from_sentinel()"
    It "retries to get primary info from sentinel successfully"
      get_master_addr_by_name_from_sentinel() {
        # mock get_master_addr_by_name_from_sentinel success
        return 0
      }
      When call retry_get_master_addr_by_name_from_sentinel 2 1 "sentinel1.redis-sentinel-headless"
      The status should be success
    End

    It "retries to get primary info from sentinel and fails"
      get_master_addr_by_name_from_sentinel() {
        # mock get_master_addr_by_name_from_sentinel failure
        return 1
      }
      When call retry_get_master_addr_by_name_from_sentinel 1 1 "sentinel1.redis-sentinel-headless"
      The status should be failure
      The stdout should include "Failed to retrieve primary info from sentinel"
      The stderr should include "Function 'get_master_addr_by_name_from_sentinel' failed after 1 retries"
    End
  End

  Describe "get_default_initialize_primary_node()"
    Context "when min lexicographical order pod fqdn exists"
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

      It "gets the minimum lexicographical order pod name as default primary node"
        When call get_default_initialize_primary_node
        The variable primary should eq "redis-0.redis-headless.default"
        The variable primary_port should eq "6379"
        The stdout should include "get the minimum lexicographical order pod name: redis-0.redis-headless.default as default primary node"
      End
    End

    Context "when min lexicographical order pod fqdn does not exist"
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

      It "exits with error if failed to get min lexicographical order pod fqdn"
        When run get_default_initialize_primary_node
        The status should be failure
        The stdout should include "Error: Failed to get min lexicographical order pod: $CURRENT_POD_NAME fqdn from redis pod fqdn list: redis-2.redis-headless.default,redis-1.redis-headless.default. Exiting."
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

      It "gets default primary node if SENTINEL_COMPONENT_NAME is not set"
        Skip if "shell type and version unmatch, please check!" should_skip_when_shell_type_and_version_invalid
        get_default_initialize_primary_node() {
          # shellcheck disable=SC2034
          primary="fake-primary"
          # shellcheck disable=SC2034
          primary_port="fake-primary-port"
        }
        When call init_or_get_primary_from_redis_sentinel
        The status should be success
        The stdout should include "SENTINEL_COMPONENT_NAME env is not set, try to use default primary node"
        The variable primary should eq "fake-primary"
        The variable primary_port should eq "fake-primary-port"
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

      It "exits with error if SENTINEL_POD_FQDN_LIST is not set"
        Skip if "shell type and version unmatch, please check!" should_skip_when_shell_type_and_version_invalid
        When run init_or_get_primary_from_redis_sentinel
        The status should be failure
        The stdout should include "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set."
      End
    End

    Context "when primary info is retrieved from sentinels"
      setup() {
        export SENTINEL_COMPONENT_NAME="redis-sentinel"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.redis-sentinel-headless,sentinel-1.redis-sentinel-headless,sentinel-2.redis-sentinel-headless"
      }
      Before "setup"

      un_setup() {
        unset SENTINEL_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
      }
      After "un_setup"

      It "retrieves primary info from multiple sentinels and selects the one with max count"
        Skip if "shell type and version unmatch, please check!" should_skip_when_shell_type_and_version_invalid
        build_sentinel_get_master_addr_by_name_command() {
          mock_output="172.18.0.3 31081"
          # shellcheck disable=SC2028
          echo "echo '$mock_output'"
        }
        When call init_or_get_primary_from_redis_sentinel
        The status should be success
        The variable primary should eq "172.18.0.3"
        The variable primary_port should eq "31081"
        The stdout should include "sentinel:sentinel-0.redis-sentinel-headless has master info: 172.18.0.3 31081"
        The stdout should include "sentinel:sentinel-1.redis-sentinel-headless has master info: 172.18.0.3 31081"
        The stdout should include "sentinel:sentinel-2.redis-sentinel-headless has master info: 172.18.0.3 31081"
      End
    End

    Context "when empty primary info is retrieved from sentinels"
      setup() {
        # shellcheck disable=SC2034
        retry_times=1
        # shellcheck disable=SC2034
        retry_delay_second=1
        export REDIS_POD_NAME_LIST="redis-1,redis-0"
        export SENTINEL_COMPONENT_NAME="redis-sentinel"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.redis-sentinel-headless,sentinel-1.redis-sentinel-headless"
      }
      Before "setup"

      un_setup() {
        unset SENTINEL_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
      }
      After "un_setup"

      It "handles empty primary info retrieved from sentinel"
        Skip if "shell type and version unmatch, please check!" should_skip_when_shell_type_and_version_invalid
        build_sentinel_get_master_addr_by_name_command() {
          echo "echo ''"
        }
        get_default_initialize_primary_node() {
          # shellcheck disable=SC2034
          primary="fake-primary1"
          # shellcheck disable=SC2034
          primary_port="fake-primary-port1"
        }
        When call init_or_get_primary_from_redis_sentinel
        The status should be success
        The stdout should include "Empty primary info retrieved from sentinel"
        The stdout should include "Failed to retrieve primary info from sentinel: sentinel-1.redis-sentinel-headless"
        The stdout should include "no primary node found from all redis sentinels, use default primary node."
        The stderr should include "Function 'get_master_addr_by_name_from_sentinel' failed after 1 retries"
        The variable primary should eq "fake-primary1"
        The variable primary_port should eq "fake-primary-port1"
      End
    End
  End
End