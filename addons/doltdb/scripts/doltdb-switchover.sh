#!/bin/sh
set -eu

: "${DOLT_SQL_BIN:=/scripts/doltdb-sql.sh}"
: "${DOLT_LOCAL_SQL_HOST:=127.0.0.1}"
: "${DOLT_SWITCHOVER_WAIT_SECONDS:=300}"
: "${DOLT_SWITCHOVER_POLL_SECONDS:=2}"
: "${DOLT_SWITCHOVER_LOG_DIR:=/tmp/kb-lifecycle}"

LOG_FILE="${DOLT_SWITCHOVER_LOG_DIR}/doltdb-switchover.log"

log() {
  printf '%s\n' "$*" >&2
}

die() {
  log "ERROR: $*"
  return 1
}

trim_field() {
  printf '%s\n' "$1" | tr -d '"' | tr -d '[:space:]'
}

sql_query() {
  host="$1"
  query="$2"
  DOLT_SQL_HOST="$host" DOLT_NO_DATABASE=true "$DOLT_SQL_BIN" "$query"
}

query_role_epoch() {
  host="$1"
  result="$(sql_query "$host" "SELECT @@GLOBAL.dolt_cluster_role, @@GLOBAL.dolt_cluster_role_epoch;")"
  line="$(printf '%s\n' "$result" | awk 'NF { last = $0 } END { print last }' | tr -d '\r')"
  role="$(trim_field "$(printf '%s\n' "$line" | cut -d, -f1)")"
  epoch="$(trim_field "$(printf '%s\n' "$line" | cut -d, -f2)")"

  case "$role" in
    primary|standby)
      ;;
    detected_broken_config)
      die "Dolt cluster role is detected_broken_config on ${host} at epoch ${epoch}"
      return 1
      ;;
    *)
      die "Unexpected Dolt cluster role output from ${host}: ${line}"
      return 1
      ;;
  esac

  case "$epoch" in
    ''|*[!0-9]*)
      die "Unexpected Dolt cluster role epoch from ${host}: ${line}"
      return 1
      ;;
  esac

  printf '%s %s\n' "$role" "$epoch"
}

find_fqdn_by_name() {
  name="$1"
  old_ifs="$IFS"
  IFS=,
  set -- ${DOLT_POD_FQDN_LIST:-}
  IFS="$old_ifs"

  for fqdn do
    [ -n "$fqdn" ] || continue
    if [ "$fqdn" = "$name" ]; then
      printf '%s\n' "$fqdn"
      return 0
    fi
    case "$fqdn" in
      "$name".*)
        printf '%s\n' "$fqdn"
        return 0
        ;;
    esac
  done

  return 1
}

resolve_current_fqdn() {
  if [ -n "${KB_SWITCHOVER_CURRENT_FQDN:-}" ]; then
    printf '%s\n' "$KB_SWITCHOVER_CURRENT_FQDN"
    return 0
  fi
  if [ -n "${KB_SWITCHOVER_CURRENT_NAME:-}" ] && find_fqdn_by_name "$KB_SWITCHOVER_CURRENT_NAME"; then
    return 0
  fi
  return 1
}

resolve_candidate_fqdn() {
  if [ -n "${KB_SWITCHOVER_CANDIDATE_FQDN:-}" ]; then
    printf '%s\n' "$KB_SWITCHOVER_CANDIDATE_FQDN"
    return 0
  fi
  if [ -n "${KB_SWITCHOVER_CANDIDATE_NAME:-}" ] && find_fqdn_by_name "$KB_SWITCHOVER_CANDIDATE_NAME"; then
    return 0
  fi

  current_fqdn="$(resolve_current_fqdn 2>/dev/null || true)"
  current_name="${KB_SWITCHOVER_CURRENT_NAME:-}"
  old_ifs="$IFS"
  IFS=,
  set -- ${DOLT_POD_FQDN_LIST:-}
  IFS="$old_ifs"

  for fqdn do
    [ -n "$fqdn" ] || continue
    [ -n "$current_fqdn" ] && [ "$fqdn" = "$current_fqdn" ] && continue
    if [ -n "$current_name" ]; then
      case "$fqdn" in
        "$current_name"|"$current_name".*)
          continue
          ;;
      esac
    fi
    printf '%s\n' "$fqdn"
    return 0
  done

  die "No switchover candidate FQDN was injected and DOLT_POD_FQDN_LIST has no non-current pod"
  return 1
}

max_epoch() {
  left="$1"
  right="$2"
  if [ "$left" -ge "$right" ]; then
    printf '%s\n' "$left"
  else
    printf '%s\n' "$right"
  fi
}

