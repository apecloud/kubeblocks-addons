#!/bin/sh
set -eu

CONFIG_FILE="${CONFIG_FILE:-/etc/conf/valkey.conf}"
RELOAD_PARAM_SCRIPT="${RELOAD_PARAM_SCRIPT:-/scripts/reload-parameter.sh}"
RELOAD_VERIFY_CMD="${RELOAD_VERIFY_CMD:-}"
MAX_WAIT="${MAX_WAIT:-15}"
MARKER_FILE="${MARKER_FILE:-/data/reload-config-applied.marker}"
GLOBAL_DEADLINE="${GLOBAL_DEADLINE:-}"

if [ -z "$GLOBAL_DEADLINE" ]; then
  GLOBAL_DEADLINE=$(( $(date +%s) + 50 ))
fi

_trace() { echo "TRACE: $*" >&2; }

_snapshot_file=
_verify_file=

_cleanup() {
  rm -f "${_snapshot_file:-}" "${_verify_file:-}" 2>/dev/null || true
}
trap '_cleanup' 0
trap '_cleanup; exit 1' 1 2 15

_build_marker() {
  _bm_host=$(hostname 2>/dev/null)
  _bm_cksum=$(cksum "$1" 2>/dev/null | cut -d' ' -f1)
  _bm_path=${2:-$1}
  [ -n "$_bm_host" ] && [ -n "$_bm_path" ] && [ -n "$_bm_cksum" ] || return 1
  echo "${_bm_host}:${_bm_path}:${_bm_cksum}"
}

_write_marker() {
  _wm_val=$(_build_marker "$1" "${2:-$1}") || { _trace "marker build failed"; return 1; }
  if echo "$_wm_val" > "$MARKER_FILE" 2>/dev/null && [ -f "$MARKER_FILE" ]; then
    _trace "wrote marker: ${_wm_val}"
    return 0
  fi
  _trace "marker write failed: ${MARKER_FILE}"
  return 2
}

_check_deadline() {
  if [ "$(date +%s)" -ge "$GLOBAL_DEADLINE" ]; then
    echo "ERROR: global deadline exceeded" >&2
    exit 1
  fi
}

_target_file_attested=false
_target_file_expected_sha=
_parse_target_file_attestation() {
  _cfa_updated=${KB_CONFIG_FILES_UPDATED:-}
  [ -n "$_cfa_updated" ] || return 0

  _cfa_target_count=0
  _cfa_remaining=$_cfa_updated
  while [ -n "$_cfa_remaining" ]; do
    case "$_cfa_remaining" in
      *,*)
        _cfa_entry=${_cfa_remaining%%,*}
        _cfa_remaining=${_cfa_remaining#*,}
        ;;
      *)
        _cfa_entry=$_cfa_remaining
        _cfa_remaining=
        ;;
    esac
    _cfa_file=${_cfa_entry%:*}
    _cfa_expected=${_cfa_entry##*:}
    [ "$_cfa_file" = "$CONFIG_FILE" ] || continue

    _cfa_target_count=$((_cfa_target_count + 1))
    if [ "$_cfa_target_count" -gt 1 ]; then
      echo "ERROR: target checksum attestation is ambiguous for ${CONFIG_FILE}" >&2
      echo "retry-safe: yes" >&2
      return 1
    fi

    case "$_cfa_expected" in
      ''|*[!0-9a-f]*)
        echo "ERROR: target checksum is malformed for ${CONFIG_FILE}" >&2
        echo "retry-safe: yes" >&2
        return 1
        ;;
    esac
    if [ "${#_cfa_expected}" -ne 64 ]; then
      echo "ERROR: target checksum is malformed for ${CONFIG_FILE}" >&2
      echo "retry-safe: yes" >&2
      return 1
    fi

    _target_file_expected_sha=$_cfa_expected
    _target_file_attested=true
  done
}

_snapshot_config() {
  if [ -z "$_snapshot_file" ]; then
    _snapshot_file=$(mktemp "${TMPDIR:-/tmp}/reload-config-snapshot.XXXXXX") || {
      echo "ERROR: cannot allocate immutable config snapshot" >&2
      echo "retry-safe: yes" >&2
      return 1
    }
  fi
  if ! cp "$CONFIG_FILE" "$_snapshot_file" 2>/dev/null; then
    echo "ERROR: cannot create immutable config snapshot from ${CONFIG_FILE}" >&2
    echo "retry-safe: yes" >&2
    return 1
  fi
}

