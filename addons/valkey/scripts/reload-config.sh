#!/bin/sh
# reload-config.sh — apply parameters from the mounted ConfigMap to the
# live Valkey process.  Called by the KubeBlocks reconfigure action.
#
# Reads the projected ConfigMap config file and runs CONFIG SET for each
# parameter via reload-parameter.sh.  A freshness gate prevents silent
# false-success when kubelet has not yet projected the updated ConfigMap.

set -eu

CONFIG_FILE="/etc/conf/valkey.conf"
DATA_LINK="/etc/conf/..data"
MAX_WAIT=15

# ── Freshness gate ─────────────────────────────────────────────────────
# kubelet may take up to 60 s to project a ConfigMap update into the pod.
# If the reconfigure action fires before projection, the script would
# read stale data, apply nothing, and exit 0 — a silent false-success.
#
# Strategy: check ..data symlink mtime (primary), then poll for content
# change (secondary).  Fail-safe on timeout so the controller can retry.

_fresh=false

if [ -L "$DATA_LINK" ]; then
  _now=$(date +%s)
  _mtime=$(stat -c %Y "$DATA_LINK" 2>/dev/null || echo 0)
  _age=$(( _now - _mtime ))
  [ "$_age" -le 10 ] && _fresh=true
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
  echo "ERROR: ConfigMap projection not detected after ${MAX_WAIT}s" >&2
  echo "retry-safe: yes" >&2
  exit 1
fi

# ── Apply parameters from the rendered config file ─────────────────────
# Each non-comment, non-empty line is "directive value".  Static params
# (bind, port, daemonize, …) fail with "ERR Unknown option" and are
# silently ignored by reload-parameter.sh.

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '#'*|'') continue ;; esac
  key=${line%% *}
  value=${line#* }
  [ -n "$key" ] || continue
  [ "$key" = "$value" ] && continue
  /scripts/reload-parameter.sh "$key" "$value"
done < "$CONFIG_FILE"
