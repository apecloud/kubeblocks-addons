# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "reload_parameter_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Valkey reload-parameter.sh"
  setup() {
    mkdir -p fakebin
    cat > fakebin/timeout <<'SH'
#!/bin/sh
shift
exec "$@"
SH
    cat > fakebin/valkey-cli <<'SH'
#!/bin/sh
case "${FAKE_VALKEY_OUTPUT:-OK}" in
  OK) printf 'OK\n' ;;
  unknown) printf 'ERR Unknown option\n' ;;
  immutable) printf 'ERR CONFIG SET failed (possibly related to argument '\''cluster-enabled'\'') - can'\''t set immutable config\n' ;;
  invalid) printf 'ERR invalid maxmemory policy\n' ;;
  range) printf 'ERR value is out of range\n' ;;
esac
exit 0
SH
    chmod +x fakebin/timeout fakebin/valkey-cli
    export PATH="./fakebin:${PATH}"
    unset VALKEY_DEFAULT_PASSWORD
    unset VALKEY_CLI_TLS_ARGS
    unset SERVICE_PORT
  }
  Before "setup"

  cleanup() {
    rm -rf fakebin
    unset FAKE_VALKEY_OUTPUT
    unset VALKEY_DEFAULT_PASSWORD
    unset VALKEY_CLI_TLS_ARGS
    unset SERVICE_PORT
  }
  After "cleanup"

  It "succeeds when CONFIG SET returns OK"
    export FAKE_VALKEY_OUTPUT=OK
    When run bash ../scripts/reload-parameter.sh MAXMEMORY_POLICY allkeys-lru
    The status should be success
  End

  It "keeps unsupported static parameters non-fatal"
    export FAKE_VALKEY_OUTPUT=unknown
    When run bash ../scripts/reload-parameter.sh BIND 0.0.0.0
    The status should be success
  End

  It "keeps immutable runtime parameters non-fatal"
    export FAKE_VALKEY_OUTPUT=immutable
    When run bash ../scripts/reload-parameter.sh CLUSTER_ENABLED yes
    The status should be success
  End

  It "fails closed on invalid enum values"
    export FAKE_VALKEY_OUTPUT=invalid
    When run bash ../scripts/reload-parameter.sh MAXMEMORY_POLICY definitely-not-a-policy
    The status should be failure
    The stderr should include "ERROR: CONFIG SET maxmemory-policy failed"
  End

  It "fails closed on invalid range values"
    export FAKE_VALKEY_OUTPUT=range
    When run bash ../scripts/reload-parameter.sh MAXMEMORY_SAMPLES 0
    The status should be failure
    The stderr should include "ERROR: CONFIG SET maxmemory-samples failed"
  End
End
