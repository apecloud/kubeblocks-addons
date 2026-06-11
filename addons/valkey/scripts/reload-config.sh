#!/bin/sh
set -eu

CONFIG_FILE="${CONFIG_FILE:-/etc/conf/valkey.conf}"
DATA_LINK="${DATA_LINK:-/etc/conf/..data}"
RELOAD_PARAM_SCRIPT="${RELOAD_PARAM_SCRIPT:-/scripts/reload-parameter.sh}"
RELOAD_VERIFY_CMD="${RELOAD_VERIFY_CMD:-}"
MAX_WAIT="${MAX_WAIT:-15}"
MARKER_FILE="${MARKER_FILE:-/tmp/.reload-config-marker}"
GLOBAL_DEADLINE="${GLOBAL_DEADLINE:-}"

if [ -z "$GLOBAL_DEADLINE" ]; then
  GLOBAL_DEADLINE=$(( $(date +%s) + 50 ))
fi

_trace() { echo "TRACE: $*" >&2; }

_check_deadline() {
  if [ "$(date +%s)" -ge "$GLOBAL_DEADLINE" ]; then
    echo "ERROR: global deadline exceeded" >&2
    rm -f "${_verify_file:-}" 2>/dev/null || true
    exit 1
  fi
}

if [ -n "$RELOAD_VERIFY_CMD" ]; then
  _get_cmd="$RELOAD_VERIFY_CMD"
else
  _port="${SERVICE_PORT:-6379}"
  _get_cmd="timeout 5 valkey-cli --no-auth-warning -h 127.0.0.1 -p $_port"
  [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ] && _get_cmd="$_get_cmd -a $VALKEY_DEFAULT_PASSWORD"
  [ -n "${VALKEY_CLI_TLS_ARGS:-}" ] && _get_cmd="$_get_cmd $VALKEY_CLI_TLS_ARGS"
fi

# ── Phase 1: Pre-check — does file differ from runtime? ──────────────
# Compare config file values against live CONFIG GET.  If any dynamic
# param differs, the file carries unapplied changes and we can safely
# proceed to apply regardless of ConfigMap projection timing.

