#!/bin/sh
# Switchover: ask syncer to coordinate ownership via DCS, then wait until
# database truth reflects the new primary and the old primary has followed it.
#
# Env vars set by KubeBlocks:
#   KB_SWITCHOVER_ROLE           - "primary" (only act when we are the primary)
#   KB_SWITCHOVER_CURRENT_NAME   - current primary pod name
#   KB_SWITCHOVER_CANDIDATE_NAME - target replica pod name (may be empty)

DATA_DIR="${MARIADB_DATADIR:-/var/lib/mysql}"
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-cluster.local}"
SYNCERCTL_BIN="${SYNCERCTL_BIN:-/tools/syncerctl}"
SYNCERCTL_HOST="${SYNCERCTL_HOST:-127.0.0.1}"
SYNCERCTL_PORT="${SYNCERCTL_PORT:-3601}"
SWITCHOVER_WAIT_SECONDS="${SWITCHOVER_WAIT_SECONDS:-50}"
SWITCHOVER_POLL_SECONDS="${SWITCHOVER_POLL_SECONDS:-2}"
SWITCHOVER_STABILIZATION_SECONDS="${SWITCHOVER_STABILIZATION_SECONDS:-10}"
MARIADB_CLIENT_BIN="${MARIADB_CLIENT_BIN:-mariadb}"

resolve_current_name() {
  if [ -n "${KB_SWITCHOVER_CURRENT_NAME}" ]; then
    echo "${KB_SWITCHOVER_CURRENT_NAME}"
    return 0
  fi
  echo "${POD_NAME:-}"
}

resolve_candidate_name() {
  local current_name
  current_name=$(resolve_current_name)
  if [ -n "${KB_SWITCHOVER_CANDIDATE_NAME}" ]; then
    echo "${KB_SWITCHOVER_CANDIDATE_NAME}"
    return 0
  fi

  local current_idx="${current_name##*-}"
  if [ "${current_idx}" = "0" ]; then
    echo "${CLUSTER_NAME}-${COMPONENT_NAME}-1"
  else
    echo "${CLUSTER_NAME}-${COMPONENT_NAME}-0"
  fi
}

resolve_candidate_fqdn() {
  local candidate
  candidate=$(resolve_candidate_name)
  echo "${candidate}.${CLUSTER_NAME}-${COMPONENT_NAME}-headless.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
}

resolve_primary_service_fqdn() {
  echo "${CLUSTER_NAME}-${COMPONENT_NAME}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
}

query_value() {
  local host="$1"
  local sql="$2"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    -P3306 -h"${host}" -N -s -e "${sql}" 2>/dev/null || echo ""
}

query_slave_status() {
  local host="$1"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    -P3306 -h"${host}" -e "SHOW SLAVE STATUS\\G" 2>/dev/null || true
}

query_server_id() {
  local host="$1"
  query_value "${host}" "SELECT @@server_id;"
}

has_mariadb_client() {
  command -v "${MARIADB_CLIENT_BIN}" >/dev/null 2>&1
}

query_syncer_role() {
  local host="$1"
  "${SYNCERCTL_BIN}" --host "${host}" --port "${SYNCERCTL_PORT}" getrole 2>/dev/null | tr -d '\r\n'
}

candidate_is_primary() {
  local candidate_fqdn="$1"
  local read_only
  local slave_status

  if ! has_mariadb_client; then
    [ "$(query_syncer_role "${candidate_fqdn}")" = "primary" ]
    return $?
  fi

  read_only=$(query_value "${candidate_fqdn}" "SELECT @@global.read_only;")
  slave_status=$(query_slave_status "${candidate_fqdn}")

  [ "${read_only}" = "0" ] && [ -z "${slave_status}" ]
}

current_follows_candidate() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local read_only
  local slave_status

  if ! has_mariadb_client; then
    [ "$(query_syncer_role "127.0.0.1")" = "secondary" ]
    return $?
  fi

  read_only=$(query_value "127.0.0.1" "SELECT @@global.read_only;")
  [ "${read_only}" = "1" ] || return 1

  slave_status=$(query_slave_status "127.0.0.1")
  printf "%s" "${slave_status}" | grep -q "Slave_IO_Running: Yes" || return 1
  printf "%s" "${slave_status}" | grep -q "Slave_SQL_Running: Yes" || return 1
  printf "%s" "${slave_status}" | grep -q "Last_IO_Errno: 0" || return 1
  printf "%s" "${slave_status}" | grep -q "Last_SQL_Errno: 0" || return 1
  printf "%s" "${slave_status}" | grep -F "Master_Host: ${candidate_fqdn}" >/dev/null 2>&1 ||
  printf "%s" "${slave_status}" | grep -F "Master_Host: ${candidate_name}" >/dev/null 2>&1
}

