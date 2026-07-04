# shellcheck shell=sh

Describe "RabbitMQ Startup Script Tests"
  Include ../scripts/startup.sh

  Describe "sync_default_user_password"
    BeforeEach "setup_default_user_env"

    setup_default_user_env() {
      RABBITMQ_DEFAULT_USER="root"
      RABBITMQ_DEFAULT_PASS="rotated-secret"
      MOCK_BIN="$(mktemp -d)"
      PATH="${MOCK_BIN}:${PATH}"
      export PATH
      cat > "${MOCK_BIN}/rabbitmq-diagnostics" <<'EOF'
#!/bin/sh
exit 0
EOF
      chmod +x "${MOCK_BIN}/rabbitmq-diagnostics"
    }

    It "succeeds when the current password already authenticates"
      cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
        case "$*" in
          *"authenticate_user root rotated-secret"*) exit 0 ;;
          *) exit 1 ;;
        esac
EOF
      chmod +x "${MOCK_BIN}/rabbitmqctl"

      When call sync_default_user_password
      The output should include "already synchronized"
      The output should not include "rotated-secret"
      The status should be success
    End

    It "changes the existing user password when the current password is rejected"
      cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
        case "$*" in
          *"authenticate_user root rotated-secret"*) exit 1 ;;
          *"list_users"*) echo "root [administrator]"; exit 0 ;;
          *"change_password root rotated-secret"*) exit 0 ;;
          *) exit 1 ;;
        esac
EOF
      chmod +x "${MOCK_BIN}/rabbitmqctl"

      When call sync_default_user_password
      The output should include "password synchronized"
      The output should not include "rotated-secret"
      The status should be success
    End

    It "fails without changing anything when the user does not exist yet"
      cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
        case "$*" in
          *"authenticate_user root rotated-secret"*) exit 1 ;;
          *"list_users"*) echo "guest [administrator]"; exit 0 ;;
          *"change_password"*) exit 1 ;;
          *) exit 1 ;;
        esac
EOF
      chmod +x "${MOCK_BIN}/rabbitmqctl"

      When call sync_default_user_password
      The status should be failure
    End
  End
End