_needs_apply=false
_has_uncheckable=false
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '#'*|'') continue ;; esac
  key=${line%% *}
  value=${line#* }
  [ -n "$key" ] || continue
  [ "$key" = "$value" ] && continue
  _check_deadline
  _actual=""
  _actual=$($_get_cmd CONFIG GET "$key" 2>/dev/null | tail -1) || true
  if [ -z "$_actual" ]; then
    _trace "pre-check ${key}: uncheckable (CONFIG GET empty)"
    _has_uncheckable=true
    continue
  fi
  _cmp_val="$value"; _cmp_val="${_cmp_val#\"}"; _cmp_val="${_cmp_val%\"}"
  if [ "$_actual" != "$_cmp_val" ]; then
    _trace "pre-check ${key}: diff actual='${_actual}' desired='${_cmp_val}'"
    _needs_apply=true
    break
  else
    _trace "pre-check ${key}: match actual='${_actual}'"
  fi
done < "$CONFIG_FILE"

_trace "pre-check result: _needs_apply=${_needs_apply} _has_uncheckable=${_has_uncheckable}"

# ── Phase 2: File matches runtime — verify freshness before rc=0 ─────
# If every checkable param already matches runtime, succeed only when we
# can positively confirm the file is post-projection.  Without that
# proof the match may be coincidental (stale old values == running
# values) and we must defer so the controller retries after kubelet
# projects the real update.

if [ "$_needs_apply" = "false" ]; then
  _fresh=false
  _current_cksum=$(cksum < "$CONFIG_FILE")

  if [ -f "$MARKER_FILE" ]; then
    _saved=$(cat "$MARKER_FILE")
    if [ "$_current_cksum" != "$_saved" ]; then
      _fresh=true; rm -f "$MARKER_FILE"
    fi
  fi

  if [ "$_fresh" = "false" ]; then
    _initial=$(cat "$CONFIG_FILE"); _waited=0
    while [ "$_waited" -lt "$MAX_WAIT" ]; do
      _check_deadline; sleep 1; _waited=$((_waited + 1))
      _current=$(cat "$CONFIG_FILE")
      if [ "$_current" != "$_initial" ]; then
        _needs_apply=true; _fresh=true; break
      fi
    done
  fi

  if [ "$_fresh" = "true" ] && [ "$_needs_apply" = "false" ]; then
    _trace "fresh confirmed but Phase 1 saw no diff — re-applying from current file"
    _needs_apply=true
  fi

  if [ "$_needs_apply" = "false" ]; then
    echo "$_current_cksum" > "$MARKER_FILE"
    echo "ERROR: file matches runtime, freshness unconfirmed after ${MAX_WAIT}s" >&2
    echo "retry-safe: yes" >&2
    exit 1
  fi
fi

# ── Phase 3: Apply parameters ────────────────────────────────────────
_timeouts=0
_verify_file=$(mktemp "${TMPDIR:-/tmp}/reload-verify.XXXXXX")

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '#'*|'') continue ;; esac
  key=${line%% *}
  value=${line#* }
  [ -n "$key" ] || continue
  [ "$key" = "$value" ] && continue
  _check_deadline

  _apply_val="$value"; _apply_val="${_apply_val#\"}"; _apply_val="${_apply_val%\"}"
  _rc=0
  timeout 5 "$RELOAD_PARAM_SCRIPT" "$key" "$_apply_val" || _rc=$?
  _trace "apply ${key}: rc=${_rc}"
  case "$_rc" in
    0)
      _check_deadline
      _post_val=""
      _post_val=$($_get_cmd CONFIG GET "$key" 2>/dev/null | tail -1) || true
      _trace "post-SET ${key}: readback='${_post_val}'"
      if [ -n "$_post_val" ]; then
        echo "$key $_post_val" >> "$_verify_file"
      else
        echo "$key $_apply_val" >> "$_verify_file"
      fi
      _timeouts=0
      ;;
    2) _timeouts=0 ;;
    124)
      _timeouts=$((_timeouts + 1))
      echo "WARN: timeout on ${key}" >&2
      if [ "$_timeouts" -ge 2 ]; then
        echo "ERROR: 2 consecutive timeouts, Valkey likely unresponsive" >&2
        rm -f "$_verify_file"; exit 1
      fi
      echo "$key $value" >> "$_verify_file"
      ;;
    *)
      rm -f "$_verify_file"; exit "$_rc" ;;
  esac
done < "$CONFIG_FILE"

# ── Phase 4: Verify — CONFIG GET read-back ────────────────────────────
_verify_failed=false

if [ -s "$_verify_file" ]; then
  while IFS= read -r entry; do
    _vkey=${entry%% *}
    _vexpected=${entry#* }
    _check_deadline
    _vactual=""
    _vactual=$($_get_cmd CONFIG GET "$_vkey" 2>/dev/null | tail -1) || true
    if [ -z "$_vactual" ]; then
      _trace "verify ${_vkey}: actual='' expected='${_vexpected}' → FAIL (empty)"
      echo "VERIFY FAIL: ${_vkey}: CONFIG GET returned empty or failed" >&2
      _verify_failed=true
      continue
    fi
    if [ "$_vactual" != "$_vexpected" ]; then
      _trace "verify ${_vkey}: actual='${_vactual}' expected='${_vexpected}' → FAIL"
      echo "VERIFY FAIL: ${_vkey}: runtime='${_vactual}' desired='${_vexpected}'" >&2
      _verify_failed=true
    else
      _trace "verify ${_vkey}: actual='${_vactual}' expected='${_vexpected}' → ok"
    fi
  done < "$_verify_file"
fi

rm -f "$_verify_file"

if [ "$_verify_failed" = "true" ]; then
  echo "ERROR: CONFIG GET read-back verification failed" >&2
  exit 1
fi

rm -f "$MARKER_FILE"
