#!/bin/bash

# Promote a Patroni standby_cluster by removing the dynamic standby_cluster
# configuration. Patroni documents this as the supported manual promotion path
# for a remote standby cluster; the caller must first fence/stop the source.
set -euo pipefail

patroni_url() {
  printf 'http://%s:8008' "${CURRENT_POD_IP:-localhost}"
}

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true|yes|1) return 0 ;;
    *) return 1 ;;
  esac
}

require_force() {
  if ! is_true "${force:-}"; then
    echo "force=true is required; promote only after the source cluster is fenced/stopped."
    return 1
  fi
}

require_standby_mode() {
  if ! printf '%s' "${PG_MODE:-}" | tr '[:upper:]' '[:lower:]' | grep -q 'standby'; then
    echo "PG_MODE=${PG_MODE:-<unset>} is not standby; refusing DR standby promotion."
    return 1
  fi
}

is_standby_leader() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "$(patroni_url)/standby-leader" || true)"
  [ "$code" = "200" ]
}

patch_remove_standby_cluster() {
  echo "Removing standby_cluster from Patroni dynamic config on $(patroni_url)"
  curl -fsS -X PATCH -d '{"standby_cluster":null}' "$(patroni_url)/config"
}

wait_read_write() {
  local timeout="${PROMOTE_TIMEOUT_SECONDS:-300}"
  local deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if curl -fsS -o /dev/null "$(patroni_url)/read-write"; then
      echo "Patroni reports read-write primary after standby promotion."
      return 0
    fi
    sleep 5
  done
  echo "Timed out waiting for Patroni read-write primary after standby promotion."
  return 1
}

promote_standby() {
  require_force
  require_standby_mode

  if ! is_standby_leader; then
    echo "Current pod is not Patroni standby leader; nothing to promote on this pod."
    return 0
  fi

  patch_remove_standby_cluster
  wait_read_write
}

${__SOURCED__:+false} : || return 0

promote_standby
