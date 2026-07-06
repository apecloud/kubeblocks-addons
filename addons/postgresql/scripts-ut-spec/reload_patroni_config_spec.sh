# shellcheck shell=sh

Describe "scripts/reload_patroni_config.sh"

  script_path() {
    printf "%s" "../scripts/reload_patroni_config.sh"
  }

  setup() {
    tmpdir=$(mktemp -d -t pg-reload-config-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    RELOAD_CONFIG_MAX_RETRIES=2
    RELOAD_CONFIG_RETRY_INTERVAL=0
    CURRENT_POD_IP="127.0.0.1"
    export PATH CALL_LOG RELOAD_CONFIG_MAX_RETRIES RELOAD_CONFIG_RETRY_INTERVAL CURRENT_POD_IP
    unset PG_MODE primaryEndpoint CURL_GET_EXIT CURL_PATCH_EXIT 2>/dev/null || true
    write_curl_stub
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  # Emulates the two curl call shapes: GET /config returns the current config
  # JSON; PATCH /config returns the patched config. curl -f semantics are
  # emulated via the CURL_*_EXIT controls (22 = HTTP error under -f).
  write_curl_stub() {
    cat > "${bindir}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${CALL_LOG}"
case "$*" in
  *"-X PATCH"*)
    if [ "${CURL_PATCH_EXIT:-0}" -ne 0 ]; then exit "${CURL_PATCH_EXIT}"; fi
    printf '%s' '{"patched":true}'
    ;;
  *)
    if [ "${CURL_GET_EXIT:-0}" -ne 0 ]; then exit "${CURL_GET_EXIT}"; fi
    printf '%s' '{"postgresql":{"parameters":{}}}'
    ;;
esac
EOF
    chmod +x "${bindir}/curl"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  It "fails closed when PG_MODE is not set instead of clearing standby config"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "Reload patroni config begin"
    The error should include "PG_MODE is not set"
    The result of function call_log should not include "PATCH"
  End

  It "clears standby config for a primary cluster"
    export PG_MODE="primary"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "Clear standby config"
    The output should include "Reload patroni config done"
    The result of function call_log should include '-X PATCH -d {"standby_cluster":null}'
  End

  It "patches standby_cluster host/port for a standby cluster"
    export PG_MODE="standby"
    export primaryEndpoint="primary.example.com:5432"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "Set STANDBY_HOST=primary.example.com, STANDBY_PORT=5432"
    The result of function call_log should include '"host":"primary.example.com","port":5432'
  End

  It "rejects an invalid primaryEndpoint format"
    export PG_MODE="standby"
    export primaryEndpoint="not-a-host-port"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "Invalid primary_endpoint format"
    The result of function call_log should not include "PATCH"
  End

  It "retries the config GET and succeeds when it recovers"
    # first GET fails, second succeeds: flip the control file the stub reads
    cat > "${bindir}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${CALL_LOG}"
case "$*" in
  *"-X PATCH"*) printf '%s' '{"patched":true}' ;;
  *)
    if [ ! -f "${CALL_LOG}.once" ]; then
      touch "${CALL_LOG}.once"
      exit 7
    fi
    printf '%s' '{"postgresql":{"parameters":{}}}'
    ;;
esac
EOF
    chmod +x "${bindir}/curl"
    export PG_MODE="primary"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "retrying in 0s (attempt 1/2)"
    The output should include "Reload patroni config done"
  End

  It "gives up after max retries when the config GET keeps failing"
    export PG_MODE="primary"
    export CURL_GET_EXIT=7
    When run bash "$(script_path)"
    The status should be failure
    The output should include "giving up"
    The result of function call_log should not include "PATCH"
  End

  It "fails when the PATCH is rejected"
    export PG_MODE="primary"
    export CURL_PATCH_EXIT=22
    When run bash "$(script_path)"
    The status should be failure
    The output should include "Clear standby config"
    The error should include "PATCH"
    The output should not include "Reload patroni config done"
  End
End