primary_service_routes_candidate() {
  local candidate_fqdn="$1"
  local candidate_server_id
  local service_server_id

  candidate_server_id=$(query_server_id "${candidate_fqdn}")
  [ -n "${candidate_server_id}" ] || return 1

  service_server_id=$(query_server_id "$(resolve_primary_service_fqdn)")
  [ "${service_server_id}" = "${candidate_server_id}" ]
}

log_primary_service_route_diagnostic() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local primary_service_fqdn
  local candidate_server_id
  local service_server_id
  local route_status="pending"
  local observation

  primary_service_fqdn=$(resolve_primary_service_fqdn)
  candidate_server_id=$(query_server_id "${candidate_fqdn}")
  service_server_id=$(query_server_id "${primary_service_fqdn}")
  if [ -n "${candidate_server_id}" ] && [ "${service_server_id}" = "${candidate_server_id}" ]; then
    route_status="matched"
  fi
  observation="candidate=${candidate_name} candidate_fqdn=${candidate_fqdn} primary_service=${primary_service_fqdn} expected_server_id=${candidate_server_id:-<empty-or-error>} service_server_id=${service_server_id:-<empty-or-error>} route_status=${route_status}"
  echo "Switchover service-route diagnostic: ${observation}"
  return 0
}

wait_post_switchover_stabilization() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local waited=0

  while [ "${waited}" -lt "${SWITCHOVER_STABILIZATION_SECONDS}" ]; do
    candidate_is_primary "${candidate_fqdn}" || return 1
    current_follows_candidate "${candidate_name}" "${candidate_fqdn}" || return 1
    sleep "${SWITCHOVER_POLL_SECONDS}"
    waited=$((waited + SWITCHOVER_POLL_SECONDS))
  done

  echo "Switchover stabilization window passed for candidate ${candidate_name} using pod/headless DB truth"
  return 0
}

wait_switchover_done() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local waited=0

  while [ "${waited}" -lt "${SWITCHOVER_WAIT_SECONDS}" ]; do
    if candidate_is_primary "${candidate_fqdn}" && current_follows_candidate "${candidate_name}" "${candidate_fqdn}"; then
      if ! wait_post_switchover_stabilization "${candidate_name}" "${candidate_fqdn}"; then
        echo "Switchover timed out: post-switchover stabilization did not hold for candidate ${candidate_name}" >&2
        return 1
      fi
      log_primary_service_route_diagnostic "${candidate_name}" "${candidate_fqdn}"
      echo "Switchover done: ${candidate_name} is primary and $(resolve_current_name) follows it"
      return 0
    fi
    sleep "${SWITCHOVER_POLL_SECONDS}"
    waited=$((waited + SWITCHOVER_POLL_SECONDS))
  done

  echo "Switchover timed out: syncer DCS switchover did not converge for candidate ${candidate_name}" >&2
  return 1
}

run_switchover() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local current_name
  current_name=$(resolve_current_name)

  if [ -z "${current_name}" ]; then
    echo "Switchover failed: current primary name is empty" >&2
    return 1
  fi
  if [ -z "${candidate_name}" ]; then
    echo "Switchover failed: candidate name is empty" >&2
    return 1
  fi

  echo "Switchover: creating syncer DCS switchover primary=${current_name} candidate=${candidate_name}"
  if ! "${SYNCERCTL_BIN}" --host "${SYNCERCTL_HOST}" --port "${SYNCERCTL_PORT}" \
    switchover --primary "${current_name}" --candidate "${candidate_name}"; then
    echo "Switchover failed: syncerctl could not create DCS switchover" >&2
    return 1
  fi

  wait_switchover_done "${candidate_name}" "${candidate_fqdn}"
}

main() {
  if [ "${KB_SWITCHOVER_ROLE}" != "primary" ]; then
    echo "Not the primary, nothing to do."
    return 0
  fi

  local candidate_name
  local candidate_fqdn
  candidate_name=$(resolve_candidate_name)
  candidate_fqdn=$(resolve_candidate_fqdn)
  run_switchover "${candidate_name}" "${candidate_fqdn}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

set -e
main
