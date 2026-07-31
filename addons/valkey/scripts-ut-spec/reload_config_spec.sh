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
if [ "${FAKE_CONFIG_DRIFT:-0}" -eq 1 ]; then
  printf '%s\n' 'maxmemory 536870912' > "${CONFIG_FILE}"
fi
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
    unset VERIFY_EMPTY_KEY FAKE_RELOAD_RC FAKE_STATIC_KEY FAKE_CONFIG_DRIFT
    unset KB_CONFIG_FILES_UPDATED maxmemory MAXMEMORY REAL_SHA256SUM SHA_HOOK
  }
  After "cleanup"

  run_kbagent_rows() {
    bash ../scripts/reload-config.sh hash-max-listpack-entries 512
    _first_rc=$?
    bash ../scripts/reload-config.sh io-threads-do-reads yes
    _second_rc=$?
    printf 'first_rc=%s second_rc=%s\n' "$_first_rc" "$_second_rc"
    return "$_second_rc"
  }

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

  It "accepts an idempotent no-op after kbagent attests the exact target file"
    cat >> "${CONFIG_FILE}" <<'CONF'
io-threads-do-reads yes
CONF
    export VERIFY_EMPTY_KEY=io-threads-do-reads
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh maxmemory 268435456
    The status should be success
    The stderr should include "target checksum verified"
    The stderr should not include "io-threads-do-reads"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "fails closed when a changed dynamic target is unreadable despite exact file attestation"
    export VERIFY_EMPTY_KEY=maxmemory
    export maxmemory=268435456
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh maxmemory 268435456
    The status should be failure
    The stderr should include "updated target maxmemory is uncheckable"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "does not scan or apply an unrelated snapshot key"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    printf '%s\n' "bind * -::*" "tcp-backlog 999" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 268435456" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh maxmemory 268435456
    The status should be success
    The stderr should not include "tcp-backlog"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "keeps sequential kbagent rows isolated when a later target is unreadable"
    cat >> "${CONFIG_FILE}" <<'CONF'
hash-max-listpack-entries 512
io-threads-do-reads yes
CONF
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 268435456" \
      "hash-max-listpack-entries 256" > "${VERIFY_VALUES}"
    export VERIFY_EMPTY_KEY=io-threads-do-reads
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When call run_kbagent_rows
    The status should be failure
    The output should include "first_rc=0 second_rc=1"
    The stderr should include "pre-check hash-max-listpack-entries: diff"
    The stderr should include "updated target io-threads-do-reads is uncheckable"
    The contents of file "${RELOAD_LOG}" should include "RELOAD: hash-max-listpack-entries 512"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD: io-threads-do-reads"
  End

  It "rejects a mismatched target checksum before any parameter mutation"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(printf '0%.0s' {1..64})"
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 214748364" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh maxmemory 268435456
    The status should be failure
    The stderr should include "target checksum mismatch"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "rejects a malformed target checksum before any parameter mutation"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:not-a-sha256"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "target checksum is malformed"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "rejects exact attestation without a current-action row"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "current-action row is malformed"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "rejects an incomplete current-action row"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh maxmemory
    The status should be failure
    The stderr should include "current-action row is malformed"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "rejects more than one current-action row in one process"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh maxmemory 1 maxmemory 2
    The status should be failure
    The stderr should include "expected exactly one key/value pair"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "rejects a current-action target absent from the immutable config snapshot"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh not-in-config value
    The status should be failure
    The stderr should include "current-action target not-in-config is absent"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "rejects a current-action value that is not in the attested snapshot"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh maxmemory 536870912
    The status should be failure
    The stderr should include "does not match immutable config snapshot"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "rejects a duplicate current-action target in the attested snapshot"
    printf '%s\n' 'maxmemory 268435456' >> "${CONFIG_FILE}"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh maxmemory 268435456
    The status should be failure
    The stderr should include "current-action target maxmemory is ambiguous"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "rejects duplicate target-file attestations as ambiguous"
    _target_sha=$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:${_target_sha},${CONFIG_FILE}:${_target_sha}"
    When run bash ../scripts/reload-config.sh maxmemory 268435456
    The status should be failure
    The stderr should include "target checksum attestation is ambiguous"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "does not treat an ordinary container environment variable as a changed argument"
    export VERIFY_EMPTY_KEY=maxmemory
    export maxmemory=268435456
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh tcp-backlog 511
    The status should be success
    The stderr should not include "maxmemory"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "does not let template environment precedence replace the current row"
    export VERIFY_EMPTY_KEY=maxmemory
    export maxmemory=template-value
    export MAXMEMORY=alias-template-value
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh tcp-backlog 511
    The status should be success
    The stderr should not include "maxmemory"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "does not treat a shell-safe alias alone as a changed argument"
    export VERIFY_EMPTY_KEY=maxmemory
    export MAXMEMORY=268435456
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh tcp-backlog 511
    The status should be success
    The stderr should not include "maxmemory"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "does not accept an attestation for an unrelated file"
    export KB_CONFIG_FILES_UPDATED="/tmp/unrelated:$(printf '0%.0s' {1..64})"
    When run bash ../scripts/reload-config.sh
    The status should be failure
    The stderr should include "freshness unconfirmed"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "rechecks attested bytes before mutation"
    _real_sha256sum=$(command -v sha256sum)
    export REAL_SHA256SUM="${_real_sha256sum}"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$("${_real_sha256sum}" "${CONFIG_FILE}" | awk '{print $1}')"
    cat > "${_spec_dir}/bin/sha256sum" <<'SH'
