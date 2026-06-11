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
# Valkey configuration

bind * -::*
tcp-backlog 511
timeout 0
maxmemory-policy volatile-lru
maxmemory 268435456
CONF

    ln -sf "${_spec_dir}/conf" "${_spec_dir}/conf/..data"

    # Mock reload-parameter.sh — logs calls, exit 0 (dynamic) by default
    cat > "${_spec_dir}/reload-parameter.sh" <<'SH'
#!/bin/sh
echo "RELOAD: $1 $2" >> "${RELOAD_LOG}"
exit "${FAKE_RELOAD_RC:-0}"
SH
    chmod +x "${_spec_dir}/reload-parameter.sh"

    # Mock timeout — passthrough
    cat > "${_spec_dir}/bin/timeout" <<'SH'
#!/bin/sh
shift
exec "$@"
SH
    chmod +x "${_spec_dir}/bin/timeout"

    # Mock stat — returns FAKE_MTIME
    cat > "${_spec_dir}/bin/stat" <<'STATSH'
#!/bin/sh
if [ -n "${FAKE_MTIME:-}" ]; then echo "$FAKE_MTIME"
else /usr/bin/stat -c %Y "$3" 2>/dev/null || /usr/bin/stat -f %m "$3" 2>/dev/null || echo 0; fi
STATSH
    chmod +x "${_spec_dir}/bin/stat"

    # Mock date — returns FAKE_NOW for +%s
    cat > "${_spec_dir}/bin/date" <<'DATESH'
#!/bin/sh
if [ "$1" = "+%s" ] && [ -n "${FAKE_NOW:-}" ]; then echo "$FAKE_NOW"
else /bin/date "$@"; fi
DATESH
    chmod +x "${_spec_dir}/bin/date"

    # Mock cksum — deterministic
    cat > "${_spec_dir}/bin/cksum" <<'CKSUMSH'
#!/bin/sh
/usr/bin/cksum "$@"
CKSUMSH
    chmod +x "${_spec_dir}/bin/cksum"

    # Mock verify command — returns expected value (pass-through)
    cat > "${_spec_dir}/verify-cmd.sh" <<'SH'
#!/bin/sh
# Expects: verify-cmd.sh CONFIG GET <key>
# Returns key then value from VERIFY_VALUES file
_key="$3"
if [ -f "${VERIFY_VALUES:-/dev/null}" ]; then
  _val=$(grep "^${_key} " "$VERIFY_VALUES" | head -1 | cut -d' ' -f2-)
  [ -n "$_val" ] && { echo "$_key"; echo "$_val"; exit 0; }
