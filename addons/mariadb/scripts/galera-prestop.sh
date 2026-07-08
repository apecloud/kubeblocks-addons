#!/bin/bash
set -uo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/mysql}"
GALERA_PRESTOP_ORDER_WAIT_SECONDS="${GALERA_PRESTOP_ORDER_WAIT_SECONDS:-70}"
GALERA_PRESTOP_POLL_SECONDS="${GALERA_PRESTOP_POLL_SECONDS:-3}"

log() {
  printf 'galera-prestop: %s\n' "$*"
}

pod_index() {
  printf '%s' "${POD_NAME##*-}"
}

peer_index() {
  local peer="$1"
  local host="${peer%%.*}"
  printf '%s' "${host##*-}"
}

higher_ordinal_peers() {
  local self_index
  self_index="$(pod_index)"
  local peer
  for peer in $(printf '%s' "${PEER_FQDNS:-}" | tr ',' ' '); do
    [ -z "${peer}" ] && continue
    printf '%s\n' "${peer}" | grep -q "^${POD_NAME}\\." && continue
    local index
    index="$(peer_index "${peer}")"
    case "${index}" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ "${index}" -gt "${self_index}" ]; then
      printf '%s\n' "${peer}"
    fi
  done
}

peer_sql_port_open() {
  local peer="$1"
  timeout 2 bash -c "echo > /dev/tcp/${peer}/3306" >/dev/null 2>&1
}

wait_for_higher_ordinals() {
  local peers
  peers="$(higher_ordinal_peers)"
  if [ -z "${peers}" ]; then
    log "no higher-ordinal peers to wait for; proceeding with local shutdown"
    return 0
  fi

  log "waiting up to ${GALERA_PRESTOP_ORDER_WAIT_SECONDS}s for higher-ordinal peers to stop: $(printf '%s' "${peers}" | tr '\n' ' ')"
  local elapsed=0
  while true; do
    local still_open=""
    local peer
    for peer in ${peers}; do
      if peer_sql_port_open "${peer}"; then
        still_open="${still_open} ${peer}"
      fi
    done

    if [ -z "${still_open}" ]; then
      log "higher-ordinal peers have stopped; proceeding with local shutdown"
      return 0
    fi

    if [ "${elapsed}" -ge "${GALERA_PRESTOP_ORDER_WAIT_SECONDS}" ]; then
      log "ordered shutdown degraded: timed out waiting for higher-ordinal peers:${still_open}"
      return 1
    fi

    sleep "${GALERA_PRESTOP_POLL_SECONDS}"
    elapsed=$((elapsed + GALERA_PRESTOP_POLL_SECONDS))
  done
}

local_sql() {
  local statement="$1"
  mariadb -u"${MARIADB_ROOT_USER}" -p"${MARIADB_ROOT_PASSWORD}" \
    -P3306 -h127.0.0.1 \
    -e "${statement}" >/dev/null 2>&1
}

graceful_shutdown() {
  if ! local_sql "SET GLOBAL wsrep_desync=ON;"; then
    log "warning: failed to set wsrep_desync=ON; continuing best-effort shutdown"
  fi

  if ! local_sql "SET GLOBAL wsrep_on=OFF;"; then
    log "warning: failed to set wsrep_on=OFF; continuing best-effort shutdown"
  fi

  if ! mysqladmin -u"${MARIADB_ROOT_USER}" -p"${MARIADB_ROOT_PASSWORD}" \
    -h127.0.0.1 shutdown >/dev/null 2>&1; then
    log "warning: mysqladmin shutdown failed; kubelet may terminate mariadbd"
  fi
}

main() {
  wait_for_higher_ordinals || true
  graceful_shutdown || true
  exit 0
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

main "$@"