_verify_snapshot_attestation() {
  [ "$_target_file_attested" = "true" ] || return 0
  _vsa_output=$(sha256sum "$_snapshot_file" 2>/dev/null) || {
    echo "ERROR: cannot calculate target checksum for ${CONFIG_FILE}" >&2
    echo "retry-safe: yes" >&2
    return 1
  }
  _vsa_actual=${_vsa_output%% *}
  if [ "$_vsa_actual" != "$_target_file_expected_sha" ]; then
    echo "ERROR: target checksum mismatch for ${CONFIG_FILE}" >&2
    echo "retry-safe: yes" >&2
    return 1
  fi
  _trace "target checksum verified on immutable snapshot: ${CONFIG_FILE}"
}

_check_live_matches_snapshot() {
  _clms_snapshot_output=$(sha256sum "$_snapshot_file" 2>/dev/null) || {
    echo "ERROR: cannot calculate immutable snapshot checksum for ${CONFIG_FILE}" >&2
    echo "retry-safe: yes" >&2
    return 1
  }
  _clms_live_output=$(sha256sum "$CONFIG_FILE" 2>/dev/null) || {
    echo "ERROR: cannot calculate live target checksum for ${CONFIG_FILE}" >&2
    echo "retry-safe: yes" >&2
    return 1
  }
  _clms_snapshot=${_clms_snapshot_output%% *}
  _clms_live=${_clms_live_output%% *}
  if [ "$_clms_live" != "$_clms_snapshot" ]; then
    echo "ERROR: target file drifted after snapshot verification: ${CONFIG_FILE}" >&2
    echo "retry-safe: yes" >&2
    return 1
  fi
}

_strip_quotes() {
  _sq_value=$(printf '%s\n' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  _sq_value=${_sq_value#\"}
  _sq_value=${_sq_value%\"}
  printf '%s\n' "$_sq_value"
}

# KubeBlocks runs one reconfigure action per ReconfigureArgs row. An attested
# invocation therefore owns exactly one key/value pair, not the whole file.
_target_key=
_target_value=
_parse_current_action_row() {
  [ "$_target_file_attested" = "true" ] || return 0
  if [ "$#" -ne 2 ]; then
    echo "ERROR: current-action row is malformed: expected exactly one key/value pair" >&2
    echo "retry-safe: yes" >&2
    return 1
  fi

  _target_key=$1
  case "$_target_key" in
    ''|*[!A-Za-z0-9_.-]*)
      echo "ERROR: current-action row is malformed: invalid key" >&2
      echo "retry-safe: yes" >&2
      return 1
      ;;
  esac
  _target_value=$(_strip_quotes "$2")

  _pcar_count=0
  _pcar_snapshot_value=
  while IFS= read -r _pcar_line || [ -n "$_pcar_line" ]; do
    case "$_pcar_line" in '#'*|'') continue ;; esac
    _pcar_key=${_pcar_line%% *}
    [ "$_pcar_key" = "$_target_key" ] || continue
    _pcar_count=$((_pcar_count + 1))
    _pcar_snapshot_value=$(_strip_quotes "${_pcar_line#* }")
  done < "$_snapshot_file"

  case "$_pcar_count" in
    0)
      echo "ERROR: current-action target ${_target_key} is absent from immutable config snapshot" >&2
      echo "retry-safe: yes" >&2
      return 1
      ;;
    1) ;;
    *)
      echo "ERROR: current-action target ${_target_key} is ambiguous in immutable config snapshot" >&2
      echo "retry-safe: yes" >&2
      return 1
      ;;
  esac

  if [ "$_pcar_snapshot_value" != "$_target_value" ]; then
    echo "ERROR: current-action target ${_target_key} does not match immutable config snapshot" >&2
    echo "retry-safe: yes" >&2
    return 1
  fi
}

_parse_target_file_attestation || exit 1
_snapshot_config || exit 1
_verify_snapshot_attestation || exit 1
_check_live_matches_snapshot || exit 1
_parse_current_action_row "$@" || exit 1

if [ -n "$RELOAD_VERIFY_CMD" ]; then
  _get_cmd="$RELOAD_VERIFY_CMD"
else
  _port="${SERVICE_PORT:-6379}"
  _get_cmd="timeout 5 valkey-cli --no-auth-warning -h 127.0.0.1 -p $_port"
  [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ] && _get_cmd="$_get_cmd -a $VALKEY_DEFAULT_PASSWORD"
  [ -n "${VALKEY_CLI_TLS_ARGS:-}" ] && _get_cmd="$_get_cmd $VALKEY_CLI_TLS_ARGS"
