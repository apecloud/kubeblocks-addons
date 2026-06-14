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

    # Mock reload-parameter.sh — logs calls, optionally tracks applied values
    cat > "${_spec_dir}/reload-parameter.sh" <<'SH'
#!/bin/sh
echo "RELOAD: $1 $2" >> "${RELOAD_LOG}"
[ -n "${APPLIED_VALUES:-}" ] && echo "$1 $2" >> "$APPLIED_VALUES"
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

    # Mock hostname — overridable for identity mismatch tests
    cat > "${_spec_dir}/bin/hostname" <<'HOSTSH'
#!/bin/sh
echo "${FAKE_HOSTNAME:-$(uname -n)}"
HOSTSH
    chmod +x "${_spec_dir}/bin/hostname"

    # Mock verify command — two-layer: APPLIED_VALUES first, then VERIFY_VALUES
    # VERIFY_EMPTY_KEY forces empty output for a specific key (for testing)
    # NORMALIZE_MAP overrides APPLIED_VALUES return for keys that Valkey normalizes
    cat > "${_spec_dir}/verify-cmd.sh" <<'SH'
#!/bin/sh
_key="$3"
if [ "$_key" = "${VERIFY_EMPTY_KEY:-}" ]; then
  echo "$_key"; echo ""; exit 0
fi
if [ -f "${APPLIED_VALUES:-}" ] 2>/dev/null; then
  _val=$(grep "^${_key} " "$APPLIED_VALUES" 2>/dev/null | tail -1 | cut -d' ' -f2-)
  if [ -n "$_val" ]; then
    if [ -f "${NORMALIZE_MAP:-/dev/null}" ]; then
      _norm=$(grep "^${_key} " "$NORMALIZE_MAP" 2>/dev/null | head -1 | cut -d' ' -f2-)
      [ -n "$_norm" ] && { echo "$_key"; echo "$_norm"; exit 0; }
    fi
    echo "$_key"; echo "$_val"; exit 0
  fi
