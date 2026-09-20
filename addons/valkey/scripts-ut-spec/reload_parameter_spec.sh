# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "reload_parameter_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Valkey reload-parameter.sh"
  # The script is driven by ParametersDefinition.spec.reloadAction.shellTrigger,
  # which calls it as `reload-parameter.sh <name> <value>` — once per changed
  # dynamic parameter — inside the config-manager sidecar.
  setup() {
    mkdir -p fakebin
    cat > fakebin/timeout <<'SH'
#!/bin/sh
shift
exec "$@"
SH
    cat > fakebin/valkey-cli <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "${FAKE_CLI_LOG:-./cli-args.log}"
case "${FAKE_VALKEY_OUTPUT:-OK}" in
  OK) printf 'OK\n' ;;
  unknown) printf 'ERR Unknown option\n' ;;
  immutable) printf "ERR CONFIG SET failed - can't set immutable config\n" ;;
  invalid) printf 'ERR invalid maxmemory policy\n' ;;
  range) printf 'ERR value is out of range\n' ;;
  unreachable) printf 'Could not connect to Valkey at 127.0.0.1:6379\n' ;;
esac
exit 0
SH
    chmod +x fakebin/timeout fakebin/valkey-cli
    export PATH="./fakebin:${PATH}"
    export FAKE_CLI_LOG="./cli-args.log"
    unset FAKE_VALKEY_OUTPUT VALKEY_DEFAULT_PASSWORD VALKEY_CLI_TLS_ARGS SERVICE_PORT
  }
  Before "setup"

  cleanup() {
    rm -rf fakebin cli-args.log
    unset FAKE_VALKEY_OUTPUT FAKE_CLI_LOG VALKEY_DEFAULT_PASSWORD VALKEY_CLI_TLS_ARGS SERVICE_PORT
  }
  After "cleanup"

  It "succeeds when CONFIG SET returns OK"
    When run bash ../scripts/reload-parameter.sh maxmemory-policy allkeys-lru
    The status should be success
  End

  It "passes the parameter name to CONFIG SET unchanged"
    # The name is already the config file key (lowercase-hyphen); translating it
    # (e.g. MAXMEMORY_POLICY) is neither needed nor done.
    When run bash ../scripts/reload-parameter.sh maxmemory-policy allkeys-lru
    The status should be success
    The contents of file "./cli-args.log" should include "CONFIG"
    The contents of file "./cli-args.log" should include "SET"
    The contents of file "./cli-args.log" should include "maxmemory-policy"
  End

  It "keeps a value containing spaces as one argument"
    When run bash ../scripts/reload-parameter.sh save "900 1"
    The status should be success
    The contents of file "./cli-args.log" should include "900 1"
  End

  It "reaches the local server with the component port"
    When run bash ../scripts/reload-parameter.sh maxclients 10000
    The status should be success
    The contents of file "./cli-args.log" should include "127.0.0.1"
    The contents of file "./cli-args.log" should include "6379"
  End

  It "passes no password argument when the component has none"
    # `include "-a"` would also match "--no-auth-warning", so match the argv item.
    When call bash -c 'bash ../scripts/reload-parameter.sh maxclients 10000 >/dev/null 2>&1; grep -qx -- -a ./cli-args.log'
    The status should be failure
  End

  It "honours SERVICE_PORT"
    export SERVICE_PORT=6380
    When run bash ../scripts/reload-parameter.sh maxclients 10000
    The status should be success
    The contents of file "./cli-args.log" should include "6380"
  End

  It "adds the password when the component provides one"
    export VALKEY_DEFAULT_PASSWORD="datapass"
    When run bash ../scripts/reload-parameter.sh maxclients 10000
    The status should be success
    The contents of file "./cli-args.log" should include "datapass"
  End

  It "passes the password as its own -a argument"
    export VALKEY_DEFAULT_PASSWORD="datapass"
    When call bash -c 'bash ../scripts/reload-parameter.sh maxclients 10000 >/dev/null 2>&1; grep -qx -- -a ./cli-args.log'
    The status should be success
  End

  It "adds the TLS flags built by the component vars"
    export VALKEY_CLI_TLS_ARGS="--tls --cacert /etc/pki/tls/ca.crt"
    When run bash ../scripts/reload-parameter.sh maxclients 10000
    The status should be success
    The contents of file "./cli-args.log" should include "--tls"
    The contents of file "./cli-args.log" should include "/etc/pki/tls/ca.crt"
  End

  It "fails closed when the engine refuses the parameter"
    export FAKE_VALKEY_OUTPUT=unknown
    When run bash ../scripts/reload-parameter.sh cluster-enabled yes
    The status should be failure
    The stderr should include "ERROR: CONFIG SET cluster-enabled failed"
    The stderr should include "ERR Unknown option"
  End

  It "fails closed on an invalid enum value"
    export FAKE_VALKEY_OUTPUT=invalid
    When run bash ../scripts/reload-parameter.sh maxmemory-policy definitely-not-a-policy
    The status should be failure
    The stderr should include "ERROR: CONFIG SET maxmemory-policy failed"
  End

  It "fails closed on an invalid range value"
    export FAKE_VALKEY_OUTPUT=range
    When run bash ../scripts/reload-parameter.sh maxmemory-samples 0
    The status should be failure
    The stderr should include "ERROR: CONFIG SET maxmemory-samples failed"
  End

  It "fails closed when the server is unreachable"
    export FAKE_VALKEY_OUTPUT=unreachable
    When run bash ../scripts/reload-parameter.sh maxclients 10000
    The status should be failure
    The stderr should include "Could not connect to Valkey"
  End

  It "fails when no parameter name is given"
    When run bash ../scripts/reload-parameter.sh
    The status should be failure
    The stderr should include "missing parameter name"
  End
End
