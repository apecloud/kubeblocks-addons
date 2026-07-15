# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "common_spec.sh skips cases because bash 4 or higher is not installed."
  exit 0
fi

Describe "Kafka common script tests"
  Include ../scripts/common.sh

  setup() {
    kafka_config_path="$(mktemp -d)"
    KAFKA_ADMIN_USER="admin"
    KAFKA_ADMIN_PASSWORD="admin-password"
    KAFKA_CLIENT_USER="client"
    KAFKA_CLIENT_PASSWORD="client-password"
    KB_KAFKA_SASL_ENABLE="true"
    KB_KAFKA_ENABLE_SASL_SCRAM="false"
    KB_KAFKA_SASL_USE_KB_BUILTIN="true"
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
    The path "$kafka_config_path/kafka_jaas.conf" should include \
      'user_admin="admin-password"'
    The path "$kafka_config_path/kafka_jaas.conf" should include \
      'user_client="client-password"'
  End
End