fi
if [ -f "${VERIFY_VALUES:-/dev/null}" ]; then
  _val=$(grep "^${_key} " "$VERIFY_VALUES" 2>/dev/null | head -1 | cut -d' ' -f2-)
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
    export RELOAD_LOG="${_spec_dir}/calls.log"
    export GLOBAL_DEADLINE=9999999999
    export MARKER_FILE="${_spec_dir}/applied.marker"
    rm -f "${RELOAD_LOG}" "${MARKER_FILE}"

    # Default: verify returns matching values (runtime == file)
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 268435456" \
      > "${_spec_dir}/verify-kv.txt"
    export VERIFY_VALUES="${_spec_dir}/verify-kv.txt"

    # Track applied values so verify sees post-CONFIG-SET state
    export APPLIED_VALUES="${_spec_dir}/applied.txt"
    rm -f "$APPLIED_VALUES"
  }
  Before "setup"

  cleanup() {
    rm -rf "${_spec_dir:-}"
    unset RELOAD_LOG FAKE_MTIME FAKE_NOW CONFIG_FILE DATA_LINK
    unset RELOAD_PARAM_SCRIPT RELOAD_VERIFY_CMD MAX_WAIT
    unset FAKE_RELOAD_RC VERIFY_VALUES APPLIED_VALUES
    unset GLOBAL_DEADLINE VERIFY_EMPTY_KEY NORMALIZE_MAP FAKE_NOW_COUNTER
    unset MARKER_FILE FAKE_HOSTNAME
  }
  After "cleanup"

  Describe "pre-check detects file differs from runtime"
    It "applies and verifies when runtime has old values"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      # Runtime has old maxmemory; file has new 268435456
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 268435456"
      The stderr should include "pre-check maxmemory: diff"
    End

    It "applies even when mtime is old (Blocker 1 fix)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      # Runtime has old maxmemory — pre-check finds diff, skips freshness
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 268435456"
      The stderr should include "pre-check maxmemory: diff"
    End
  End

  Describe "file matches runtime — freshness gate"
    It "exits 0 when ..data mtime is recent and all params match runtime (Bug 2 idempotent fix)"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "recent projection heuristic, runtime matches"
    End

    It "exits 0 when mtime stale but runtime verified and content stable (Bug 9b)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "content stable"
      The stderr should include "wrote marker:"
    End

    It "falls back to old-mtime when stat returns non-numeric (GNU stat -f %m compat, Bug 9b closes)"
      export FAKE_NOW=1000
      export FAKE_MTIME="Filesystem 0x1234 Type: ext4 Block size: 4096 995"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "content stable"
    End

    It "accepts when mtime stale + runtime verified + content stable (Bug 9b bounded risk)"
      export FAKE_NOW=1000
      export FAKE_MTIME=100
      # Bounded risk: if kubelet hasn't projected a genuinely new ConfigMap
      # within MAX_WAIT, this is a false PASS. Residual window = kubelet
      # projection latency (Watch mode ~5s, MAX_WAIT default 15s).
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "content stable"
      The stderr should include "wrote marker:"
    End
  End

  Describe "content-hash marker — idempotent close"
    It "exits 0 on late retry when content-hash marker matches (Bug 6 fix)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      export MARKER_OBS_WINDOW=1
      export MAX_WAIT=1
      echo "$(hostname):${CONFIG_FILE}:$(cksum "$CONFIG_FILE" | cut -d' ' -f1)" > "$MARKER_FILE"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "content-hash marker matches"
      The stderr should include "deferring to content polling"
      The stderr should include "content stable"
    End

    It "exits 0 after pod restart when marker persists and config unchanged (Bug 7 fix)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      export MARKER_OBS_WINDOW=1
      export MAX_WAIT=1
      echo "$(hostname):${CONFIG_FILE}:$(cksum "$CONFIG_FILE" | cut -d' ' -f1)" > "$MARKER_FILE"
      ln -sf "${_spec_dir}/conf-new-mount" "${DATA_LINK}"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "content-hash marker matches"
      The stderr should include "deferring to content polling"
      The stderr should include "content stable"
    End

    It "invalidates stale marker then writes fresh one after content polling (Bug 9a/9b)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      echo "$(hostname):${CONFIG_FILE}:99999999" > "$MARKER_FILE"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "marker mismatch"
      The stderr should include "content stable"
      The stderr should include "wrote marker:"
      The path "$MARKER_FILE" should be file
    End

    It "invalidates hostname-mismatched marker then writes fresh one (Bug 9a/9b)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      export FAKE_HOSTNAME="restored-cluster-pod-0"
      echo "old-cluster-pod-0:${CONFIG_FILE}:$(cksum "$CONFIG_FILE" | cut -d' ' -f1)" > "$MARKER_FILE"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "marker mismatch"
      The stderr should include "content stable"
      The path "$MARKER_FILE" should be file
    End

    It "invalidates malformed marker then writes fresh one (Bug 9a/9b)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      echo "garbage-no-colons" > "$MARKER_FILE"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "marker mismatch"
      The stderr should include "content stable"
      The path "$MARKER_FILE" should be file
    End

    It "writes marker after successful apply for future retries"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "pre-check maxmemory: diff"
      The path "$MARKER_FILE" should be file
    End

    It "writes marker on mtime shortcut for future VScale use (Bug 8 fix)"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "recent projection heuristic"
      The path "$MARKER_FILE" should be file
    End

    It "VScale after mtime shortcut: marker written earlier enables exit 0 with stale mtime"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      export MARKER_OBS_WINDOW=1
      export MAX_WAIT=1
      # First call: mtime fresh → exit 0 + writes marker
      bash ../scripts/reload-config.sh 2>/dev/null
      # Verify marker was written
      [ -f "$MARKER_FILE" ] || { echo "FAIL: marker not written by mtime shortcut"; exit 1; }
      # Second call: simulate VScale — stale mtime, same config content
      export FAKE_MTIME=500
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "content-hash marker matches"
      The stderr should include "deferring to content polling"
      The stderr should include "content stable"
    End

    It "invalidates empty-cksum marker then writes fresh one (Bug 9a/9b)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      echo "$(hostname):${CONFIG_FILE}:" > "$MARKER_FILE"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "marker mismatch"
      The stderr should include "content stable"
      The path "$MARKER_FILE" should be file
    End

    It "does not write marker when cksum command fails"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      # Replace cksum mock with one that always fails
      cat > "${_spec_dir}/bin/cksum" <<'SH'