fi
echo "$_key"
echo ""
SH
    chmod +x "${_spec_dir}/verify-cmd.sh"

    export PATH="${_spec_dir}/bin:${PATH}"
    export CONFIG_FILE="${_spec_dir}/conf/valkey.conf"
    export DATA_LINK="${_spec_dir}/conf/..data"
    export RELOAD_PARAM_SCRIPT="${_spec_dir}/reload-parameter.sh"
    export RELOAD_VERIFY_CMD="${_spec_dir}/verify-cmd.sh"
    export MAX_WAIT=1
    export APPLY_BUDGET=50
    export MARKER_FILE="${_spec_dir}/marker"
    export RELOAD_LOG="${_spec_dir}/calls.log"
    rm -f "${RELOAD_LOG}" "${MARKER_FILE}"

    # Default: verify returns matching values
    cp "${_spec_dir}/conf/valkey.conf" "${_spec_dir}/verify-values.txt"
    # Strip comments and empty lines, keep key-value pairs
    grep -v '^#' "${_spec_dir}/verify-values.txt" | grep -v '^$' > "${_spec_dir}/verify-kv.txt" || true
    export VERIFY_VALUES="${_spec_dir}/verify-kv.txt"
  }
  Before "setup"

  cleanup() {
    rm -rf "${_spec_dir:-}"
    unset RELOAD_LOG FAKE_MTIME FAKE_NOW CONFIG_FILE DATA_LINK
    unset RELOAD_PARAM_SCRIPT RELOAD_VERIFY_CMD MAX_WAIT APPLY_BUDGET
    unset MARKER_FILE FAKE_RELOAD_RC VERIFY_VALUES
  }
  After "cleanup"

  It "applies parameters and passes verify when projection is fresh"
    export FAKE_NOW=1000
    export FAKE_MTIME=995
    When run bash ../scripts/reload-config.sh
    The status should be success
    The contents of file "${RELOAD_LOG}" should include "RELOAD: bind * -::*"
    The contents of file "${RELOAD_LOG}" should include "RELOAD: tcp-backlog 511"
    The contents of file "${RELOAD_LOG}" should include "RELOAD: timeout 0"
    The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory-policy volatile-lru"
    The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 268435456"
  End

  It "defers with exit 1 when freshness is unconfirmed"
    export FAKE_NOW=1000
    export FAKE_MTIME=500
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "ConfigMap projection not detected"
    The stderr should include "retry-safe: yes"
  End

  It "writes marker file on freshness failure"
    export FAKE_NOW=1000
    export FAKE_MTIME=500
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "ConfigMap projection not detected"
    The file "${MARKER_FILE}" should be exist
  End

  It "proceeds on retry when content changed since last failure"
    export FAKE_NOW=1000
    export FAKE_MTIME=500
    # Write a stale marker (different from current content)
    echo "99999 99 stale" > "${MARKER_FILE}"
    When run bash ../scripts/reload-config.sh
    The status should be success
    The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 268435456"
  End

  It "defers again if marker exists and content unchanged"
    export FAKE_NOW=1000
    export FAKE_MTIME=500
    # Write a marker matching current content
    cksum < "${CONFIG_FILE}" > "${MARKER_FILE}"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "ConfigMap projection not detected"
  End

  It "skips comment and empty lines"
    export FAKE_NOW=1000
    export FAKE_MTIME=995
    When run bash ../scripts/reload-config.sh
    The status should be success
    The contents of file "${RELOAD_LOG}" should not include "RELOAD: #"
  End

  It "cleans marker file on success"
    export FAKE_NOW=1000
    export FAKE_MTIME=995
    echo "stale marker" > "${MARKER_FILE}"
    When run bash ../scripts/reload-config.sh
    The status should be success
    The file "${MARKER_FILE}" should not be exist
  End

  Describe "CONFIG GET read-back verification"
    It "fails when runtime value differs from desired"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      # Override verify values so maxmemory returns wrong value
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "VERIFY FAIL: maxmemory"
    End
  End

  Describe "apply budget guard"
    It "aborts when budget is exceeded"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      export APPLY_BUDGET=0
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "apply budget"
    End
  End

  Describe "consecutive timeout abort"
    setup_timeout_mock() {
      _td=$(mktemp -d "${TMPDIR:-/tmp}/reload-timeout.XXXXXX")
      mkdir -p "${_td}/conf" "${_td}/bin"

      printf '%s\n' 'param-a val-a' 'param-b val-b' 'param-c val-c' \
        > "${_td}/conf/valkey.conf"
      ln -sf "${_td}/conf" "${_td}/conf/..data"

      cat > "${_td}/bin/timeout" <<'SH'
#!/bin/sh
exit 124
SH
      chmod +x "${_td}/bin/timeout"

      cat > "${_td}/bin/stat" <<'SH'
#!/bin/sh
echo "${FAKE_MTIME:-0}"
SH
      chmod +x "${_td}/bin/stat"

      cat > "${_td}/bin/date" <<'SH'
#!/bin/sh
if [ "$1" = "+%s" ]; then echo "${FAKE_NOW:-0}"; else /bin/date "$@"; fi
SH
      chmod +x "${_td}/bin/date"

      cat > "${_td}/bin/cksum" <<'SH'
#!/bin/sh
/usr/bin/cksum "$@"
SH
      chmod +x "${_td}/bin/cksum"

      cat > "${_td}/bin/mktemp" <<'SH'
#!/bin/sh
f="${_td}/verify-tmp"
touch "$f"
echo "$f"
SH
      chmod +x "${_td}/bin/mktemp"

      export PATH="${_td}/bin:${PATH}"
      export CONFIG_FILE="${_td}/conf/valkey.conf"
      export DATA_LINK="${_td}/conf/..data"
      export RELOAD_PARAM_SCRIPT="/nonexistent/reload-parameter.sh"
      export MARKER_FILE="${_td}/marker"
      export MAX_WAIT=0
      export APPLY_BUDGET=50
    }
    Before "setup_timeout_mock"

    cleanup_timeout() { rm -rf "${_td:-}"; }
    After "cleanup_timeout"

    It "aborts after 2 consecutive timeouts"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "2 consecutive timeouts"
    End
  End
End
