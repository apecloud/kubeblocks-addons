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

warn_if_source_reachable() {
  local endpoint="${sourceEndpoint:-}"
  if [ -z "$endpoint" ]; then
    echo "No sourceEndpoint provided; skipping best-effort source reachability probe."
    return 0
  fi

  local host="${endpoint%:*}" port="${endpoint##*:}"
  if [ -z "$host" ] || [ -z "$port" ] || [ "$host" = "$port" ] || ! [[ "$port" =~ ^[0-9]+$ ]]; then
    echo "WARNING: invalid sourceEndpoint '$endpoint'; expected host:port. Skipping source reachability probe."
    return 0
  fi

  if timeout 3 bash -c 'cat < /dev/null > "/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
    echo "WARNING: sourceEndpoint ${endpoint} is still TCP-reachable while promoting standby. Ensure the source is fenced/stopped to avoid split-brain."
  else
    echo "sourceEndpoint ${endpoint} is not TCP-reachable in best-effort probe."
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

warn_manual_failback_boundary() {
  cat <<'EOF'
WARNING: DR standby promotion only activates this Patroni cluster.
WARNING: The KubeBlocks Cluster spec may still contain PG_MODE=standby and serviceRefs to the old source.
WARNING: Before restarting the old source, update the promoted Cluster spec to remove standby config and either delete or rebuild the old source as a standby.
WARNING: Automatic failback is not part of pg-promote-standby.
EOF
}

promote_standby() {
  require_force
  warn_if_source_reachable
  require_standby_mode

  if ! is_standby_leader; then
    echo "Current pod is not Patroni standby leader; nothing to promote on this pod."
    return 0
  fi

  patch_remove_standby_cluster
  wait_read_write
  warn_manual_failback_boundary
}

${__SOURCED__:+false} : || return 0

promote_standby