#!/bin/sh
exit 1
SH
      chmod +x "${_spec_dir}/bin/cksum"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "pre-check maxmemory: diff"
      The path "$MARKER_FILE" should not be file
    End
  End

  Describe "Bug 9: content polling closure + marker resilience"
    It "preserves marker when _build_marker fails transiently (Bug 9a)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      # Pre-seed valid marker
      echo "$(hostname):${CONFIG_FILE}:$(cksum "$CONFIG_FILE" | cut -d' ' -f1)" > "$MARKER_FILE"
      # Break cksum so _build_marker returns 1
      cat > "${_spec_dir}/bin/cksum" <<'SH'
#!/bin/sh
exit 1
SH
      chmod +x "${_spec_dir}/bin/cksum"
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "marker check: _build_marker failed, preserving existing marker"
      The stderr should include "marker build failed"
      The path "$MARKER_FILE" should be file
    End

    It "VScale on pod that missed initial mtime window: Bug 9b writes marker, then VScale matches via observation"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      export MARKER_OBS_WINDOW=1
      export MAX_WAIT=1
      # First call: stale mtime, no marker → Bug 9b → exit 0 + marker
      bash ../scripts/reload-config.sh 2>/dev/null
      [ -f "$MARKER_FILE" ] || { echo "FAIL: marker not written by Bug 9b path"; exit 1; }
      # Second call: simulate VScale — stale mtime, same config → marker matches →
      # observation window (1s) → no projection → defers to content polling → exit 0
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "content-hash marker matches"
      The stderr should include "deferring to content polling"
      The stderr should include "content stable"
    End

    It "fail-closed when marker write fails on content polling path (Bug 9b gate)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      # Point MARKER_FILE to non-writable path
      export MARKER_FILE="/nonexistent-dir/marker"
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "marker write failed"
      The stderr should include "retry-safe: yes"
    End

    It "fail-closed when checked_any=false even with stable content"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      # All params return empty → all uncheckable → checked_any=false
      printf '' > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "file matches runtime, freshness unconfirmed"
    End

    It "traces no-marker-file when marker absent"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      rm -f "$MARKER_FILE"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "no marker file at"
      The stderr should include "content stable"
    End

    It "fail-closed when mtime shortcut marker write fails"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      # Point MARKER_FILE to non-writable path — mtime fresh but write fails
      export MARKER_FILE="/nonexistent-dir/marker"
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "recent projection heuristic"
      The stderr should include "marker write failed"
      The stderr should include "retry-safe: yes"
    End

    It "marker match + delayed projection triggers apply (Bug 10)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      export MARKER_OBS_WINDOW=3
      export MAX_WAIT=1
      # Pre-seed marker matching current (old) file content
      echo "$(hostname):${CONFIG_FILE}:$(cksum "$CONFIG_FILE" | cut -d' ' -f1)" > "$MARKER_FILE"
      # Schedule file change after 1s (simulating kubelet projection with new maxmemory)
      _new_conf="${CONFIG_FILE}.new"
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 536870912" \
        "io-threads-do-reads yes" > "$_new_conf"
      (sleep 1; cp "$_new_conf" "$CONFIG_FILE") &
      _bg=$!
      When run bash ../scripts/reload-config.sh
      wait $_bg 2>/dev/null || true
      The status should be success
      The stderr should include "projection detected"
      The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory"
    End

    It "marker match + no projection defers to content polling (Bug 10/11)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      export MARKER_OBS_WINDOW=1
      export MAX_WAIT=1
      # Pre-seed marker matching current file content
      echo "$(hostname):${CONFIG_FILE}:$(cksum "$CONFIG_FILE" | cut -d' ' -f1)" > "$MARKER_FILE"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "deferring to content polling"
      The stderr should include "content stable"
    End

    It "marker match + late projection caught by content polling (Bug 11)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      export MARKER_OBS_WINDOW=1
      export MAX_WAIT=5
      echo "$(hostname):${CONFIG_FILE}:$(cksum "$CONFIG_FILE" | cut -d' ' -f1)" > "$MARKER_FILE"
      _new_conf="${CONFIG_FILE}.new"
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 536870912" \
        "io-threads-do-reads yes" > "$_new_conf"
      (sleep 3; cp "$_new_conf" "$CONFIG_FILE") &
      _bg=$!
      When run bash ../scripts/reload-config.sh
      wait $_bg 2>/dev/null || true
      The status should be success
      The stderr should include "deferring to content polling"
      The stderr should not include "content stable"
      The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory"
    End

    It "marker match + delayed projection + fresh mtime still applies (Bug 10 rev2)"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      export MARKER_OBS_WINDOW=3
      export MAX_WAIT=1
      echo "$(hostname):${CONFIG_FILE}:$(cksum "$CONFIG_FILE" | cut -d' ' -f1)" > "$MARKER_FILE"
      _new_conf="${CONFIG_FILE}.new"
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 536870912" \
        "io-threads-do-reads yes" > "$_new_conf"
      (sleep 1; cp "$_new_conf" "$CONFIG_FILE") &
      _bg=$!
      When run bash ../scripts/reload-config.sh
      wait $_bg 2>/dev/null || true
      The status should be success
      The stderr should include "projection detected"
      The stderr should not include "recent projection heuristic"
      The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory"
    End

    It "marker match + runtime mismatch still applies (Bug 10 safety)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      export MARKER_OBS_WINDOW=1
      # Runtime has old maxmemory
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      # Marker won't match because Phase 1 sees diff → _needs_apply=true → skip Phase 2
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "pre-check maxmemory: diff"
      The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory"
    End

    It "Phase 4 marker write failure does not block exit 0 (apply succeeded)"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      # Runtime has old maxmemory → pre-check diff → apply → Phase 4
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      # Point MARKER_FILE to non-writable path
      export MARKER_FILE="/nonexistent-dir/marker"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "pre-check maxmemory: diff"
      The stderr should include "Phase 4: marker write failed"
    End
  End

  Describe "content-change polling"
    It "applies when runtime has old values (Phase 1 diff path)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 268435456"
      The stderr should include "pre-check maxmemory: diff"
    End

    It "exits 0 when mtime stale + runtime verified + content stable (Bug 9b)"
      export FAKE_NOW=1000
      export FAKE_MTIME=500
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "content stable"
      The stderr should include "wrote marker:"
    End
  End

  It "skips comment and empty lines"
    export FAKE_NOW=1000
    export FAKE_MTIME=995
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 214748364" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be success
    The contents of file "${RELOAD_LOG}" should not include "RELOAD: #"
    The stderr should include "pre-check maxmemory: diff"
  End

  It "successful apply exits cleanly (no persistent state files)"
    export FAKE_NOW=1000
    export FAKE_MTIME=995
    printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
      "maxmemory-policy volatile-lru" "maxmemory 214748364" \
      > "${VERIFY_VALUES}"
    When run bash ../scripts/reload-config.sh
    The status should be success
    The stderr should include "pre-check maxmemory: diff"
  End

  It "idempotent exit 0 on retry when ..data mtime is recent"
    export FAKE_NOW=1000
    export FAKE_MTIME=995
    # Simulates Bug 2 retry: prior apply succeeded, controller retries this pod.
    # File matches runtime (Phase 1 no diff), ..data mtime is recent → exit 0.
    When run bash ../scripts/reload-config.sh
    The status should be success
    The stderr should include "recent projection heuristic, runtime matches"
  End

  Describe "CONFIG GET read-back verification"
    It "succeeds when Valkey normalizes unit-suffixed values"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      # Config file has auto-aof-rewrite-min-size 64mb, but CONFIG GET
      # returns 67108864 (bytes). After CONFIG SET, post-SET readback
      # captures Valkey's normalized form, so verify compares 67108864
      # against 67108864 → PASS.
      cat > "${CONFIG_FILE}" <<'TESTCONF'
