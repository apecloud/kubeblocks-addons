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
    rm -f $redis_real_conf;
    rm -f $redis_acl_file;
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
        The contents of file "$redis_acl_file" should include "user $REDIS_REPL_USER on +psync +replconf +ping >$REDIS_REPL_PASSWORD"
        The contents of file "$redis_acl_file" should include "user $REDIS_SENTINEL_USER on allchannels +multi +slaveof +ping +exec +subscribe +config|rewrite +role +publish +info +client|setname +client|kill +script|kill >$REDIS_SENTINEL_PASSWORD"
        The contents of file "$redis_acl_file" should include "user default on >$REDIS_DEFAULT_PASSWORD ~* &* +@all"
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
      redis_advertised_svc_host_value="172.0.0.1"
      redis_advertised_svc_port_value="31000"
      When call build_announce_ip_and_port
      The contents of file "$redis_real_conf" should include "replica-announce-port $redis_advertised_svc_port_value"
      The contents of file "$redis_real_conf" should include "replica-announce-ip $redis_advertised_svc_host_value"
      The stdout should include "redis use nodeport $redis_advertised_svc_host_value:$redis_advertised_svc_port_value to announce"
    End

    It "builds announce ip and port correctly when advertised svc is not enabled"
      unset redis_advertised_svc_host_value
      unset redis_advertised_svc_port_value
      export KB_POD_NAME="redis-redis-0"
      export REDIS_POD_FQDN_LIST="redis-redis-0.redis-redis.default.svc.cluster.local,redis-redis-1.redis-redis.default.svc.cluster.local"
      When call build_announce_ip_and_port
      The contents of file "$redis_real_conf" should include "replica-announce-ip redis-redis-0.redis-redis.default.svc.cluster.local"
      The stdout should include "redis use kb pod fqdn redis-redis-0.redis-redis.default.svc.cluster.local to announce"
    End

    It "exits with error when failed to get current pod fqdn"
      unset redis_advertised_svc_host_value
      unset redis_advertised_svc_port_value
      export KB_POD_NAME="redis-redis-2"
      export REDIS_POD_FQDN_LIST="redis-redis-0.redis-redis.default,redis-redis-1.redis-redis.default"
      When run build_announce_ip_and_port
      The status should be failure
      The stdout should include "Error: Failed to get current pod: redis-redis-2 fqdn from redis pod fqdn list: redis-redis-0.redis-redis.default,redis-redis-1.redis-redis.default. Exiting."
    End
  End

  Describe "build_redis_service_port()"
    It "builds redis service port correctly when SERVICE_PORT env is set"
      export SERVICE_PORT="6380"
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
      export REDIS_ADVERTISED_PORT="redis-redis-redis-advertised-0:31000,redis-redis-redis-advertised-1:32000"
      export KB_HOST_IP="10.0.0.1"
      When call parse_redis_advertised_svc_if_exist "redis-redis-0"
      The variable redis_advertised_svc_port_value should eq "31000"
      The variable redis_advertised_svc_host_value should eq "10.0.0.1"
      The stdout should include "Found matching svcName and port for podName 'redis-redis-0'"
    End

    It "exits with error when no matching svc is found"
      export REDIS_ADVERTISED_PORT="redis-redis-redis-advertised-0:31000,redis-redis-redis-advertised-1:32000"
      export KB_HOST_IP="10.0.0.2"
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
        export KB_POD_NAME="redis-redis-0"
        export KB_CLUSTER_COMP_NAME="redis-redis"
        primary="redis-redis-0.redis-redis-headless.default"
        When call check_current_pod_is_primary
        The status should be success
        The stdout should include "current pod is primary with name mapping"
      End

      It "returns false when current pod does not match the primary"
        export KB_POD_NAME="redis-redis-1"
        export KB_CLUSTER_COMP_NAME="redis-redis"
        primary="redis-redis-0.redis-redis-headless.default"
        When call check_current_pod_is_primary
        The status should be failure
      End
    End

    Context 'mapping with pod ip and service port'
      setup() {
        export KB_POD_NAME="redis-redis-0"
        export KB_POD_IP="10.0.0.1"
        service_port="6379"
        primary="10.0.0.1"
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
        export KB_POD_NAME="redis-redis-0"
        export KB_POD_IP="10.0.0.1"
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
        unset redis_advertised_svc_host_value
        unset redis_advertised_svc_port_value
      }
      After 'un_setup'

      It "returns false when current redis_advertised_svc_host_value and redis_advertised_svc_port_value exist but not match"
        primary="172.0.0.1"
        primary_port="32000"
        When call check_current_pod_is_primary
        The status should be failure
        The stdout should include "redis advertised svc host and port exist but not match"
      End

      It "returns true when current redis_advertised_svc_host_value and redis_advertised_svc_port_value matches the primary"
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
      export KB_CLUSTER_COMP_NAME="redis-redis"
      export SENTINEL_SERVICE_PORT="26379"
      export SENTINEL_PASSWORD="sentinel_password"
      When call build_sentinel_get_master_addr_by_name_command "sentinel1.redis-sentinel-headless"
      The output should eq "timeout 5 redis-cli -h sentinel1.redis-sentinel-headless -p 26379 -a sentinel_password sentinel get-master-addr-by-name redis-redis"
    End
  End

  Describe "get_master_addr_by_name_from_sentinel()"
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
      # mock sed command execute error in get_master_addr_by_name_from_sentinel
      The stderr should include "first RE may not be empty"
    End

    It "handles empty primary info from sentinel"
      build_sentinel_get_master_addr_by_name_command() {
        echo "echo ''"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.redis-sentinel-headless"
      The status should be failure
      The stdout should include "Empty primary info retrieved from sentinel"
      # mock sed command execute error in get_master_addr_by_name_from_sentinel
      The stderr should include "first RE may not be empty"
    End

    It "retries on timeout error from sentinel"
      build_sentinel_get_master_addr_by_name_command() {
        echo "return 124"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.redis-sentinel-headless"
      The status should be failure
      The stdout should include "Timeout occurred while retrieving primary info from sentinel. Retrying..."
      # mock sed command execute error in get_master_addr_by_name_from_sentinel
      The stderr should include "first RE may not be empty"
    End

    It "retries on other errors from sentinel"
      build_sentinel_get_master_addr_by_name_command() {
        echo "return 1"
      }
      When call get_master_addr_by_name_from_sentinel "sentinel1.redis-sentinel-headless"
      The status should be failure
      The stdout should include "Error occurred while retrieving primary info from sentinel. Retrying..."
      # mock sed command execute error in get_master_addr_by_name_from_sentinel
      The stderr should include "first RE may not be empty"
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
    End
  End

  Describe "get_default_initialize_primary_node()"
    Context "when min lexicographical order pod fqdn exists"
      setup() {
        export KB_POD_LIST="redis-2,redis-1,redis-0"
        export REDIS_POD_FQDN_LIST="redis-2.redis-headless.default,redis-1.redis-headless.default,redis-0.redis-headless.default"
        service_port="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_POD_LIST
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
        export KB_POD_LIST="redis-2,redis-1,redis-0"
        export REDIS_POD_FQDN_LIST="redis-2.redis-headless.default,redis-1.redis-headless.default"
        service_port="6379"
      }
      Before "setup"

      un_setup() {
        unset KB_POD_LIST
        unset REDIS_POD_FQDN_LIST
        unset service_port
      }
      After "un_setup"

      It "exits with error if failed to get min lexicographical order pod fqdn"
        When run get_default_initialize_primary_node
        The status should be failure
        The stdout should include "Error: Failed to get min lexicographical order pod: $KB_POD_NAME fqdn from redis pod fqdn list: redis-2.redis-headless.default,redis-1.redis-headless.default. Exiting."
      End
    End
  End

#  Describe "init_or_get_primary_from_redis_sentinel()"
#    Context 'when primary is not set'
#      setup() {
#        export KB_CLUSTER_COMP_NAME="redis-redis"
#        export SENTINEL_POD_FQDN_LIST="sentinel1.redis-sentinel-headless,sentinel2.redis-sentinel-headless"
#        export SENTINEL_SERVICE_PORT="26379"
#        export SENTINEL_PASSWORD="sentinel_password"
#      }
#      Before 'setup'
#
#      un_setup() {
#        unset KB_CLUSTER_COMP_NAME
#        unset SENTINEL_POD_FQDN_LIST
#        unset SENTINEL_SERVICE_PORT
#        unset SENTINEL_PASSWORD
#        unset primary
#      }
#      After 'un_setup'
#
#      It "initializes primary from sentinel successfully"
#        stub retry_get_master_addr_by_name_from_sentinel
#        When call init_or_get_primary_from_redis_sentinel
#        The status should be success
#        The variable primary should eq ""
#      End
#    End
#  End
#
#  Describe "start_redis_server()"
#    It "starts redis server with default configuration"
#      When run start_redis_server
#      The status should be success
#      The stdout should include "exec redis-server /etc/redis/redis.conf"
#    End
#
#    It "starts redis server with loadmodule configuration"
#      mkdir -p /opt/redis-stack/lib
#      touch /opt/redis-stack/lib/redisearch.so
#      touch /opt/redis-stack/lib/redistimeseries.so
#      touch /opt/redis-stack/lib/redisbloom.so
#      export REDISEARCH_ARGS="--arg1 value1"
#      export REDISTIMESERIES_ARGS="--arg2 value2"
#      export REDISBLOOM_ARGS="--arg3 value3"
#      When run start_redis_server
#      The status should be success
#      The stdout should include "exec redis-server /etc/redis/redis.conf"
#      The stdout should include "--loadmodule /opt/redis-stack/lib/redisearch.so --arg1 value1"
#      The stdout should include "--loadmodule /opt/redis-stack/lib/redistimeseries.so --arg2 value2"
#      The stdout should include "--loadmodule /opt/redis-stack/lib/redisbloom.so --arg3 value3"
#    End
#  End
End