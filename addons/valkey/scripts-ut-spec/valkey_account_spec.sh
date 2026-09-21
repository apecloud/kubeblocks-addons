# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_account_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

Describe "Valkey Account Script Tests"

  Include ../scripts/valkey-account.sh

  # Mock valkey-cli.  Calls are appended to $CLI_LOG (a file: the script invokes
  # it inside command substitutions, so only a file survives the subshell).
  valkey-cli() {
    printf '%s\n' "$*" >> "${CLI_LOG}"
    case "$*" in
      *"ACL SAVE"*) printf 'OK\n' ;;
      *) printf '%s\n' "${MOCK_ACL_OUTPUT:-OK}" ;;
    esac
  }

  setup() {
    CLI_LOG="${PWD}/valkey-cli-account-mock.log"
    : > "${CLI_LOG}"
    unset SERVICE_PORT VALKEY_DEFAULT_PASSWORD TLS_ENABLED
    export ACL_COMMAND="ACL SETUSER alice-sen on ~* &* +@all"
    export VALKEY_DEFAULT_USER="default"
    export VALKEY_DEFAULT_PASSWORD="admin_password"
    export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless,valkey-1.valkey-headless"
    export REPLICAS="2"
    unset MOCK_ACL_OUTPUT
  }
  BeforeAll "setup"

  cleanup() {
    unset ACL_COMMAND VALKEY_DEFAULT_USER VALKEY_DEFAULT_PASSWORD
    unset VALKEY_POD_FQDN_LIST REPLICAS SERVICE_PORT MOCK_ACL_OUTPUT TLS_ENABLED
    rm -f "${CLI_LOG}"
  }
  AfterAll "cleanup"

  # Run the action in a subshell (it exits through create_post_check) and print
  # the recorded calls afterwards.
  run_account_and_show_calls() {
    ( do_acl_command "${VALKEY_POD_FQDN_LIST}" "${VALKEY_DEFAULT_USER}" "${VALKEY_DEFAULT_PASSWORD}" )
    echo "── recorded cli calls ──"
    cat "${CLI_LOG}"
  }

  run_account_exit_status() {
    local rc=0
    ( do_acl_command "${VALKEY_POD_FQDN_LIST}" "${VALKEY_DEFAULT_USER}" "${VALKEY_DEFAULT_PASSWORD}" ) \
      >/dev/null 2>&1 || rc=$?
    printf '%s' "${rc}"
  }

  Describe "env_pre_check()"
    It "rejects an empty ACL_COMMAND"
      env_pre_check_exit_status() {
        local rc=0
        ( unset ACL_COMMAND; env_pre_check ) >/dev/null 2>&1 || rc=$?
        printf '%s' "${rc}"
      }
      When call env_pre_check_exit_status
      The status should be success
      The stdout should eq "1"
    End

    It "rejects an empty pod list"
      env_pre_check_pod_list_exit_status() {
        local rc=0
        ( unset VALKEY_POD_FQDN_LIST; env_pre_check ) >/dev/null 2>&1 || rc=$?
        printf '%s' "${rc}"
      }
      When call env_pre_check_pod_list_exit_status
      The status should be success
      The stdout should eq "1"
    End

    It "passes with the required env set"
      When call env_pre_check
      The status should be success
    End
  End

  Describe "do_acl_command()"
    It "runs the ACL command and ACL SAVE on every host and passes the post check"
      When call run_account_and_show_calls
      The status should be success
      The stdout should include "DO ACL COMMAND FOR HOST: valkey-0.valkey-headless"
      The stdout should include "DO ACL COMMAND FOR HOST: valkey-1.valkey-headless"
      The stdout should include "DO ACL SAVE FOR HOST: valkey-1.valkey-headless"
      The stdout should include "DO ACL COMMAND FOR ALL 2 HOSTS SUCCESS"
      The stdout should include "--user default"
      The stdout should include "ACL SETUSER alice-sen on ~* &* +@all"
      The stdout should include "ACL SAVE"
    End

    It "uses the port embedded in a host:port entry"
      export VALKEY_POD_FQDN_LIST="10.0.0.1:31666"
      export REPLICAS="1"
      When call run_account_and_show_calls
      The status should be success
      The stdout should include "-h 10.0.0.1 -p 31666"
    End

    It "fails when a pod answers with an ERR"
      export MOCK_ACL_OUTPUT="ERR User alice-sen already exists"
      When call run_account_exit_status
      The status should be success
      The stdout should eq "1"
    End

    It "fails the post check when fewer hosts answered than REPLICAS"
      export REPLICAS="3"
      When call run_account_exit_status
      The status should be success
      The stdout should eq "1"
    End

    It "defaults REPLICAS to the host count when it is not provided"
      unset REPLICAS
      When call run_account_and_show_calls
      The status should be success
      The stdout should include "REPLICAS is not set"
      The stdout should include "DO ACL COMMAND FOR ALL 2 HOSTS SUCCESS"
    End

    It "adds no TLS flags when TLS_ENABLED is unset"
      When call run_account_and_show_calls
      The status should be success
      The stdout should not include "--tls"
    End

    It "adds --tls --insecure when TLS_ENABLED is true (redis-style switch)"
      export TLS_ENABLED="true"
      When call run_account_and_show_calls
      The status should be success
      The stdout should include "--tls --insecure"
      The stdout should include "DO ACL COMMAND FOR ALL 2 HOSTS SUCCESS"
    End
  End
End