# Valkey configuration

bind * -::*
tcp-backlog 511
timeout 0
maxmemory-policy volatile-lru
maxmemory 268435456
auto-aof-rewrite-min-size 64mb
TESTCONF
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 268435456" \
        "auto-aof-rewrite-min-size 67108864" \
        > "${VERIFY_VALUES}"
      printf '%s\n' "auto-aof-rewrite-min-size 67108864" \
        > "${_spec_dir}/normalize-map.txt"
      export NORMALIZE_MAP="${_spec_dir}/normalize-map.txt"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The contents of file "${RELOAD_LOG}" should include "RELOAD: auto-aof-rewrite-min-size 64mb"
      The stderr should include "pre-check auto-aof-rewrite-min-size: diff"
    End

    It "fails when CONFIG GET returns empty (Blocker 2 fix)"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      # Pre-check triggers via tcp-backlog diff.  VERIFY_EMPTY_KEY makes
      # verify-cmd return empty for maxmemory in all phases (pre-check
      # skips it, verify catches it).
      export VERIFY_EMPTY_KEY=maxmemory
      printf '%s\n' "bind * -::*" "tcp-backlog 999" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "VERIFY FAIL: maxmemory: CONFIG GET returned empty or failed"
    End
  End

  Describe "uncheckable params handling"
    It "defers when all CONFIG GETs fail (freshness gate runs)"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      # Verify-cmd returns empty for everything → all uncheckable
      # → _needs_apply stays false → Phase 2 freshness gate runs → defers
      printf '' > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "pre-check bind: uncheckable"
      The stderr should include "file matches runtime, freshness unconfirmed"
    End

    It "succeeds when checkable params match and one static param is uncheckable"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      # bind/tcp-backlog/timeout/maxmemory-policy match, maxmemory returns empty
      # → checkable params verified, one uncheckable → mtime fresh → exit 0
      export VERIFY_EMPTY_KEY=maxmemory
      printf '%s\n' "bind * -::*" "tcp-backlog 511" "timeout 0" \
        "maxmemory-policy volatile-lru" "maxmemory 268435456" \
        > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be success
      The stderr should include "pre-check maxmemory: uncheckable"
      The stderr should include "recent projection heuristic, runtime matches"
    End
  End

  Describe "quoted values in config file"
    It "matches CONFIG GET despite quotes in file (no false diff)"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      cat > "${CONFIG_FILE}" <<'TESTCONF'
