# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "start_broker_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Pulsar Start Broker Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/start-broker.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "extract_ordinal_from_object_name()"
    It "extracts the ordinal from object name"
      When call extract_ordinal_from_object_name "pod-1"
      The output should equal "1"
    End
  End

  Describe "parse_advertised_svc_if_exist()"
    It "parses advertised service if it exists"
      POD_NAME="pod-1"
      ADVERTISED_PORT_PULSAR="pod-svc-0:8080,pod-svc-1:8081"

      When run parse_advertised_svc_if_exist "$ADVERTISED_PORT_PULSAR"
      The output should include "Found matching svcName and port for podName 'pod-1'"
      The status should be success
    End

    It "ignores if no advertised ports are provided"
      When run parse_advertised_svc_if_exist ""
      The output should include "Ignoring."
      The status should be success
    End

    It "exits with an error if no matching service is found"
      POD_NAME="pod-1"
      ADVERTISED_PORT_PULSAR="pod-svc-2:8080,pod-svc-3:8081"

      When run parse_advertised_svc_if_exist "$ADVERTISED_PORT_PULSAR"
      The output should include "Error: No matching svcName and port found for podName 'pod-1'"
      The status should be failure
    End
  End

  Describe "initialize_nodeport_config()"
    It "initializes NodePort configuration"
      POD_NAME="pod-1"
      ADVERTISED_PORT_PULSAR="pod-svc-1:8080"
      ADVERTISED_PORT_KAFKA="pod-svc-1:9092"
      POD_HOST_IP="192.168.1.1"

      When run initialize_nodeport_config
      The output should include "set PULSAR_PREFIX_advertisedListeners=cluster:pulsar://192.168.1.1:8080"
      The output should include "set PULSAR_PREFIX_kafkaAdvertisedListeners=CLIENT://192.168.1.1:9092"
      The status should be success
    End

    It "handles missing service ports gracefully"
      POD_NAME="pod-1"
      ADVERTISED_PORT_PULSAR="pod-svc-2:8080"
      ADVERTISED_PORT_KAFKA="pod-svc-3:9092"

      When run initialize_nodeport_config
      The output should include "Error: No matching svcName and port found for podName 'pod-1'"
      The status should be failure
    End
  End

  Describe "initialize_loadbalancer_config()"
    It "selects the current broker LB IP and uses the Service port"
      POD_NAME="broker-1"
      ADVERTISED_HOST="broker-advertised-listener-0:192.0.2.10,broker-advertised-listener-1:192.0.2.11"
      ADVERTISED_PORT_PULSAR="broker-advertised-listener-1:30650"

      When call initialize_loadbalancer_config
      The variable PULSAR_PREFIX_advertisedListeners should equal "cluster:pulsar://192.0.2.11:6650"
      The status should be success
    End

    It "supports LB hostnames"
      POD_NAME="broker-0"
      ADVERTISED_HOST="broker-advertised-listener-0:broker.example.com"

      When call initialize_loadbalancer_config
      The variable PULSAR_PREFIX_advertisedListeners should equal "cluster:pulsar://broker.example.com:6650"
      The status should be success
    End

    It "brackets IPv6 LB addresses"
      POD_NAME="broker-0"
      ADVERTISED_HOST="broker-advertised-listener-0:2001:db8::1"

      When call initialize_loadbalancer_config
      The variable PULSAR_PREFIX_advertisedListeners should equal "cluster:pulsar://[2001:db8::1]:6650"
      The status should be success
    End

    It "fails when the current broker has no LB address"
      POD_NAME="broker-1"
      ADVERTISED_HOST="broker-advertised-listener-0:192.0.2.10"

      When run initialize_loadbalancer_config
      The output should include "No LoadBalancer address found"
      The status should be failure
    End

    It "fails when LB addresses are empty"
      POD_NAME="broker-0"
      ADVERTISED_HOST=""

      When run initialize_loadbalancer_config
      The output should include "No LoadBalancer address found"
      The status should be failure
    End
  End

  Describe "merge_configuration_files()"
    It "merges configuration files successfully"
      /kb-scripts/merge_pulsar_config.py() {
        return 0  # Simulate successful merge
      }

      bin/apply-config-from-env.py() {
        return 0  # Simulate successful application
      }

      When run merge_configuration_files
      The status should be success
    End
  End
End