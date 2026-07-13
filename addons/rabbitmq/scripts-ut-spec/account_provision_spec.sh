# shellcheck shell=sh

Describe "RabbitMQ managed account provisioning"
  account_script="../scripts/account-provision.sh"
  cmpd_file="../templates/cmpd.yaml"

  BeforeEach "setup_account_env"

  setup_account_env() {
    KB_ACCOUNT_NAME="root"
    KB_ACCOUNT_PASSWORD="rotated-secret"
    KB_ACCOUNT_STATEMENT='rabbitmqctl change_password ${KB_ACCOUNT_NAME} ${KB_ACCOUNT_PASSWORD}'
    MOCK_BIN="$(mktemp -d)"
    MOCK_STATE="$(mktemp -d)"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH MOCK_STATE KB_ACCOUNT_NAME KB_ACCOUNT_PASSWORD KB_ACCOUNT_STATEMENT
  }

  AfterEach "cleanup_account_env"

  cleanup_account_env() {
    rm -rf "${MOCK_BIN}" "${MOCK_STATE}"
  }

  It "declares the controller-managed update statement and action"
    When call grep -E 'update: rabbitmqctl change_password \$\{KB_ACCOUNT_NAME\} \$\{KB_ACCOUNT_PASSWORD\}|accountProvision:|/scripts/account-provision.sh|targetPodSelector: Any' "${cmpd_file}"
    The status should be success
    The line 1 should include 'update: rabbitmqctl change_password ${KB_ACCOUNT_NAME} ${KB_ACCOUNT_PASSWORD}'
    The output should include "accountProvision:"
    The output should include "/scripts/account-provision.sh"
    The output should include "targetPodSelector: Any"
  End

  It "changes and verifies the password before reporting success"
    cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
case "$*" in
  *"change_password root rotated-secret"*) printf "change\n" >> "${MOCK_STATE}/calls"; exit 0 ;;
  *"authenticate_user root rotated-secret"*) printf "authenticate\n" >> "${MOCK_STATE}/calls"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
    chmod +x "${MOCK_BIN}/rabbitmqctl"

    When call sh "${account_script}"
    The status should be success
    The output should include "synchronized"
    The output should not include "rotated-secret"
    The contents of file "${MOCK_STATE}/calls" should include "change"
    The contents of file "${MOCK_STATE}/calls" should include "authenticate"
  End

  It "fails closed when change_password fails"
    cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
exit 17
EOF
    chmod +x "${MOCK_BIN}/rabbitmqctl"

    When call sh "${account_script}"
    The status should be failure
    The output should not include "rotated-secret"
  End

  It "fails closed when the new password cannot authenticate"
    cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
case "$*" in
  *"change_password root rotated-secret"*) exit 0 ;;
  *"authenticate_user root rotated-secret"*) exit 19 ;;
  *) exit 1 ;;
esac
EOF
    chmod +x "${MOCK_BIN}/rabbitmqctl"

    When call sh "${account_script}"
    The status should be failure
    The output should not include "rotated-secret"
  End

  It "rejects unsupported account statements"
    KB_ACCOUNT_STATEMENT="create-user"
    export KB_ACCOUNT_STATEMENT
    cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "${MOCK_BIN}/rabbitmqctl"

    When call sh "${account_script}"
    The status should be failure
    The error should include "unsupported account statement"
    The error should not include "rotated-secret"
  End
End
