#!/bin/bash
set -uo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/mysql}"
GALERA_PRESTOP_ORDER_WAIT_SECONDS="${GALERA_PRESTOP_ORDER_WAIT_SECONDS:-60}"
GALERA_PRESTOP_POLL_SECONDS="${GALERA_PRESTOP_POLL_SECONDS:-3}"
GALERA_PRESTOP_PROBE_TIMEOUT_SECONDS="${GALERA_PRESTOP_PROBE_TIMEOUT_SECONDS:-2}"
GALERA_PRESTOP_SQL_TIMEOUT_SECONDS="${GALERA_PRESTOP_SQL_TIMEOUT_SECONDS:-3}"
GALERA_PRESTOP_SHUTDOWN_TIMEOUT_SECONDS="${GALERA_PRESTOP_SHUTDOWN_TIMEOUT_SECONDS:-40}"
GALERA_PRESTOP_TERMINATION_GRACE_SECONDS="${GALERA_PRESTOP_TERMINATION_GRACE_SECONDS:-120}"
GALERA_PRESTOP_SAFETY_MARGIN_SECONDS="${GALERA_PRESTOP_SAFETY_MARGIN_SECONDS:-5}"
GALERA_PRESTOP_CONTAINER_LOG_PATH="${GALERA_PRESTOP_CONTAINER_LOG_PATH:-/proc/1/fd/1}"
GALERA_PRESTOP_DEGRADED_LOG="${GALERA_PRESTOP_DEGRADED_LOG:-${DATA_DIR}/log/galera-prestop-degraded.log}"

log() {
  local line="galera-prestop: $*"
  printf '%s\n' "${line}"
  if [ -n "${GALERA_PRESTOP_CONTAINER_LOG_PATH}" ]; then
    { printf '%s\n' "${line}" >> "${GALERA_PRESTOP_CONTAINER_LOG_PATH}"; } 2>/dev/null && return 0
  fi
  return 1
}

record_degraded() {
  local detail="$*"
  local timestamp
  local persisted=0
  local mirrored=0
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')"
  mkdir -p "$(dirname "${GALERA_PRESTOP_DEGRADED_LOG}")" 2>/dev/null || true
  if printf '%s pod=%s %s\n' "${timestamp}" "${POD_NAME:-<unset>}" "${detail}" \
    >> "${GALERA_PRESTOP_DEGRADED_LOG}" 2>/dev/null; then
    persisted=1
  fi
  if log "ordered shutdown degraded: ${detail}"; then
    mirrored=1
  fi
  if [ "${persisted}" -ne 1 ] && [ "${mirrored}" -ne 1 ]; then
    DEGRADED_EVIDENCE_WRITE_FAILED=1
    return 1
  fi
  return 0
}

