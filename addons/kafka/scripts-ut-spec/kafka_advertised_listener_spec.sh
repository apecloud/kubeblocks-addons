# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "kafka_advertised_listener_spec.sh requires bash 4 or higher."
  exit 0
fi

source ./utils.sh
common_library_file="./advertised-common.sh"
generate_common_library "$common_library_file"

Describe "Kafka per-broker advertised listeners"
  Include "$common_library_file"

  Parameters
    kafka-server-setup.sh
    kafka-27-server-setup.sh
  End

  setup() {
    ut_mode="true"
    KAFKA_CFG_PROCESS_ROLES="broker"
    KAFKA_CFG_METADATA_LOG_DIR="./unused-metadata"
    MY_POD_NAME="kafka-broker-1"
    MY_POD_HOST_IP="192.0.2.10"
    MY_POD_IP="10.0.0.10"
    POD_FQDN_LIST="kafka-broker-1.kafka.svc.cluster.local"
    CONTROLLER_POD_NAME_LIST=""
    BROKER_MIN_NODE_ID=0
    KB_BROKER_DIRECT_POD_ACCESS="false"
    BROKER_ADVERTISED_SERVICE_TYPE="LoadBalancer"
    BROKER_ADVERTISED_PORT="kafka-advertised-listener-0:30001,kafka-advertised-listener-1:30002"
    BROKER_ADVERTISED_HOST="kafka-advertised-listener-0:192.0.2.20,kafka-advertised-listener-1:192.0.2.21"
    unset KAFKA_CFG_ADVERTISED_LISTENERS
  }
  BeforeEach setup
  run_metadata() {
    __SOURCED__="$1" source "../scripts/$1"
    set_cfg_metadata
  }
  cleanup() { rm -f "$common_library_file"; }
  AfterAll cleanup

  It "uses the matching LB IP and service port instead of the allocated nodePort"
    When run run_metadata "$1"
    The status should be success
    The output should include "INTERNAL://kafka-broker-1.kafka.svc.cluster.local:9094,CLIENT://192.0.2.21:9092"
  End

  It "supports LB without nodePort allocation"
    BROKER_ADVERTISED_PORT="kafka-advertised-listener-1:9092"
    When run run_metadata "$1"
    The status should be success
    The output should include "CLIENT://192.0.2.21:9092"
  End

  It "advertises an LB hostname"
    BROKER_ADVERTISED_HOST="kafka-advertised-listener-1:broker-1.example.com"
    When run run_metadata "$1"
    The status should be success
    The output should include "CLIENT://broker-1.example.com:9092"
  End

  It "preserves and brackets an IPv6 ingress"
    BROKER_ADVERTISED_HOST="kafka-advertised-listener-1:2001:db8::21"
    When run run_metadata "$1"
    The status should be success
    The output should include "CLIENT://[2001:db8::21]:9092"
  End

  It "fails when this broker has no ingress instead of using another broker's LB"
    BROKER_ADVERTISED_HOST="kafka-advertised-listener-0:192.0.2.20"
    When run run_metadata "$1"
    The status should be failure
    The stdout should include "Found matching svcName"
    The stderr should include "LoadBalancer ingress not found for service 'kafka-advertised-listener-1'"
    The stdout should not include "KAFKA_CFG_ADVERTISED_LISTENERS="
  End

  It "fails for an empty ingress"
    BROKER_ADVERTISED_HOST="kafka-advertised-listener-1:"
    When run run_metadata "$1"
    The status should be failure
    The stdout should include "Found matching svcName"
    The stderr should include "LoadBalancer ingress not found"
  End

  It "fails when LB port references are unavailable"
    BROKER_ADVERTISED_PORT=""
    When run run_metadata "$1"
    The status should be failure
    The stderr should include "LoadBalancer advertised service ports are missing"
  End

  It "preserves NodePort addresses"
    BROKER_ADVERTISED_SERVICE_TYPE="NodePort"
    BROKER_ADVERTISED_HOST="kafka-advertised-listener-0,kafka-advertised-listener-1"
    When run run_metadata "$1"
    The status should be success
    The output should include "CLIENT://192.0.2.10:30002"
  End

  It "keeps ClusterIP on the headless endpoint"
    BROKER_ADVERTISED_SERVICE_TYPE="ClusterIP"
    BROKER_ADVERTISED_PORT="kafka-advertised-listener-1:9092"
    When run run_metadata "$1"
    The status should be success
    The output should include "CLIENT://kafka-broker-1.kafka.svc.cluster.local:9092"
  End

  It "preserves direct Pod access"
    KB_BROKER_DIRECT_POD_ACCESS="true"
    When run run_metadata "$1"
    The status should be success
    The output should include "CLIENT://10.0.0.10:9092"
  End

  It "preserves legacy NodePort variables without the service type"
    unset BROKER_ADVERTISED_SERVICE_TYPE
    When run run_metadata "$1"
    The status should be success
    The output should include "CLIENT://192.0.2.10:30002"
  End

  It "also configures combined KRaft listeners"
    KAFKA_CFG_PROCESS_ROLES="broker,controller"
    When run run_metadata "$1"
    The status should be success
    The output should include "CLIENT://192.0.2.21:9092"
  End
End
