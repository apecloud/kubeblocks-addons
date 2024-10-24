# shellcheck shell=bash
# shellcheck disable=SC2034

# Validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "kafka_server_setup_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Kafka Server Setup Script Tests"
  # Load the scripts to be tested and dependencies
  Include ../scripts/kafka-server-setup.sh
  Include $common_library_file

  init() {
    ut_mode="true"
    mock_tls_cert_path="./certs"
    kafka_config_certs_path="./certs"
    kafka_kraft_config_path="./kraft"
    kafka_config_path="./config"
    mkdir -p $mock_tls_cert_path
    mkdir -p $kafka_config_certs_path
    mkdir -p $kafka_kraft_config_path
    mkdir -p $kafka_config_path
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file;
    rm -fr $mock_tls_cert_path;
    rm -fr $kafka_config_certs_path;
    rm -fr $kafka_kraft_config_path;
    rm -fr $kafka_config_path;
  }
  AfterAll 'cleanup'

  un_setup() {
    # Reset environment variables before each test
    unset TLS_ENABLED
    unset TLS_CERT_PATH
    unset SERVER_PROP_PATH
    unset SERVER_PROP_FILE
    unset KAFKA_CFG_PROCESS_ROLES
    unset BROKER_ADVERTISED_PORT
    unset MY_POD_NAME
    unset POD_FQDN_LIST
    unset CONTROLLER_POD_NAME_LIST
    unset KB_HOST_IP
    unset BROKER_MIN_NODE_ID
    unset KB_KAFKA_ENABLE_SASL
    unset KB_KAFKA_SASL_CONFIG_PATH
    unset KAFKA_KRAFT_CLUSTER_ID
    unset KB_KAFKA_BROKER_HEAP
    unset KB_KAFKA_CONTROLLER_HEAP
  }

  Describe "set_tls_configuration_if_needed()"
    It "skips TLS configuration if TLS_ENABLED or TLS_CERT_PATH is not set"
      un_setup
      When run set_tls_configuration_if_needed
      The output should include "TLS_ENABLED or TLS_CERT_PATH is not set, skipping TLS configuration"
      The status should be success
    End

    It "returns error if TLS_CERT_PATH is set but PEM files are missing"
      un_setup
      TLS_ENABLED="true"
      TLS_CERT_PATH="$mock_tls_cert_path"
      When run set_tls_configuration_if_needed
      The stderr should include "[tls]Couldn't find the expected PEM files! They are mandatory when encryption via TLS is enabled."
      The stdout should include "KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,CLIENT:SSL"
      The status should be failure
    End

    It "successfully sets TLS configuration when all required variables are set"
      un_setup
      TLS_ENABLED="true"
      TLS_CERT_PATH="$mock_tls_cert_path"
      # Create mock PEM files for testing
      mkdir -p $mock_tls_cert_path
      touch $mock_tls_cert_path/ca.crt
      touch $mock_tls_cert_path/tls.crt
      touch $mock_tls_cert_path/tls.key
      When run set_tls_configuration_if_needed
      The output should include "[tls]KAFKA_TLS_TRUSTSTORE_FILE=$mock_tls_cert_path/kafka.truststore.pem"
      # hack the error from openssl
      The stderr should include "Could not find private key of key from"
      The status should be success
    End

    It "fails if TLS_CERT_PATH is set but ca.crt is missing"
      un_setup
      rm -f $mock_tls_cert_path/ca.crt
      TLS_ENABLED="true"
      TLS_CERT_PATH="$mock_tls_cert_path"
      mkdir -p $mock_tls_cert_path
      touch $mock_tls_cert_path/tls.crt
      touch $mock_tls_cert_path/tls.key
      When run set_tls_configuration_if_needed
      The stderr should include "[tls]PEM_CA not provided, and auth.tls.pemChainIncluded was not true."
      The stdout should include "KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,CLIENT:SSL"
      The status should be failure
    End
  End

  Describe "convert_server_properties_to_env_var()"
    It "skips conversion if the server properties file does not exist"
      un_setup
      SERVER_PROP_FILE="non_existent_file.properties"
      When run convert_server_properties_to_env_var
      The status should be success
    End

    It "successfully converts properties to environment variables"
      un_setup
      SERVER_PROP_FILE="$kafka_config_path/server.properties"
      echo -e "broker.id=0\nlisteners=PLAINTEXT://:9092\n" > "$SERVER_PROP_FILE"
      When run convert_server_properties_to_env_var
      The output should include "[cfg]export KAFKA_CFG_BROKER_ID=0"
      The output should include "[cfg]export KAFKA_CFG_LISTENERS=PLAINTEXT://:9092"
      The status should be success
    End

    It "handles properties with no value gracefully"
      un_setup
      SERVER_PROP_FILE="$kafka_config_path/server.properties"
      echo -e "broker.id=0\nlisteners=\n" > "$SERVER_PROP_FILE"
      When run convert_server_properties_to_env_var
      The output should include "line 'listeners' has no value; skipped"
      The status should be success
    End

    It "ignores commented lines"
      un_setup
      SERVER_PROP_FILE="$kafka_config_path/server.properties"
      echo -e "# This is a comment\nbroker.id=0\n# listeners=PLAINTEXT://:9092\n" > "$SERVER_PROP_FILE"
      When run convert_server_properties_to_env_var
      The output should include "[cfg]export KAFKA_CFG_BROKER_ID=0"
      The output should not include "listeners"
      The status should be success
    End
  End

  Describe "override_sasl_configuration()"
    It "sets SASL configuration when KB_KAFKA_ENABLE_SASL is true"
      un_setup
      KB_KAFKA_ENABLE_SASL="true"
      KB_KAFKA_SASL_CONFIG_PATH="$kafka_config_path/kafka_jaas.conf"
      touch "$KB_KAFKA_SASL_CONFIG_PATH"
      When run override_sasl_configuration
      The output should include "[sasl]KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,INTERNAL:SASL_PLAINTEXT,CLIENT:SASL_PLAINTEXT"
      # mock the error from cp
      The stderr should include "cp: ./config/kafka_jaas.conf and ./config/kafka_jaas.conf are identical"
      The status should be success
    End

    It "does not set SASL configuration when KB_KAFKA_ENABLE_SASL is false"
      un_setup
      KB_KAFKA_ENABLE_SASL="false"
      When run override_sasl_configuration
      The output should not include "KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP"
      The status should be success
    End
  End

  Describe "generate_kraft_cluster_id()"
    It "sets KAFKA_KRAFT_CLUSTER_ID if provided"
      un_setup
      KAFKA_KRAFT_CLUSTER_ID="my-cluster-id"
      When run generate_kraft_cluster_id
      The output should include "KAFKA_KRAFT_CLUSTER_ID=my-cluster-id"
      The status should be success
    End

    It "truncates KAFKA_KRAFT_CLUSTER_ID to 22 characters if too long"
      un_setup
      KAFKA_KRAFT_CLUSTER_ID="this-is-a-very-long-cluster-id-that-exceeds-length"
      When run generate_kraft_cluster_id
      The output should include "export KAFKA_KRAFT_CLUSTER_ID=this-is-a-very-long-cl"
      The status should be success
    End

    It "does not set KAFKA_KRAFT_CLUSTER_ID if not provided"
      un_setup
      When run generate_kraft_cluster_id
      The output should not include "KAFKA_KRAFT_CLUSTER_ID"
      The status should be success
    End
  End
End