# Valkey configuration

bind * -::*
logfile "/data/running.log"
maxmemory-policy volatile-lru
maxmemory 268435456
TESTCONF
      # Runtime matches file content (unquoted)
      printf '%s\n' "bind * -::*" "logfile /data/running.log" \
        "maxmemory-policy volatile-lru" "maxmemory 268435456" \
        > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be success
      # All params match + ..data mtime fresh → exit 0 (no false diff, no apply needed)
      The stderr should include "pre-check logfile: match"
      The stderr should include "recent projection heuristic, runtime matches"
    End

    It "strips quotes before CONFIG SET (no runtime corruption)"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      cat > "${CONFIG_FILE}" <<'TESTCONF'
# Valkey configuration

bind * -::*
logfile "/data/running.log"
maxmemory-policy volatile-lru
maxmemory 268435456
TESTCONF
      # Runtime has old maxmemory → pre-check detects diff → apply
      printf '%s\n' "bind * -::*" "logfile /data/running.log" \
        "maxmemory-policy volatile-lru" "maxmemory 214748364" \
        > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be success
      # Reload should pass unquoted value to reload-parameter.sh
      The contents of file "${RELOAD_LOG}" should include "RELOAD: logfile /data/running.log"
      The contents of file "${RELOAD_LOG}" should not include 'RELOAD: logfile "/data/running.log"'
      The stderr should include "pre-check maxmemory: diff"
    End
  End

  Describe "global deadline"
    It "aborts when deadline is already exceeded"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      export GLOBAL_DEADLINE=0
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "global deadline exceeded"
    End

    It "aborts after CONFIG SET succeeds when deadline is reached before post-SET readback"
      # Counter-based date: returns 999, 1000, 1001, ... on each +%s call.
      # Call 1 (pre-check _check_deadline): 999 < 1001 → pass
      # Call 2 (apply-loop _check_deadline): 1000 < 1001 → pass
      # Call 3 (post-SET _check_deadline): 1001 >= 1001 → deadline exceeded
      echo "999" > "${_spec_dir}/now-counter"
      export FAKE_NOW_COUNTER="${_spec_dir}/now-counter"
      cat > "${_spec_dir}/bin/date" <<'SH'