fi

_run_attested_action_row() {
  _check_deadline
  _raa_actual=""
  _raa_actual=$($_get_cmd CONFIG GET "$_target_key" 2>/dev/null | tail -1) || true
  if [ -z "$_raa_actual" ]; then
    echo "ERROR: updated target ${_target_key} is uncheckable by CONFIG GET" >&2
    echo "retry-safe: yes" >&2
    return 1
  fi

  if [ "$_raa_actual" = "$_target_value" ]; then
    _check_live_matches_snapshot || return 1
    _trace "target checksum verified and current row matches runtime; accepting idempotent no-op"
    _write_marker "$_snapshot_file" "$CONFIG_FILE" || _trace "no-op marker write failed"
    return 0
  fi

  _trace "pre-check ${_target_key}: diff actual='${_raa_actual}' desired='${_target_value}'"
  _check_live_matches_snapshot || return 1

  _raa_rc=0
  timeout 5 "$RELOAD_PARAM_SCRIPT" "$_target_key" "$_target_value" || _raa_rc=$?
  _trace "apply ${_target_key}: rc=${_raa_rc}"
  case "$_raa_rc" in
    0) ;;
    124)
      echo "ERROR: timeout applying current-action target ${_target_key}" >&2
      echo "retry-safe: yes" >&2
      return 1
      ;;
    2)
      echo "ERROR: current-action target ${_target_key} was not dynamically applied" >&2
      echo "retry-safe: yes" >&2
      return 1
      ;;
    *) return "$_raa_rc" ;;
  esac

  _check_deadline
  _raa_post=""
  _raa_post=$($_get_cmd CONFIG GET "$_target_key" 2>/dev/null | tail -1) || true
  if [ -z "$_raa_post" ]; then
    echo "VERIFY FAIL: ${_target_key}: CONFIG GET returned empty or failed" >&2
    return 1
  fi
  if [ "$_raa_post" != "$_target_value" ]; then
    echo "VERIFY FAIL: ${_target_key}: runtime='${_raa_post}' desired='${_target_value}'" >&2
    return 1
  fi

  _check_live_matches_snapshot || return 1
  _trace "verify ${_target_key}: actual='${_raa_post}' expected='${_target_value}' -> ok"
  _write_marker "$_snapshot_file" "$CONFIG_FILE" || \
    _trace "marker write failed - apply succeeded, future VScale may need retry"
}

if [ "$_target_file_attested" = "true" ]; then
  _run_attested_action_row
  exit $?
fi

# ── Phase 1: Pre-check — does file differ from runtime? ──────────────
# Compare config file values against live CONFIG GET.  If any dynamic
# param differs, the file carries unapplied changes and we can safely
# proceed to apply regardless of ConfigMap projection timing.

_needs_apply=false
_has_uncheckable=false
_checked_any=false
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
    _checked_any=true
    break
  else
    _trace "pre-check ${key}: match actual='${_actual}'"
    _checked_any=true
  fi
done < "$_snapshot_file"

_trace "pre-check result: _needs_apply=${_needs_apply} _has_uncheckable=${_has_uncheckable} _checked_any=${_checked_any}"

# ── Phase 2: Legacy file-wide path requires projected-content change ───
# Older controllers omit the target checksum attestation. Retain the strict
# bounded wait instead of accepting a potentially stale matching file.
if [ "$_needs_apply" = "false" ]; then
  _initial=$(cat "$_snapshot_file"); _waited=0
  while [ "$_waited" -lt "$MAX_WAIT" ]; do
    _check_deadline; sleep 1; _waited=$((_waited + 1))
    _current=$(cat "$CONFIG_FILE")
    if [ "$_current" != "$_initial" ]; then
      _snapshot_config || exit 1
      _needs_apply=true; break
    fi
  done

  if [ "$_needs_apply" = "false" ]; then
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
      echo "$key $_apply_val" >> "$_verify_file"
      ;;
    *)
      rm -f "$_verify_file"; exit "$_rc" ;;
  esac
done < "$_snapshot_file"

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
_verify_file=

if [ "$_verify_failed" = "true" ]; then
  echo "ERROR: CONFIG GET read-back verification failed" >&2
  exit 1
fi

_write_marker "$_snapshot_file" "$CONFIG_FILE" || _trace "Phase 4: marker write failed — apply succeeded, future VScale may need retry"
