# shellcheck shell=bash
# shellcheck disable=SC2034

# we need bash 4 or higher to run this script in some cases
should_skip_when_shell_type_and_version_invalid() {
  # validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
  if validate_shell_type_and_version "bash" 4 &>/dev/null; then
    # should not skip
    return 1
  fi
  echo "redis_cluster_server_start_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  return 0
}

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Cluster Server Start Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file
  Include ../redis-cluster-scripts/redis-cluster-common.sh
  Include ../redis-cluster-scripts/redis-cluster-server-start.sh

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
        export REDIS_DEFAULT_PASSWORD="default_password"
      }
      Before 'setup'

      un_setup() {
        unset REDIS_REPL_PASSWORD
        unset REDIS_DEFAULT_PASSWORD
      }
      After 'un_setup'

      It "builds default accounts correctly when all password envs are set"
        When call build_redis_default_accounts
        The status should be success
        The stdout should include "build redis default accounts succeeded!"
        The contents of file "$redis_real_conf" should include "masteruser $REDIS_REPL_USER"
        The contents of file "$redis_real_conf" should include "masterauth $REDIS_REPL_PASSWORD"
        The contents of file "$redis_real_conf" should include "protected-mode yes"
        The contents of file "$redis_real_conf" should include "aclfile /data/users.acl"
        The contents of file "$redis_acl_file" should include "user $REDIS_REPL_USER on +psync +replconf +ping >$REDIS_REPL_PASSWORD"
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
        The stdout should include "build redis default accounts succeeded!"
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
        The stdout should include "build redis default accounts succeeded!"
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
      The stdout should include "redis use advertised svc $redis_advertised_svc_host_value:$redis_advertised_svc_port_value to announce"
    End

    It "builds announce ip and port correctly when advertised svc is not enabled"
      unset redis_advertised_svc_host_value
      unset redis_advertised_svc_port_value
      export CURRENT_POD_NAME="redis-redis-0"
      export CURRENT_SHARD_POD_FQDN_LIST="redis-redis-0.redis-redis.default.svc.cluster.local,redis-redis-1.redis-redis.default.svc.cluster.local"
      When call build_announce_ip_and_port
      The contents of file "$redis_real_conf" should include "replica-announce-ip redis-redis-0.redis-redis.default.svc.cluster.local"
      The stdout should include "redis use kb pod fqdn redis-redis-0.redis-redis.default.svc.cluster.local to announce"
    End

    It "exits with error when failed to get current pod fqdn"
      unset redis_advertised_svc_host_value
      unset redis_advertised_svc_port_value
      export CURRENT_POD_NAME="redis-redis-2"
      export CURRENT_SHARD_POD_FQDN_LIST="redis-redis-0.redis-redis.default,redis-redis-1.redis-redis.default"
      When run build_announce_ip_and_port
      The status should be failure
      The stdout should include "Error: Failed to get current pod: redis-redis-2 fqdn from current shard pod fqdn list: redis-redis-0.redis-redis.default,redis-redis-1.redis-redis.default. Exiting."
    End
  End

  Describe "build_cluster_announce_info()"
    It "builds cluster announce info correctly when advertised svc is enabled"
      redis_advertised_svc_host_value="172.0.0.1"
      redis_advertised_svc_port_value="31000"
      redis_advertised_svc_bus_port_value="31000"
      export CURRENT_POD_NAME="redis-redis-0"
      export CURRENT_SHARD_POD_FQDN_LIST="redis-redis-0.redis-redis.default.svc.cluster.local,redis-redis-1.redis-redis.default.svc.cluster.local"
      When call build_cluster_announce_info
      The contents of file "$redis_real_conf" should include "cluster-announce-port $redis_advertised_svc_port_value"
      The contents of file "$redis_real_conf" should include "cluster-announce-ip $redis_advertised_svc_host_value"
      The contents of file "$redis_real_conf" should include "cluster-announce-bus-port $redis_advertised_svc_bus_port_value"
      The contents of file "$redis_real_conf" should include "cluster-announce-hostname redis-redis-0.redis-redis.default.svc.cluster.local"
      The contents of file "$redis_real_conf" should include "cluster-preferred-endpoint-type ip"
      The stdout should include "redis cluster use advertised svc $redis_advertised_svc_host_value:$redis_advertised_svc_port_value@$redis_advertised_svc_bus_port_value to announce"

    End

    It "builds cluster announce info correctly when advertised svc is not enabled"
      unset redis_advertised_svc_host_value
      unset redis_advertised_svc_port_value
      unset redis_advertised_svc_bus_port_value
      export CURRENT_POD_IP="172.0.0.5"
      export CURRENT_POD_NAME="redis-redis-0"
      export CURRENT_SHARD_POD_FQDN_LIST="redis-redis-0.redis-redis.default.svc.cluster.local,redis-redis-1.redis-redis.default.svc.cluster.local"
      When call build_cluster_announce_info
      The contents of file "$redis_real_conf" should include "cluster-announce-ip $CURRENT_POD_IP"
      The contents of file "$redis_real_conf" should include "cluster-announce-hostname redis-redis-0.redis-redis.default.svc.cluster.local"
      The contents of file "$redis_real_conf" should include "cluster-preferred-endpoint-type hostname"
      The stdout should include "redis use kb pod fqdn redis-redis-0.redis-redis.default.svc.cluster.local to announce"
    End
  End

  Describe "build_redis_cluster_service_port()"
    It "builds redis service port correctly when SERVICE_PORT env is set"
      export SERVICE_PORT="6380"
      export CLUSTER_BUS_PORT="16380"
      When call build_redis_cluster_service_port
      The contents of file "$redis_real_conf" should include "port $SERVICE_PORT"
      The contents of file "$redis_real_conf" should include "cluster-port $CLUSTER_BUS_PORT"
    End

    It "builds redis service port with default value when SERVICE_PORT env is not set"
      unset SERVICE_PORT
      unset CLUSTER_BUS_PORT
      When call build_redis_cluster_service_port
      The contents of file "$redis_real_conf" should include "port 6379"
      The contents of file "$redis_real_conf" should include "cluster-port 16379"
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

  Describe "parse_current_pod_advertised_svc_if_exist()"
    Context "when both CURRENT_SHARD_ADVERTISED_PORT and CURRENT_SHARD_ADVERTISED_BUS_PORT are set"
      setup() {
        export CURRENT_POD_HOST_IP="172.0.0.1"
        export CURRENT_POD_NAME="redis-redis-0"
        export CURRENT_SHARD_ADVERTISED_PORT="redis-redis-0:31000,redis-redis-1:31001"
        export CURRENT_SHARD_ADVERTISED_BUS_PORT="redis-redis-0:31888,redis-redis-1:31889"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_POD_HOST_IP
        unset CURRENT_POD_NAME
        unset CURRENT_SHARD_ADVERTISED_PORT
        unset CURRENT_SHARD_ADVERTISED_BUS_PORT
      }
      After "un_setup"

      It "parses advertised service correctly"
        When call parse_current_pod_advertised_svc_if_exist
        The variable redis_advertised_svc_port_value should equal "31000"
        The variable redis_advertised_svc_bus_port_value should equal "31888"
        The variable redis_advertised_svc_host_value should equal "172.0.0.1"
      End
    End

    Context "when CURRENT_SHARD_ADVERTISED_PORT or CURRENT_SHARD_ADVERTISED_BUS_PORT is not set"
      setup() {
        unset CURRENT_POD_HOST_IP
        unset CURRENT_POD_NAME
        unset CURRENT_SHARD_ADVERTISED_PORT
        unset CURRENT_SHARD_ADVERTISED_BUS_PORT
      }
      Before "setup"

      It "ignores parsing when CURRENT_SHARD_ADVERTISED_PORT and CURRENT_SHARD_ADVERTISED_BUS_PORT are not set"
        When call parse_current_pod_advertised_svc_if_exist
        The stdout should include "Environment variable CURRENT_SHARD_ADVERTISED_PORT and CURRENT_SHARD_ADVERTISED_BUS_PORT not found. Ignoring."
      End
    End

    Context "when CURRENT_SHARD_ADVERTISED_PORT is invalid"
      setup() {
        export CURRENT_POD_HOST_IP="172.0.0.1"
        export CURRENT_POD_NAME="redis-redis-1"
        export CURRENT_SHARD_ADVERTISED_PORT="redis-redis-0:31000,redis-redis-1"
        export CURRENT_SHARD_ADVERTISED_BUS_PORT="redis-redis-0:31888,redis-redis-1:32222"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_POD_HOST_IP
        unset CURRENT_POD_NAME
        unset CURRENT_SHARD_ADVERTISED_PORT
        unset CURRENT_SHARD_ADVERTISED_BUS_PORT
      }
      After "un_setup"

      It "exits with error when CURRENT_SHARD_ADVERTISED_PORT is invalid"
        When run parse_current_pod_advertised_svc_if_exist
        The status should be failure
        The stdout should include "Exiting due to error in CURRENT_SHARD_ADVERTISED_PORT."
      End
    End

    Context "when CURRENT_SHARD_ADVERTISED_BUS_PORT is invalid"
      setup() {
        export CURRENT_POD_HOST_IP="172.0.0.1"
        export CURRENT_POD_NAME="redis-redis-1"
        export CURRENT_SHARD_ADVERTISED_PORT="redis-redis-0:31000,redis-redis-1:31001"
        export CURRENT_SHARD_ADVERTISED_BUS_PORT="redis-redis-0:31888,redis-redis-1"
      }
      Before "setup"

      un_setup() {
        unset CURRENT_POD_HOST_IP
        unset CURRENT_POD_NAME
        unset CURRENT_SHARD_ADVERTISED_PORT
        unset CURRENT_SHARD_ADVERTISED_BUS_PORT
      }
      After "un_setup"

      It "exits with error when CURRENT_SHARD_ADVERTISED_BUS_PORT is invalid"
        When run parse_current_pod_advertised_svc_if_exist
        The status should be failure
        The stdout should include "Exiting due to error in CURRENT_SHARD_ADVERTISED_BUS_PORT."
      End
    End
  End

  Describe "get_current_comp_nodes_for_scale_out_replica()"
    Context "when cluster nodes info contains only one line"
      get_cluster_nodes_info() {
        cluster_nodes_info="4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287"
        echo "$cluster_nodes_info"
      }
      It "returns early when cluster nodes info contains only one line"
        When call get_current_comp_nodes_for_scale_out_replica "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc" "6379"
        The stdout should include "Cluster nodes info contains only one line, returning..."
      End
    End

    Context "when using advertised ports"
      get_cluster_nodes_info() {
        cluster_nodes_info="4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:31000@32000,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287"$'\n'"7381c6dca033cd1b321922508553fab869a29e 10.42.0.228:31001@32001,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc slave 4958e6dca033cd1b321922508553fab869a29d 0 1711958289570 4 connected"$'\n'"8492e6dca033cd1b321922508553fab869a29f 10.42.0.229:32222@32223,redis-shard-abc-0.redis-shard-abc-headless.default.svc master - 0 1711958289570 5 connected 1365-2729 6827-8191 12288-13652"
        echo "$cluster_nodes_info"
      }

      setup() {
        export CURRENT_SHARD_ADVERTISED_PORT="redis-shard-sxj-0:31000,redis-shard-sxj-1:31001"
        export CURRENT_SHARD_ADVERTISED_BUS_PORT="redis-shard-sxj-0:32000,redis-shard-sxj-1:32001"
        export current_comp_primary_node=()
        export current_comp_other_nodes=()
        export other_comp_primary_nodes=()
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_ADVERTISED_PORT
        unset CURRENT_SHARD_ADVERTISED_BUS_PORT
        unset cluster_nodes_info
      }
      After "un_setup"

      It "parses current component nodes correctly when using advertised ports"
        When call get_current_comp_nodes_for_scale_out_replica "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc" "6379"
        The status should be success
        The variable current_comp_primary_node should equal "10.42.0.227#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc#10.42.0.227:31000@32000"
        The variable current_comp_other_nodes should equal "10.42.0.228#redis-shard-sxj-1.redis-shard-sxj-headless.default.svc#10.42.0.228:31001@32001"
        The variable other_comp_primary_nodes should equal "10.42.0.229#redis-shard-abc-0.redis-shard-abc-headless.default.svc#10.42.0.229:32222@32223"
        The stdout should include "other_comp_other_nodes: "
      End
    End

    Context "when not using advertised ports"
      get_cluster_nodes_info() {
        cluster_nodes_info="4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287"$'\n'"7381c6dca033cd1b321922508553fab869a29e 10.42.0.228:6379@16379,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc slave 4958e6dca033cd1b321922508553fab869a29d 0 1711958289570 4 connected"$'\n'"8492e6dca033cd1b321922508553fab869a29f 10.42.0.229:6379@16379,redis-shard-abc-0.redis-shard-abc-headless.default.svc master - 0 1711958289570 5 connected 1365-2729 6827-8191 12288-13652"
        echo "$cluster_nodes_info"
      }
      setup() {
        unset CURRENT_SHARD_ADVERTISED_PORT
        unset CURRENT_SHARD_ADVERTISED_BUS_PORT
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard-sxj"
        export SERVICE_PORT="6379"
        export current_comp_primary_node=()
        export current_comp_other_nodes=()
        export other_comp_primary_nodes=()
        export other_comp_other_nodes=()
      }
      Before "setup"

      un_setup() {
        unset CURRENT_SHARD_COMPONENT_NAME
        unset SERVICE_PORT
        unset cluster_nodes_info
      }
      After "un_setup"

      It "parses current component nodes correctly when not using advertised ports"
        When call get_current_comp_nodes_for_scale_out_replica "redis-shard-sxj-0.redis-shard-sxj-headless.default.svc" "6379"
        The variable current_comp_primary_node should equal "10.42.0.227#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc:6379@16379"
        The variable current_comp_other_nodes should equal "10.42.0.228#redis-shard-sxj-1.redis-shard-sxj-headless.default.svc#redis-shard-sxj-1.redis-shard-sxj-headless.default.svc:6379@16379"
        The variable other_comp_primary_nodes should equal "10.42.0.229#redis-shard-abc-0.redis-shard-abc-headless.default.svc#redis-shard-abc-0.redis-shard-abc-headless.default.svc:6379@16379"
        The stdout should include "other_comp_other_nodes: "
      End
    End
  End
End