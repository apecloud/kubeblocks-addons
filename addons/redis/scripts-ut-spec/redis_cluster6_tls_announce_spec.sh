# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo 'redis_cluster6_tls_announce_spec.sh requires bash 4 or higher.'
  exit 0
fi

source ./utils.sh
common_library_file='./cluster6-tls-common.sh'
generate_common_library "$common_library_file"

Describe 'Redis 6 Cluster TLS announce compatibility'
  Include $common_library_file
  Include ../redis-cluster-scripts/redis-cluster-common.sh
  Include ../redis-cluster-scripts/redis-cluster6-server-start.sh

  setup() {
    ut_mode=true
    redis_real_conf=$(mktemp)
    CURRENT_POD_NAME=redis-shard-0
    CURRENT_POD_IP=10.0.0.10
    CURRENT_POD_HOST_IP=192.0.2.10
    CURRENT_SHARD_POD_FQDN_LIST=redis-shard-0.redis-headless.default.svc.cluster.local
    CURRENT_SHARD_ADVERTISED_PORT=''
    CURRENT_SHARD_ADVERTISED_BUS_PORT=''
    CURRENT_SHARD_LB_ADVERTISED_HOST=''
    REDIS_CLUSTER_HOST_NETWORK_PORT=''
    REDIS_CLUSTER_HOST_NETWORK_BUS_PORT=''
    redis_announce_port_value=''
    redis_announce_bus_port_value=''
    FIXED_POD_IP_ENABLED=false
  }
  cleanup() { rm -f "$redis_real_conf"; }
  cleanup_common() { rm -f "$common_library_file"; }
  Before 'setup'
  After 'cleanup'
  AfterAll 'cleanup_common'

  build_network_config() {
    case "$1" in
      nodeport)
        CURRENT_SHARD_ADVERTISED_PORT=redis-advertised-0:31000
        CURRENT_SHARD_ADVERTISED_BUS_PORT=redis-advertised-0:32000
        ;;
      hostnetwork)
        REDIS_CLUSTER_HOST_NETWORK_PORT=31000
        REDIS_CLUSTER_HOST_NETWORK_BUS_PORT=32000
        ;;
    esac
    parse_redis_cluster_shard_announce_addr
    build_cluster_announce_info
    build_redis_tls_config
  }

  Context 'external network modes'
  Parameters
    '6.0.20' 'nodeport'
    '6.0.20' 'hostnetwork'
  End
  It 'uses the Redis 6.0 TLS-aware announce-port for external networks'
    SERVICE_VERSION=$1
    TLS_ENABLED=true
    When call build_network_config "$2"
    The status should be success
    The output should include 'to announce'
    The contents of file "$redis_real_conf" should include 'cluster-announce-ip 192.0.2.10'
    The contents of file "$redis_real_conf" should include 'cluster-announce-port 31000'
    The contents of file "$redis_real_conf" should include 'cluster-announce-bus-port 32000'
    The contents of file "$redis_real_conf" should include 'tls-cluster yes'
    The contents of file "$redis_real_conf" should include 'port 0'
    The contents of file "$redis_real_conf" should not include 'cluster-announce-tls-port'
    The contents of file "$redis_real_conf" should not include 'cluster-announce-port 0'
  End
  End

  It 'keeps the separate TLS announce port for Redis 6.2'
    SERVICE_VERSION=6.2.14
    TLS_ENABLED=true
    When call build_network_config nodeport
    The status should be success
    The output should include 'to announce'
    The contents of file "$redis_real_conf" should include 'cluster-announce-tls-port 31000'
    The contents of file "$redis_real_conf" should include 'cluster-announce-port 0'
  End

  It 'keeps default-network TLS free of external announce ports'
    SERVICE_VERSION=6.0.20
    TLS_ENABLED=true
    When call build_network_config default
    The status should be success
    The output should include 'to announce'
    The contents of file "$redis_real_conf" should include 'cluster-announce-ip 10.0.0.10'
    The contents of file "$redis_real_conf" should include 'tls-cluster yes'
    The contents of file "$redis_real_conf" should not include 'cluster-announce-port'
    The contents of file "$redis_real_conf" should not include 'cluster-announce-tls-port'
  End

  It 'preserves non-TLS external announce ports'
    SERVICE_VERSION=6.0.20
    TLS_ENABLED=false
    When call build_network_config hostnetwork
    The status should be success
    The output should include 'to announce'
    The contents of file "$redis_real_conf" should include 'cluster-announce-port 31000'
    The contents of file "$redis_real_conf" should not include 'tls-cluster'
    The contents of file "$redis_real_conf" should not include 'cluster-announce-tls-port'
  End
End