monotonic_seconds() {
  printf '%s' "${SECONDS}"
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

validate_inputs() {
  local pod_prefix="${POD_NAME:-}"
  pod_prefix="${pod_prefix%-*}"
  local self_index="${POD_NAME:-}"
  self_index="${self_index##*-}"
  if [ -z "${POD_NAME:-}" ] \
    || [ -z "${pod_prefix}" ] \
    || [ "${pod_prefix}" = "${POD_NAME}" ] \
    || ! is_uint "${self_index}"; then
    VALIDATION_ERROR="reason=invalid_pod_name value=${POD_NAME:-<unset>}"
    return 1
  fi

  case "${PEER_FQDNS:-}" in
    '')
      VALIDATION_ERROR="reason=missing_peer_fqdns"
      return 1
      ;;
    ,*|*,|*,,*|*[[:space:]]*)
      VALIDATION_ERROR="reason=invalid_peer_fqdns_list"
      return 1
      ;;
  esac

  local peer
  local self_found=0
  for peer in $(printf '%s' "${PEER_FQDNS}" | tr ',' ' '); do
    local host="${peer%%.*}"
    local index
    index="$(peer_index "${peer}")"
    if [ -z "${peer}" ] || [ "${host}" = "${peer}" ] || ! is_uint "${index}"; then
      VALIDATION_ERROR="reason=invalid_peer_fqdn value=${peer:-<empty>}"
      return 1
    fi
    case "${peer}" in
      "${POD_NAME}."*) self_found=1 ;;
    esac
  done
  if [ "${self_found}" -ne 1 ]; then
    VALIDATION_ERROR="reason=self_missing_from_peer_fqdns pod=${POD_NAME}"
    return 1
  fi

  if ! is_uint "${GALERA_PRESTOP_ORDER_WAIT_SECONDS}" \
    || ! is_uint "${GALERA_PRESTOP_POLL_SECONDS}" \
    || ! is_uint "${GALERA_PRESTOP_PROBE_TIMEOUT_SECONDS}" \
    || ! is_uint "${GALERA_PRESTOP_SQL_TIMEOUT_SECONDS}" \
    || ! is_uint "${GALERA_PRESTOP_SHUTDOWN_TIMEOUT_SECONDS}" \
    || ! is_uint "${GALERA_PRESTOP_TERMINATION_GRACE_SECONDS}" \
    || ! is_uint "${GALERA_PRESTOP_SAFETY_MARGIN_SECONDS}" \
    || [ "${GALERA_PRESTOP_POLL_SECONDS}" -eq 0 ] \
    || [ "${GALERA_PRESTOP_PROBE_TIMEOUT_SECONDS}" -eq 0 ] \
    || [ "${GALERA_PRESTOP_SQL_TIMEOUT_SECONDS}" -eq 0 ] \
    || [ "${GALERA_PRESTOP_SHUTDOWN_TIMEOUT_SECONDS}" -eq 0 ] \
    || [ "${GALERA_PRESTOP_TERMINATION_GRACE_SECONDS}" -eq 0 ] \
    || [ "${GALERA_PRESTOP_SAFETY_MARGIN_SECONDS}" -eq 0 ]; then
    VALIDATION_ERROR="reason=invalid_timeout_configuration"
    return 1
  fi

  local worst_case_seconds=$((
    GALERA_PRESTOP_ORDER_WAIT_SECONDS
    + (2 * GALERA_PRESTOP_SQL_TIMEOUT_SECONDS)
    + GALERA_PRESTOP_SHUTDOWN_TIMEOUT_SECONDS
    + GALERA_PRESTOP_SAFETY_MARGIN_SECONDS
  ))
  if [ "${worst_case_seconds}" -gt "${GALERA_PRESTOP_TERMINATION_GRACE_SECONDS}" ]; then
    VALIDATION_ERROR="reason=timeout_budget_exceeds_termination_grace worst_case=${worst_case_seconds} grace=${GALERA_PRESTOP_TERMINATION_GRACE_SECONDS}"
    return 1
  fi

  return 0
}

pod_index() {
  local name="${POD_NAME:-}"
  printf '%s' "${name##*-}"
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
    case "${peer}" in
      "${POD_NAME}."*) continue ;;
    esac
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

peer_sql_port_state() {
  local peer="$1"
  local probe_timeout="${2:-${GALERA_PRESTOP_PROBE_TIMEOUT_SECONDS}}"
  local output
  local rc
  # ${1} is intentionally expanded by the bounded child bash, not this shell.
  # shellcheck disable=SC2016
  output="$(LC_ALL=C timeout "${probe_timeout}" bash -c 'echo > "/dev/tcp/${1}/3306"' _ "${peer}" 2>&1)"
  rc=$?
  if [ "${rc}" -eq 0 ]; then
    printf 'open'
    return 0
  fi

  case "${rc}" in
    124|137)
      printf 'timeout'
      return 0
      ;;
  esac

  case "${output}" in
    *"Connection refused"*) printf 'closed' ;;
    *"Name or service not known"*|*"Temporary failure in name resolution"*|*"No address associated"*)
      printf 'dns-failure'
      ;;
    *) printf 'unreachable' ;;
  esac
}

