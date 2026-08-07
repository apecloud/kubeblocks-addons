# shellcheck shell=sh disable=SC2016

Describe "RabbitMQ managed account provisioning"
  account_script="../scripts/account-provision.sh"
  addon_chart_file="../Chart.yaml"
  cluster_chart_file="../../../addons-cluster/rabbitmq/Chart.yaml"
  cluster_template_file="../../../addons-cluster/rabbitmq/templates/cluster.yaml"
  cmpd_file="../templates/cmpd.yaml"
  cmpv_file="../templates/cmpv.yaml"

  BeforeEach "setup_account_env"

  setup_account_env() {
    KB_ACCOUNT_NAME="root"
    KB_ACCOUNT_PASSWORD="rotated-secret"
    KB_ACCOUNT_STATEMENT='rabbitmqctl change_password ${KB_ACCOUNT_NAME} ${KB_ACCOUNT_PASSWORD}'
    RABBITMQ_NODENAME="rabbit@rabbitmq-0.rabbitmq-headless.rabbitmq-test"
    MOCK_BIN="$(mktemp -d)"
    MOCK_STATE="$(mktemp -d)"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH MOCK_STATE KB_ACCOUNT_NAME KB_ACCOUNT_PASSWORD KB_ACCOUNT_STATEMENT RABBITMQ_NODENAME
  }

  AfterEach "cleanup_account_env"

  cleanup_account_env() {
    rm -rf "${MOCK_BIN}" "${MOCK_STATE}"
  }

  It "routes first reconciliation and later rotations through the managed action"
    When call grep -E 'initAccount: false|create: rabbitmqctl change_password \$\{KB_ACCOUNT_NAME\} \$\{KB_ACCOUNT_PASSWORD\}|update: rabbitmqctl change_password \$\{KB_ACCOUNT_NAME\} \$\{KB_ACCOUNT_PASSWORD\}|accountProvision:|/scripts/account-provision.sh|targetPodSelector: Any|name: RABBITMQ_NODENAME' "${cmpd_file}"
    The status should be success
    The line 1 should include "initAccount: false"
    The line 2 should include 'create: rabbitmqctl change_password ${KB_ACCOUNT_NAME} ${KB_ACCOUNT_PASSWORD}'
    The line 3 should include 'update: rabbitmqctl change_password ${KB_ACCOUNT_NAME} ${KB_ACCOUNT_PASSWORD}'
    The output should include "accountProvision:"
    The output should include "/scripts/account-provision.sh"
    The output should include "targetPodSelector: Any"
    The output should include "name: RABBITMQ_NODENAME"
  End

  It "maps the account action to the version-matched RabbitMQ image"
    When call grep -F 'accountProvision: {{ $imageRegistry }}/{{ $.Values.image.repository }}:{{ index . 2 }}' "${cmpv_file}"
    The status should be success
    The output should include "accountProvision:"
  End

  It "delivers the immutable account contract through a new ComponentDefinition"
    addon_version=$(awk '$1 == "version:" { print $2; exit }' "${addon_chart_file}")
    cluster_version=$(awk '$1 == "version:" { print $2; exit }' "${cluster_chart_file}")

    When call sh -c '
      test "$1" = "1.2.0-alpha.2" &&
      test "$2" = "$1" &&
      grep -Fq "{{ include \"rabbitmq.cmpdName\" . }}" "$3" &&
      grep -Fq "componentDef: rabbitmq-{{ .Chart.Version }}" "$4" &&
      ! grep -Fq "apps.kubeblocks.io/skip-immutable-check" "$3"
    ' sh "${addon_version}" "${cluster_version}" "${cmpd_file}" "${cluster_template_file}"
    The status should be success
  End

  It "keeps the root secret injected into RabbitMQ bootstrap"
    When call grep -A13 -- '- name: RABBITMQ_DEFAULT_USER' "${cmpd_file}"
    The status should be success
    The output should include "credentialVarRef:"
    The output should include "name: root"
    The output should include "- name: RABBITMQ_DEFAULT_PASS"
  End

  It "changes and verifies the password before reporting success"
    cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
case "$*" in
  *"--longnames -q -n rabbit@rabbitmq-0.rabbitmq-headless.rabbitmq-test change_password root rotated-secret"*) printf "change\n" >> "${MOCK_STATE}/calls"; exit 0 ;;
  *"--longnames -q -n rabbit@rabbitmq-0.rabbitmq-headless.rabbitmq-test authenticate_user root rotated-secret"*) printf "authenticate\n" >> "${MOCK_STATE}/calls"; exit 0 ;;
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
    The error should include "password update failed"
    The output should not include "rotated-secret"
  End

  It "fails closed when the new password cannot authenticate"
    cat > "${MOCK_BIN}/rabbitmqctl" <<'EOF'
#!/bin/sh
case "$*" in
  *"--longnames -q -n rabbit@rabbitmq-0.rabbitmq-headless.rabbitmq-test change_password root rotated-secret"*) exit 0 ;;
  *"--longnames -q -n rabbit@rabbitmq-0.rabbitmq-headless.rabbitmq-test authenticate_user root rotated-secret"*) exit 19 ;;
  *) exit 1 ;;
esac
EOF
    chmod +x "${MOCK_BIN}/rabbitmqctl"

    When call sh "${account_script}"
    The status should be failure
    The error should include "password verification failed"
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

  It "fails before invoking RabbitMQ when the target node identity is missing"
    unset RABBITMQ_NODENAME
    export RABBITMQ_NODENAME

    When call sh "${account_script}"
    The status should be failure
    The error should include "RABBITMQ_NODENAME is required"
    The error should not include "rotated-secret"
  End
End
