# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "reload_config_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Valkey reload-config.sh"
  setup() {
    _spec_dir=$(mktemp -d "${TMPDIR:-/tmp}/reload-config-spec.XXXXXX")
    mkdir -p "${_spec_dir}/conf" "${_spec_dir}/bin"

    cat > "${_spec_dir}/conf/valkey.conf" <<'CONF'
bind * -::*
tcp-backlog 511
timeout 0
maxmemory-policy volatile-lru
maxmemory 268435456
CONF

cat > "${_spec_dir}/reload-parameter.sh" <<'SH'
#!/bin/sh
echo "RELOAD: $1 $2" >> "${RELOAD_LOG}"
if [ "$1" = "${FAKE_STATIC_KEY:-}" ]; then
  exit 2
fi
if [ "${FAKE_RELOAD_RC:-0}" -ne 0 ]; then
  exit "${FAKE_RELOAD_RC}"
fi
echo "$1 $2" >> "${APPLIED_VALUES}"
exit 0
SH
    chmod +x "${_spec_dir}/reload-parameter.sh"

    cat > "${_spec_dir}/bin/timeout" <<'SH'
#!/bin/sh
shift
exec "$@"
SH
    chmod +x "${_spec_dir}/bin/timeout"

    cat > "${_spec_dir}/verify-cmd.sh" <<'SH'
#!/bin/sh
key="$3"
if [ "$key" = "${VERIFY_EMPTY_KEY:-}" ]; then
  printf '%s\n\n' "$key"
  exit 0
fi
value=$(grep "^${key} " "${APPLIED_VALUES}" 2>/dev/null | tail -1 | cut -d' ' -f2-)
if [ -z "$value" ]; then
  value=$(grep "^${key} " "${VERIFY_VALUES}" 2>/dev/null | head -1 | cut -d' ' -f2-)
fi
printf '%s\n%s\n' "$key" "$value"
SH
    chmod +x "${_spec_dir}/verify-cmd.sh"

    export PATH="${_spec_dir}/bin:${PATH}"
    export CONFIG_FILE="${_spec_dir}/conf/valkey.conf"
    export RELOAD_PARAM_SCRIPT="${_spec_dir}/reload-parameter.sh"
    export RELOAD_VERIFY_CMD="${_spec_dir}/verify-cmd.sh"
    export MAX_WAIT=1
    export GLOBAL_DEADLINE=9999999999
    export MARKER_FILE="${_spec_dir}/applied.marker"
    export RELOAD_LOG="${_spec_dir}/calls.log"
    export APPLIED_VALUES="${_spec_dir}/applied.txt"
    export VERIFY_VALUES="${_spec_dir}/verify-kv.txt"
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 268435456" \
      > "${VERIFY_VALUES}"
    rm -f "${RELOAD_LOG}" "${APPLIED_VALUES}" "${MARKER_FILE}"
  }
  Before "setup"

  cleanup() {
    rm -rf "${_spec_dir:-}"
    unset CONFIG_FILE RELOAD_PARAM_SCRIPT RELOAD_VERIFY_CMD MAX_WAIT
    unset GLOBAL_DEADLINE MARKER_FILE RELOAD_LOG APPLIED_VALUES VERIFY_VALUES
    unset VERIFY_EMPTY_KEY FAKE_RELOAD_RC FAKE_STATIC_KEY
  }
  After "cleanup"

  It "applies a file that differs from runtime and verifies the readback"
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 214748364" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be success
    The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 268435456"
    The stderr should include "pre-check maxmemory: diff"
    The path "${MARKER_FILE}" should be file
  End

  It "defers when matching old content stays stable even if a prior marker exists"
    echo "$(hostname):${CONFIG_FILE}:$(cksum "$CONFIG_FILE" | cut -d' ' -f1)" > "${MARKER_FILE}"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "freshness unconfirmed"
    The stderr should include "retry-safe: yes"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "defers when matching old content stays stable without a marker"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "freshness unconfirmed"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "applies when a fresh projection changes the file during the bounded wait"
    export MAX_WAIT=3
    _new_conf="${CONFIG_FILE}.new"
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 536870912" \
      > "${_new_conf}"
    (sleep 1; cp "${_new_conf}" "${CONFIG_FILE}") &
    _bg=$!
    When run bash ../scripts/reload-config.sh
    wait "${_bg}" 2>/dev/null || true
    The status should be success
    The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 536870912"
    The stderr should include "wrote marker:"
  End

  It "fails when post-apply CONFIG GET cannot prove the desired value"
    export VERIFY_EMPTY_KEY=maxmemory
    printf '%s\n' "bind * -::*" "tcp-backlog 999" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 214748364" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "VERIFY FAIL: maxmemory"
  End

  It "strips configuration quotes before applying"
    cat > "${CONFIG_FILE}" <<'CONF'
bind * -::*
logfile "/data/running.log"
CONF
    printf '%s\n' "bind * -::*" "logfile /data/old.log" > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be success
    The contents of file "${RELOAD_LOG}" should include "RELOAD: logfile /data/running.log"
    The contents of file "${RELOAD_LOG}" should not include '"'
    The stderr should include "pre-check logfile: diff"
  End

  It "skips comments and empty lines without inventing parameter calls"
    cat > "${CONFIG_FILE}" <<'CONF'
# comment

maxmemory 268435456
CONF
    printf '%s\n' "maxmemory 214748364" > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be success
    The contents of file "${RELOAD_LOG}" should equal "RELOAD: maxmemory 268435456"
    The stderr should include "pre-check maxmemory: diff"
  End

  It "continues past an explicitly unsupported static parameter"
    export FAKE_STATIC_KEY=bind
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 214748364" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be success
    The contents of file "${RELOAD_LOG}" should include "RELOAD: bind * -::*"
    The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 268435456"
    The stderr should include "apply bind: rc=2"
  End

  It "aborts after two consecutive parameter timeouts"
    export FAKE_RELOAD_RC=124
    printf '%s\n' "bind old" "tcp-backlog 1" "timeout 1" \
      "maxmemory-policy noeviction" "maxmemory 1" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "2 consecutive timeouts"
  End

  It "fails closed when every runtime value is unreadable"
    : > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "uncheckable"
    The stderr should include "freshness unconfirmed"
  End

  It "aborts before mutation when the global deadline has expired"
    export GLOBAL_DEADLINE=1
    printf '%s\n' "bind old" > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "global deadline exceeded"
    The path "${RELOAD_LOG}" should not be file
  End
End