wait_for_higher_ordinals() {
  local peers
  peers="$(higher_ordinal_peers)"
  if [ -z "${peers}" ]; then
    log "no higher-ordinal peers to wait for; proceeding with local shutdown"
    return 0
  fi

  log "waiting up to ${GALERA_PRESTOP_ORDER_WAIT_SECONDS}s for higher-ordinal peers to stop: $(printf '%s' "${peers}" | tr '\n' ' ')"
  local started_at
  started_at="$(monotonic_seconds)"
  local deadline=$((started_at + GALERA_PRESTOP_ORDER_WAIT_SECONDS))
  while true; do
    local now
    now="$(monotonic_seconds)"
    local remaining=$((deadline - now))
    if [ "${remaining}" -le 0 ]; then
      local exhausted=""
      local exhausted_peer
      for exhausted_peer in ${peers}; do
        exhausted="${exhausted} ${exhausted_peer}(budget-exhausted)"
      done
      record_degraded "reason=order_wait_timeout elapsed_seconds=$((now - started_at)) peers:${exhausted}"
      return 1
    fi

    local still_waiting=""
    local peer
    for peer in ${peers}; do
      now="$(monotonic_seconds)"
      remaining=$((deadline - now))
      if [ "${remaining}" -le 0 ]; then
        still_waiting="${still_waiting} ${peer}(budget-exhausted)"
        continue
      fi

      local probe_timeout="${GALERA_PRESTOP_PROBE_TIMEOUT_SECONDS}"
      if [ "${remaining}" -lt "${probe_timeout}" ]; then
        probe_timeout="${remaining}"
      fi
      local state
      state="$(peer_sql_port_state "${peer}" "${probe_timeout}")"
      case "${state}" in
        closed)
          # A refused connection is only the local observation that the SQL
          # listener is down. It is the cleanest signal available to this
          # preStop hook, but it is not proof that the peer wrote grastate.dat.
          ;;
        open|timeout|dns-failure|unreachable)
          still_waiting="${still_waiting} ${peer}(${state})"
          ;;
        *)
          still_waiting="${still_waiting} ${peer}(unknown:${state})"
          ;;
      esac
    done

    if [ -z "${still_waiting}" ]; then
      log "higher-ordinal peers have stopped; proceeding with local shutdown"
      return 0
    fi

    now="$(monotonic_seconds)"
    remaining=$((deadline - now))
    if [ "${remaining}" -le 0 ]; then
      record_degraded "reason=order_wait_timeout elapsed_seconds=$((now - started_at)) peers:${still_waiting}"
      return 1
    fi

    local sleep_seconds="${GALERA_PRESTOP_POLL_SECONDS}"
    if [ "${remaining}" -lt "${sleep_seconds}" ]; then
      sleep_seconds="${remaining}"
    fi
    sleep "${sleep_seconds}"
  done
}

local_sql() {
  local statement="$1"
  timeout "${GALERA_PRESTOP_SQL_TIMEOUT_SECONDS}" \
    mariadb -u"${MARIADB_ROOT_USER:-}" -p"${MARIADB_ROOT_PASSWORD:-}" \
    -P3306 -h127.0.0.1 \
    -e "${statement}" >/dev/null 2>&1
}

graceful_shutdown() {
  if ! local_sql "SET GLOBAL wsrep_desync=ON;"; then
    log "warning: failed to set wsrep_desync=ON; continuing best-effort shutdown"
    record_degraded "reason=wsrep_desync_failed"
  fi

  if ! local_sql "SET GLOBAL wsrep_on=OFF;"; then
    log "warning: failed to set wsrep_on=OFF; continuing best-effort shutdown"
    record_degraded "reason=wsrep_disable_failed"
  fi

  if ! timeout "${GALERA_PRESTOP_SHUTDOWN_TIMEOUT_SECONDS}" \
    mysqladmin -u"${MARIADB_ROOT_USER:-}" -p"${MARIADB_ROOT_PASSWORD:-}" \
    -h127.0.0.1 shutdown >/dev/null 2>&1; then
    log "warning: mysqladmin shutdown failed; kubelet may terminate mariadbd"
    record_degraded "reason=mysqladmin_shutdown_failed"
  fi
}

main() {
  DEGRADED_EVIDENCE_WRITE_FAILED=0
  if ! validate_inputs; then
    record_degraded "${VALIDATION_ERROR}"
  else
    wait_for_higher_ordinals || true
  fi
  graceful_shutdown || true
  if [ "${DEGRADED_EVIDENCE_WRITE_FAILED}" -ne 0 ]; then
    printf 'galera-prestop: degraded evidence sinks unavailable; emitting FailedPreStopHook\n' >&2
    return 1
  fi
  return 0
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

main "$@"