#!/bin/sh
if [ "$1" = "+%s" ] && [ -f "${FAKE_NOW_COUNTER:-}" ]; then
  _n=$(cat "$FAKE_NOW_COUNTER")
  echo "$((_n + 1))" > "$FAKE_NOW_COUNTER"
  echo "$_n"
else
  /bin/date "$@"
fi
SH
      chmod +x "${_spec_dir}/bin/date"
      export GLOBAL_DEADLINE=1001
      printf '%s\n' 'maxmemory 268435456' > "${CONFIG_FILE}"
      printf '%s\n' "maxmemory 214748364" > "${VERIFY_VALUES}"
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "global deadline exceeded"
      The contents of file "${RELOAD_LOG}" should include "RELOAD: maxmemory 268435456"
    End
  End

  Describe "single timeout verify catch"
    setup_single_timeout_mock() {
      _st=$(mktemp -d "${TMPDIR:-/tmp}/reload-single-timeout.XXXXXX")
      mkdir -p "${_st}/conf" "${_st}/bin"

      printf '%s\n' 'maxmemory 268435456' 'maxmemory-policy volatile-lru' \
        > "${_st}/conf/valkey.conf"
      ln -sf "${_st}/conf" "${_st}/conf/..data"

      cat > "${_st}/reload-parameter.sh" <<'SH'
#!/bin/sh
echo "RELOAD: $1 $2" >> "${RELOAD_LOG}"
[ -n "${APPLIED_VALUES:-}" ] && echo "$1 $2" >> "$APPLIED_VALUES"
exit 0
SH
      chmod +x "${_st}/reload-parameter.sh"

      # timeout mock: return 124 for TIMEOUT_KEY, passthrough otherwise
      cat > "${_st}/bin/timeout" <<'SH'
#!/bin/sh
shift
if [ -n "${TIMEOUT_KEY:-}" ] && echo "$2" | grep -q "^${TIMEOUT_KEY}$"; then
  exit 124
fi
exec "$@"
SH
      chmod +x "${_st}/bin/timeout"

      cat > "${_st}/bin/stat" <<'SH'
#!/bin/sh
echo "${FAKE_MTIME:-0}"
SH
      chmod +x "${_st}/bin/stat"

      cat > "${_st}/bin/date" <<'SH'
#!/bin/sh
if [ "$1" = "+%s" ]; then echo "${FAKE_NOW:-0}"; else /bin/date "$@"; fi
SH
      chmod +x "${_st}/bin/date"

      cat > "${_st}/bin/cksum" <<'SH'
#!/bin/sh
/usr/bin/cksum "$@"
SH
      chmod +x "${_st}/bin/cksum"

      cat > "${_st}/bin/hostname" <<'SH'
#!/bin/sh
echo "${FAKE_HOSTNAME:-$(uname -n)}"
SH
      chmod +x "${_st}/bin/hostname"

      # verify mock: maxmemory returns OLD value, maxmemory-policy returns new
      cat > "${_st}/verify-cmd.sh" <<'SH'
#!/bin/sh
_key="$3"
if [ -f "${APPLIED_VALUES:-}" ] 2>/dev/null; then
  _val=$(grep "^${_key} " "$APPLIED_VALUES" 2>/dev/null | tail -1 | cut -d' ' -f2-)
  if [ -n "$_val" ]; then echo "$_key"; echo "$_val"; exit 0; fi
fi
if [ -f "${VERIFY_VALUES:-/dev/null}" ]; then
  _val=$(grep "^${_key} " "$VERIFY_VALUES" 2>/dev/null | head -1 | cut -d' ' -f2-)
  [ -n "$_val" ] && { echo "$_key"; echo "$_val"; exit 0; }
fi
echo "$_key"; echo ""; exit 0
SH
      chmod +x "${_st}/verify-cmd.sh"

      export PATH="${_st}/bin:${PATH}"
      export CONFIG_FILE="${_st}/conf/valkey.conf"
      export DATA_LINK="${_st}/conf/..data"
      export RELOAD_PARAM_SCRIPT="${_st}/reload-parameter.sh"
      export RELOAD_VERIFY_CMD="${_st}/verify-cmd.sh"
      export MAX_WAIT=0
      export GLOBAL_DEADLINE=9999999999
      export RELOAD_LOG="${_st}/calls.log"
      export APPLIED_VALUES="${_st}/applied.txt"
      export MARKER_FILE="${_st}/applied.marker"
      rm -f "$APPLIED_VALUES" "$RELOAD_LOG" "$MARKER_FILE"
      printf '%s\n' "maxmemory 214748364" "maxmemory-policy volatile-lru" \
        > "${_st}/verify-kv.txt"
      export VERIFY_VALUES="${_st}/verify-kv.txt"
    }
    Before "setup_single_timeout_mock"

    cleanup_single_timeout() {
      rm -rf "${_st:-}"
      unset TIMEOUT_KEY MARKER_FILE
    }
    After "cleanup_single_timeout"

    It "catches single timed-out param via verify"
      export FAKE_NOW=1000
      export FAKE_MTIME=995
      export TIMEOUT_KEY=maxmemory
      When run bash ../scripts/reload-config.sh
      The status should be failure
      The stderr should include "VERIFY FAIL: maxmemory"
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

      cat > "${_td}/bin/hostname" <<'SH'
