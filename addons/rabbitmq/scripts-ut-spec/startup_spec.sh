# shellcheck shell=sh

Describe "RabbitMQ Startup Script Tests"
  Include ../scripts/startup.sh

  Describe "sync_default_user_password"
    BeforeEach "setup_default_user_env"

    setup_default_user_env() {
      RABBITMQ_DEFAULT_USER="root"
      RABBITMQ_DEFAULT_PASS="rotated-secret"
      RABBITMQ_PASSWORD_SYNC_ATTEMPTS=
      RABBITMQ_PASSWORD_SYNC_INTERVAL_SECONDS=0
      MOCK_BIN="$(mktemp -d)"
      MOCK_STATE="$(mktemp -d)"
      PATH="${MOCK_BIN}:${PATH}"
      export PATH MOCK_STATE
      cat > "${MOCK_BIN}/rabbitmq-diagnostics" <<'EOF'
#!/bin/sh
exit 0
EOF
      chmod +x "${MOCK_BIN}/rabbitmq-diagnostics"
      cat > "${MOCK_BIN}/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
      chmod +x "${MOCK_BIN}/sleep"
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

  Describe "sync_default_user_password_until_ready"
    BeforeEach "setup_password_sync_retry_env"

    setup_password_sync_retry_env() {
      RABBITMQ_DEFAULT_USER="root"
      RABBITMQ_DEFAULT_PASS="rotated-secret"
      RABBITMQ_PASSWORD_SYNC_ATTEMPTS=
      RABBITMQ_PASSWORD_SYNC_INTERVAL_SECONDS=0
      MOCK_BIN="$(mktemp -d)"
      MOCK_STATE="$(mktemp -d)"
      PATH="${MOCK_BIN}:${PATH}"
      export PATH MOCK_STATE
      cat > "${MOCK_BIN}/rabbitmq-diagnostics" <<'EOF'
#!/bin/sh
exit 0
EOF
      chmod +x "${MOCK_BIN}/rabbitmq-diagnostics"
      cat > "${MOCK_BIN}/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
      chmod +x "${MOCK_BIN}/sleep"
    }

    It "keeps retrying by default until the existing user can be synchronized"
      cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
        count_file="${MOCK_STATE}/list_users_count"
        case "$*" in
          *"authenticate_user root rotated-secret"*) exit 1 ;;
          *"list_users"*)
            count="$(cat "$count_file" 2>/dev/null || echo 0)"
            count=$((count + 1))
            echo "$count" > "$count_file"
            if [ "$count" -ge 3 ]; then
              echo "root [administrator]"
            else
              echo "guest [administrator]"
            fi
            exit 0
            ;;
          *"change_password root rotated-secret"*) exit 0 ;;
          *) exit 1 ;;
        esac
EOF
      chmod +x "${MOCK_BIN}/rabbitmqctl"

      When call sync_default_user_password_until_ready
      The output should include "password synchronized"
      The output should not include "rotated-secret"
      The status should be success
    End

    It "only gives up when an explicit attempt limit is configured"
      RABBITMQ_PASSWORD_SYNC_ATTEMPTS=2
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

      When call sync_default_user_password_until_ready
      The error should include "did not complete after 2 attempts"
      The error should not include "rotated-secret"
      The status should be failure
    End
  End
End
