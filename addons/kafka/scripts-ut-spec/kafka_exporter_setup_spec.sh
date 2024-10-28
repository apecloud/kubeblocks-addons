# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "kafka_exporter_setup_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Kafka Exporter Setup Script Tests"
  # Load the scripts to be tested and dependencies
  Include ../scripts/kafka-exporter-setup.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  un_setup() {
    # Reset environment variables before each test
    unset BROKER_POD_FQDN_LIST
    unset COMBINE_POD_FQDN_LIST
    unset TLS_ENABLED
  }

  Describe "generate_kafka_servers()"
    It "returns an error if both BROKER_POD_FQDN_LIST and COMBINE_POD_FQDN_LIST are unset"
      un_setup
      When run generate_kafka_servers
      The stderr should include "Error: BROKER_POD_FQDN_LIST and COMBINE_POD_FQDN_LIST environment variable is not set"
      The status should be failure
    End

    It "generates server list from COMBINE_POD_FQDN_LIST"
      un_setup
      COMBINE_POD_FQDN_LIST="kafka-kafka-0.kafka-kafka-headless.default.svc.cluster.local,kafka-kafka-1.kafka-kafka-headless.default.svc.cluster.local"
      When run generate_kafka_servers
      The output should equal " --kafka.server=kafka-kafka-0.kafka-kafka-headless.default.svc.cluster.local:9094 --kafka.server=kafka-kafka-1.kafka-kafka-headless.default.svc.cluster.local:9094"
      The status should be success
    End

    It "generates server list from BROKER_POD_FQDN_LIST if COMBINE_POD_FQDN_LIST is unset"
      un_setup
      BROKER_POD_FQDN_LIST="kafka-kafka-0.kafka-kafka-headless.default.svc.cluster.local,kafka-kafka-1.kafka-kafka-headless.default.svc.cluster.local"
      When run generate_kafka_servers
      The output should equal " --kafka.server=kafka-kafka-0.kafka-kafka-headless.default.svc.cluster.local:9094 --kafka.server=kafka-kafka-1.kafka-kafka-headless.default.svc.cluster.local:9094"
      The status should be success
    End
  End

  Describe "get_start_kafka_exporter_cmd()"
    It "returns failure if generate_kafka_servers fails"
      generate_kafka_servers() {
        return 1
      }
      When run get_start_kafka_exporter_cmd
      The stderr should include "failed to generate kafka servers. Exiting."
      The status should be failure
    End

    It "returns the correct command with TLS enabled"
      un_setup
      COMBINE_POD_FQDN_LIST="combine1.example.com"
      TLS_ENABLED="true"
      When run get_start_kafka_exporter_cmd
      The output should include "kafka_exporter --web.listen-address=:9308 --tls.enabled  --kafka.server=combine1.example.com:9094"
      The stderr should include "TLS_ENABLED is set to true, start kafka_exporter with tls enabled."
      The status should be success
    End

    It "returns the correct command with TLS disabled"
      un_setup
      BROKER_POD_FQDN_LIST="broker1.example.com"
      TLS_ENABLED=""
      When run get_start_kafka_exporter_cmd
      The output should include "kafka_exporter --web.listen-address=:9308  --kafka.server=broker1.example.com:9094"
      The stderr should include "TLS_ENABLED is not set, start kafka_exporter with tls disabled."
      The status should be success
    End
  End
End