next_epoch() {
  current_epoch="$1"
  candidate_epoch="$2"
  max="$(max_epoch "$current_epoch" "$candidate_epoch")"
  printf '%s\n' "$((max + 1))"
}

assume_role() {
  host="$1"
  role="$2"
  epoch="$3"
  log "Assuming Dolt cluster role ${role} on ${host} at epoch ${epoch}"
  sql_query "$host" "CALL dolt_assume_cluster_role('${role}', ${epoch});" >/dev/null
}

role_matches() {
  host="$1"
  expected_role="$2"
  min_epoch="$3"
  role_epoch="$(query_role_epoch "$host")" || return 1
  set -- $role_epoch
  [ "$1" = "$expected_role" ] && [ "$2" -ge "$min_epoch" ]
}

wait_for_role() {
  host="$1"
  expected_role="$2"
  min_epoch="$3"
  deadline="${DOLT_SWITCHOVER_DEADLINE:-$(( $(date +%s) + DOLT_SWITCHOVER_WAIT_SECONDS ))}"

  while [ "$(date +%s)" -le "$deadline" ]; do
    if role_matches "$host" "$expected_role" "$min_epoch"; then
      return 0
    fi
    sleep "$DOLT_SWITCHOVER_POLL_SECONDS"
  done

  role_epoch="$(query_role_epoch "$host" 2>/dev/null || true)"
  die "Timed out waiting for ${host} to become ${expected_role} at epoch >= ${min_epoch}; current=${role_epoch:-unknown}"
  return 1
}

run_switchover() {
  DOLT_SWITCHOVER_DEADLINE="$(( $(date +%s) + DOLT_SWITCHOVER_WAIT_SECONDS ))"
  export DOLT_SWITCHOVER_DEADLINE
  candidate_fqdn="$(resolve_candidate_fqdn)"
  current_role_epoch="$(query_role_epoch "$DOLT_LOCAL_SQL_HOST")" || return 1
  candidate_role_epoch="$(query_role_epoch "$candidate_fqdn")" || return 1
  set -- $current_role_epoch
  current_role="$1"
  current_epoch="$2"
  set -- $candidate_role_epoch
  candidate_role="$1"
  candidate_epoch="$2"

  log "Current pod role=${current_role} epoch=${current_epoch}; candidate ${candidate_fqdn} role=${candidate_role} epoch=${candidate_epoch}; timeout=${DOLT_SWITCHOVER_WAIT_SECONDS}s"

  if [ "$current_role" = "standby" ] && [ "$candidate_role" = "primary" ]; then
    log "Switchover already completed."
    return 0
  fi

  if [ "$candidate_role" != "standby" ]; then
    die "Switchover candidate ${candidate_fqdn} must be standby, got ${candidate_role}"
    return 1
  fi

  epoch="$(next_epoch "$current_epoch" "$candidate_epoch")"

  case "$current_role" in
    primary)
      assume_role "$DOLT_LOCAL_SQL_HOST" "standby" "$epoch"
      wait_for_role "$DOLT_LOCAL_SQL_HOST" "standby" "$epoch"
      ;;
    standby)
      log "Current pod is already standby; retrying candidate promotion only."
      ;;
    *)
      die "Current pod must be primary or already demoted standby, got ${current_role}"
      return 1
      ;;
  esac

  assume_role "$candidate_fqdn" "primary" "$epoch"
  wait_for_role "$candidate_fqdn" "primary" "$epoch"
  wait_for_role "$DOLT_LOCAL_SQL_HOST" "standby" "$epoch"
  log "DoltDB switchover completed: ${candidate_fqdn} is primary at epoch ${epoch}"
}

main() {
  if [ "${KB_SWITCHOVER_ROLE:-}" != "primary" ]; then
    log "Switchover not for primary role (got '${KB_SWITCHOVER_ROLE:-}'); exiting."
    return 0
  fi

  : "${DOLT_ROOT_PASSWORD:?DOLT_ROOT_PASSWORD is required}"

  run_switchover
}

if [ "${DOLTDB_SWITCHOVER_LIBRARY_MODE:-false}" != "true" ]; then
  mkdir -p "$DOLT_SWITCHOVER_LOG_DIR"
  exec 4>&2
  exec >>"$LOG_FILE" 2>&1
  trap 'rc=$?; if [ "$rc" -ne 0 ]; then echo "doltdb switchover failed, last log lines:" >&4; tail -n 80 "$LOG_FILE" >&4 || true; fi; exit "$rc"' EXIT
  main "$@"
fi