#!/bin/sh
"${REAL_SHA256SUM}" "$@"
printf '%s\n' 'maxmemory 536870912' > "${CONFIG_FILE}"
SH
    chmod +x "${_spec_dir}/bin/sha256sum"
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 214748364" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh maxmemory 268435456
    The status should be failure
    The stderr should include "target file drifted after snapshot verification"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "does not apply live bytes that drift after final checksum verification"
    _real_sha256sum=$(command -v sha256sum)
    export REAL_SHA256SUM="${_real_sha256sum}"
    export SHA_HOOK="${_spec_dir}/sha-hook-fired"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$("${_real_sha256sum}" "${CONFIG_FILE}" | awk '{print $1}')"
    cat > "${_spec_dir}/bin/sha256sum" <<'SH'
#!/bin/sh
"${REAL_SHA256SUM}" "$@"
if [ "$1" = "${CONFIG_FILE}" ] && [ ! -f "${SHA_HOOK}" ]; then
  : > "${SHA_HOOK}"
  printf '%s\n' 'maxmemory 536870912' > "${CONFIG_FILE}"
fi
SH
    chmod +x "${_spec_dir}/bin/sha256sum"
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 214748364" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh maxmemory 268435456
    The status should be failure
    The stderr should include "target file drifted after snapshot verification"
    The contents of file "${RELOAD_LOG}" should not include "RELOAD:"
  End

  It "fails after row apply when the live file drifts before marker write"
    export FAKE_CONFIG_DRIFT=1
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 214748364" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh maxmemory 268435456
    The status should be failure
    The stderr should include "target file drifted after snapshot verification"
    The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 268435456"
  End

  It "normalizes surrounding row whitespace and configuration quotes"
    cat > "${CONFIG_FILE}" <<'CONF'
logfile "/data/running.log"
CONF
    printf '%s\n' 'logfile /data/old.log' > "${VERIFY_VALUES}"
    export KB_CONFIG_FILES_UPDATED="${CONFIG_FILE}:$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
    When run bash ../scripts/reload-config.sh logfile ' "/data/running.log" '
    The status should be success
    The stderr should include "pre-check logfile: diff"
    The contents of file "${RELOAD_LOG}" should include "RELOAD: logfile /data/running.log"
    The contents of file "${RELOAD_LOG}" should not include '"'
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
