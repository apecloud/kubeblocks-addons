# shellcheck shell=sh

Describe "doltdb-sql.sh"
  setup() {
    export TEST_DIR
    TEST_DIR="$(mktemp -d)"
    export PATH="${TEST_DIR}:$PATH"
    export DOLT_ROOT_PASSWORD="test-password"
    export TLS_MOUNT_PATH="/etc/pki/tls"

    cat >"${TEST_DIR}/dolt" <<'EOF'
#!/bin/sh
printf 'SSL_CERT_FILE=%s\n' "${SSL_CERT_FILE:-}"
printf 'ARGS=%s\n' "$*"
EOF
    chmod +x "${TEST_DIR}/dolt"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    unset DOLT_ROOT_PASSWORD TLS_ENABLED TLS_MOUNT_PATH DOLT_TLS_CA_FILE DOLT_NO_DATABASE
  }
  AfterEach "cleanup"

  It "trusts the mounted KubeBlocks CA when TLS is enabled"
    export TLS_ENABLED="true"
    export DOLT_NO_DATABASE="true"

    When run sh ../scripts/doltdb-sql.sh "SELECT 1"
    The status should be success
    The output should include "SSL_CERT_FILE=/etc/pki/tls/ca.crt"
    The output should not include "--no-tls"
  End

  It "keeps plaintext mode explicit when TLS is disabled"
    export TLS_ENABLED="false"
    export DOLT_NO_DATABASE="true"

    When run sh ../scripts/doltdb-sql.sh "SELECT 1"
    The status should be success
    The output should include "SSL_CERT_FILE="
    The output should include "--no-tls"
  End
End
