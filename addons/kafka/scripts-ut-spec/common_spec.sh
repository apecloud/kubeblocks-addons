# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "common_spec.sh skips cases because bash 4 or higher is not installed."
  exit 0
fi

Describe "Kafka common script tests"
  Include ../scripts/common.sh

  setup() {
    export kafka_config_path="$(mktemp -d)"
    export KAFKA_ADMIN_USER="admin"
    export KAFKA_ADMIN_PASSWORD="admin-password"
    export KAFKA_CLIENT_USER="client"
    export KAFKA_CLIENT_PASSWORD="client-password"
    export KB_KAFKA_SASL_ENABLE="true"
    export KB_KAFKA_ENABLE_SASL_SCRAM="false"
    export KB_KAFKA_SASL_USE_KB_BUILTIN="true"
  }

  cleanup() {
    rm -rf "$kafka_config_path"
  }

  BeforeEach "setup"
  AfterEach "cleanup"

  It "writes PLAIN server user entries for the managed admin and client"
    When call build_server_jaas_config \
      "org.apache.kafka.common.security.plain.PlainLoginModule required"
    The status should be success
    The output should include "[sasl] write jaas config"
    The contents of file "$kafka_config_path/kafka_jaas.conf" should include \
      'user_admin="admin-password"'
    The contents of file "$kafka_config_path/kafka_jaas.conf" should include \
      'user_client="client-password"'
  End
End
