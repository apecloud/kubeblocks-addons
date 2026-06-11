#!/bin/sh
set -eu

CONFIG_FILE="${CONFIG_FILE:-/etc/conf/valkey.conf}"
DATA_LINK="${DATA_LINK:-/etc/conf/..data}"
RELOAD_PARAM_SCRIPT="${RELOAD_PARAM_SCRIPT:-/scripts/reload-parameter.sh}"
RELOAD_VERIFY_CMD="${RELOAD_VERIFY_CMD:-}"
MAX_WAIT="${MAX_WAIT:-15}"
APPLY_BUDGET="${APPLY_BUDGET:-50}"
MARKER_FILE="${MARKER_FILE:-/tmp/.reload-config-marker}"

# ── Freshness gate ─────────────────────────────────────────────────────
# kubelet may take up to 60s to project a ConfigMap update into the pod.
# If the reconfigure action fires before projection, the script reads stale
# data, applies old values, and returns rc=0 — a silent false-success.
#
# Strategy:
#   1. Retry detection via persistent marker (cksum of last-seen content).
#      If content changed since the last failed attempt, it is fresh.
#   2. ..data symlink mtime (kubelet atomically swaps this on projection).
#   3. Content-change polling (secondary, catches slow projections).
#   4. Fail-safe: exit 1 with retry-safe hint so the controller retries.

_fresh=false
_current_cksum=$(cksum < "$CONFIG_FILE")

if [ -f "$MARKER_FILE" ]; then
  _saved_cksum=$(cat "$MARKER_FILE")
  if [ "$_current_cksum" != "$_saved_cksum" ]; then
    _fresh=true
    rm -f "$MARKER_FILE"
  fi
fi

if [ "$_fresh" = "false" ] && [ -L "$DATA_LINK" ]; then
  _now=$(date +%s)
  _mtime=$(stat -c %Y "$DATA_LINK" 2>/dev/null || echo 0)
  _age=$(( _now - _mtime ))
  [ "$_age" -le 120 ] && _fresh=true
fi

if [ "$_fresh" = "false" ]; then
  _initial=$(cat "$CONFIG_FILE")
  _waited=0
  while [ "$_waited" -lt "$MAX_WAIT" ]; do
    sleep 1; _waited=$(( _waited + 1 ))
    _current=$(cat "$CONFIG_FILE")
    if [ "$_current" != "$_initial" ]; then
      _fresh=true; break
    fi
  done
fi

if [ "$_fresh" = "false" ]; then
  echo "$_current_cksum" > "$MARKER_FILE"
  echo "ERROR: ConfigMap projection not detected after ${MAX_WAIT}s" >&2
  echo "retry-safe: yes" >&2
  exit 1
fi

# ── Apply parameters from the rendered config file ─────────────────────
# Budget guard: stay well within the kbagent 60s action boundary.
# Per-param timeout (5s) prevents a single hung valkey-cli from blowing
# the budget.  Two consecutive timeouts abort (server likely unresponsive).
# reload-parameter.sh exit codes: 0=OK, 2=static/skip, 1=error.

_apply_start=$(date +%s)
_timeouts=0
_verify_file=$(mktemp "${TMPDIR:-/tmp}/reload-verify.XXXXXX")

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '#'*|'') continue ;; esac
  key=${line%% *}
  value=${line#* }
  [ -n "$key" ] || continue
  [ "$key" = "$value" ] && continue

  _elapsed=$(( $(date +%s) - _apply_start ))
  if [ "$_elapsed" -ge "$APPLY_BUDGET" ]; then
    echo "ERROR: apply budget ${APPLY_BUDGET}s exceeded at param ${key}" >&2
    rm -f "$_verify_file"
    exit 1
  fi

  _rc=0
  timeout 5 "$RELOAD_PARAM_SCRIPT" "$key" "$value" || _rc=$?
  case "$_rc" in
    0) echo "$key $value" >> "$_verify_file"; _timeouts=0 ;;
    2) _timeouts=0 ;;
    124)
      _timeouts=$(( _timeouts + 1 ))
      echo "WARN: timeout on ${key}" >&2
      if [ "$_timeouts" -ge 2 ]; then
        echo "ERROR: 2 consecutive timeouts, Valkey likely unresponsive" >&2
        rm -f "$_verify_file"
        exit 1
      fi ;;
    *)
      rm -f "$_verify_file"
      exit "$_rc" ;;
  esac
done < "$CONFIG_FILE"

# ── Verify: CONFIG GET read-back ──────────────────────────────────────
# For each param where CONFIG SET succeeded, confirm the runtime value
# matches.  This catches silent false-success (stale file + no-op SET).

_verify_failed=false

if [ -s "$_verify_file" ]; then
  if [ -n "$RELOAD_VERIFY_CMD" ]; then
    _get_cmd="$RELOAD_VERIFY_CMD"
  else
    _port="${SERVICE_PORT:-6379}"
    _get_cmd="timeout 5 valkey-cli --no-auth-warning -h 127.0.0.1 -p $_port"
    [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ] && _get_cmd="$_get_cmd -a $VALKEY_DEFAULT_PASSWORD"
    [ -n "${VALKEY_CLI_TLS_ARGS:-}" ] && _get_cmd="$_get_cmd $VALKEY_CLI_TLS_ARGS"
  fi

  while IFS= read -r entry; do
    _vkey=${entry%% *}
    _vexpected=${entry#* }
    _vactual=""
    _vactual=$($_get_cmd CONFIG GET "$_vkey" 2>/dev/null | tail -1) || true
    [ -z "$_vactual" ] && continue
    if [ "$_vactual" != "$_vexpected" ]; then
      echo "VERIFY FAIL: ${_vkey}: runtime='${_vactual}' desired='${_vexpected}'" >&2
      _verify_failed=true
    fi
  done < "$_verify_file"
fi

rm -f "$_verify_file"

if [ "$_verify_failed" = "true" ]; then
  echo "ERROR: CONFIG GET read-back verification failed" >&2
  exit 1
fi

rm -f "$MARKER_FILE"