#!/bin/sh
echo "${FAKE_HOSTNAME:-$(uname -n)}"
SH
      chmod +x "${_td}/bin/hostname"

      cat > "${_td}/bin/mktemp" <<SH
#!/bin/sh
f="${_td}/verify-tmp"
touch "\$f"
echo "\$f"
SH
      chmod +x "${_td}/bin/mktemp"

      # Verify mock: all params differ (to pass pre-check)
      cat > "${_td}/verify-cmd.sh" <<'SH'
#!/bin/sh
_key="$3"
echo "$_key"
echo "DIFFERENT"
SH
      chmod +x "${_td}/verify-cmd.sh"

      export PATH="${_td}/bin:${PATH}"
      export CONFIG_FILE="${_td}/conf/valkey.conf"
      export DATA_LINK="${_td}/conf/..data"
      export RELOAD_PARAM_SCRIPT="/nonexistent/reload-parameter.sh"
      export RELOAD_VERIFY_CMD="${_td}/verify-cmd.sh"
      export MAX_WAIT=0
      export GLOBAL_DEADLINE=9999999999
      export MARKER_FILE="${_td}/applied.marker"
      rm -f "$MARKER_FILE"
      unset APPLIED_VALUES
    }
    Before "setup_timeout_mock"

    cleanup_timeout() { rm -rf "${_td:-}"; unset MARKER_FILE; }
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
