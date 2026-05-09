#!/bin/sh
# Called by KubeBlocks when a replica node joins the replication cluster.
# Sets up GTID-based async replication from the primary service endpoint.

CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-cluster.local}"
PRIMARY_HOST="${PRIMARY_HOST:-${CLUSTER_NAME}-${COMPONENT_NAME}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}}"
POD_NAME="${POD_NAME:-${KB_JOIN_MEMBER_POD_NAME:-}}"
POD_INDEX="${POD_NAME##*-}"
HEADLESS_HOST="${CLUSTER_NAME}-${COMPONENT_NAME}-headless.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
BOOTSTRAP_PRIMARY_HOST="${CLUSTER_NAME}-${COMPONENT_NAME}-0.${HEADLESS_HOST}"
ACTIVE_PRIMARY_HOST="${PRIMARY_HOST}"
DATA_DIR="${MARIADB_DATADIR:-/var/lib/mysql}"
MYSQL_CLIENT_DIR="${MYSQL_CLIENT_DIR:-/tools/mysql-client}"
PRIMARY_SAMPLE_RETRIES="${PRIMARY_SAMPLE_RETRIES:-3}"
PRIMARY_SAMPLE_SLEEP_SECONDS="${PRIMARY_SAMPLE_SLEEP_SECONDS:-1}"
PRIMARY_SAMPLE_HOST=""
PRIMARY_SAMPLE_SERVER_ID=""
PRIMARY_SAMPLE_RESOLVED_ENDPOINT=""
PRIMARY_SAMPLE_READ_ONLY=""
PRIMARY_SAMPLE_GTID=""
PRIMARY_SAMPLE_STABLE="unknown"
PRIMARY_SAMPLE_LOG=""

resolve_mariadb_cli() {
  if command -v mariadb >/dev/null 2>&1; then
    command -v mariadb
    return 0
  fi
  if [ -x "${MYSQL_CLIENT_DIR}/bin/mariadb" ]; then
    echo "${MYSQL_CLIENT_DIR}/bin/mariadb"
    return 0
  fi
  return 1
}

MARIADB_CLI="${MARIADB_CLI:-$(resolve_mariadb_cli || true)}"

local_sql()   { "${MARIADB_CLI}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" -P3306 -h127.0.0.1 --connect-timeout=5 -N -s "$@"; }
host_sql()    { local host="$1"; shift; "${MARIADB_CLI}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" -P3306 "-h${host}" --connect-timeout=5 -N -s "$@"; }
primary_sql() { host_sql "${ACTIVE_PRIMARY_HOST}" "$@"; }

append_primary_sample_log() {
  if [ -n "${PRIMARY_SAMPLE_LOG}" ]; then
    PRIMARY_SAMPLE_LOG="${PRIMARY_SAMPLE_LOG}
$1"
  else
    PRIMARY_SAMPLE_LOG="$1"
  fi
}

query_primary_sample_once() {
  local host="$1"
  host_sql "${host}" -e "SELECT @@server_id, @@hostname, @@global.read_only, @@global.gtid_binlog_state;" 2>/dev/null
}

sample_primary_for_divergence() {
  local host="${ACTIVE_PRIMARY_HOST:-${PRIMARY_HOST}}" attempts="${PRIMARY_SAMPLE_RETRIES:-3}" sleep_seconds="${PRIMARY_SAMPLE_SLEEP_SECONDS:-1}"
  local i sample sid endpoint read_only gtid identity prev_identity="" prev_gtid=""

  PRIMARY_SAMPLE_HOST="${host}"
  PRIMARY_SAMPLE_SERVER_ID=""
  PRIMARY_SAMPLE_RESOLVED_ENDPOINT=""
  PRIMARY_SAMPLE_READ_ONLY=""
  PRIMARY_SAMPLE_GTID=""
  PRIMARY_SAMPLE_STABLE="false"
  PRIMARY_SAMPLE_LOG=""

  i=1
  while [ "${i}" -le "${attempts}" ] 2>/dev/null; do
    sample=$(query_primary_sample_once "${host}" || true)
    sid=""
    endpoint=""
    read_only=""
    gtid=""
    if [ -n "${sample}" ]; then
      old_ifs="${IFS}"
      IFS="$(printf '\t')"
      set -- ${sample}
      IFS="${old_ifs}"
      sid="$1"
      endpoint="$2"
      read_only="$3"
      gtid="$4"
    fi
    append_primary_sample_log "attempt=${i} host=${host} server_id=${sid:-<empty>} resolved_endpoint=${endpoint:-<empty>} read_only=${read_only:-<empty>} gtid=${gtid:-<empty>}"
    if [ -n "${sid}" ] && [ -n "${gtid}" ]; then
      identity="${sid}/${endpoint:-unknown}"
      if [ -n "${prev_identity}" ]; then
        if [ "${identity}" != "${prev_identity}" ] || ! gtid_state_is_covered_by "${prev_gtid}" "${gtid}"; then
          PRIMARY_SAMPLE_STABLE="false"
          return 1
        fi
      fi
      prev_identity="${identity}"
      prev_gtid="${gtid}"
      PRIMARY_SAMPLE_SERVER_ID="${sid}"
      PRIMARY_SAMPLE_RESOLVED_ENDPOINT="${endpoint:-unknown}"
      PRIMARY_SAMPLE_READ_ONLY="${read_only:-unknown}"
      PRIMARY_SAMPLE_GTID="${gtid}"
    fi
    i=$((i + 1))
    if [ "${i}" -le "${attempts}" ] 2>/dev/null; then
      sleep "${sleep_seconds}"
    fi
  done

  if [ -n "${PRIMARY_SAMPLE_GTID}" ]; then
    PRIMARY_SAMPLE_STABLE="true"
    return 0
  fi
  PRIMARY_SAMPLE_STABLE="false"
  return 1
}

mark_replication_ready() {
  if [ ! -f "${DATA_DIR}/.replication-ready" ]; then
    touch "${DATA_DIR}/.replication-ready"
  fi
  rm -f "${DATA_DIR}/.replication-pending" "${DATA_DIR}/.replication-divergence-pending"
}

mark_replication_pending() {
  rm -f "${DATA_DIR}/.replication-ready" "${DATA_DIR}/.replication-divergence-pending"
  touch "${DATA_DIR}/.replication-pending"
}

mark_replication_divergence_pending() {
  mark_replication_pending
  touch "${DATA_DIR}/.replication-divergence-pending"
}

replication_marker_state() {
  local state="" marker
  for marker in .replication-ready .replication-pending .replication-divergence-pending; do
    if [ -f "${DATA_DIR}/${marker}" ]; then
      state="${state}${marker} "
    fi
  done
  if [ -n "${state}" ]; then
    printf "%s" "${state% }"
  else
    printf "%s" "<none>"
  fi
}

persist_gtid_divergence_evidence() {
  local branch="$1" local_state="$2" primary_state="$3" slave_status="$4"
  local ts marker_state evidence_file marker_file
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  marker_state=$(replication_marker_state)
  evidence_file="${DATA_DIR}/log/replication-divergence.log"
  marker_file="${DATA_DIR}/.replication-divergence-pending"
  mkdir -p "${DATA_DIR}/log" 2>/dev/null || true

  {
    printf 'timestamp=%s\n' "${ts}"
    printf 'branch=%s\n' "${branch}"
    printf 'decision=divergence-pending\n'
    printf 'pod_name=%s\n' "${POD_NAME:-unknown}"
    printf 'cluster_name=%s\n' "${CLUSTER_NAME:-unknown}"
    printf 'component_name=%s\n' "${COMPONENT_NAME:-unknown}"
    printf 'active_primary_host=%s\n' "${ACTIVE_PRIMARY_HOST:-unknown}"
    printf 'primary_host=%s\n' "${PRIMARY_HOST:-unknown}"
    printf 'primary_sample_host=%s\n' "${PRIMARY_SAMPLE_HOST:-unknown}"
    printf 'primary_sample_stable=%s\n' "${PRIMARY_SAMPLE_STABLE:-unknown}"
    printf 'primary_resolved_endpoint=%s\n' "${PRIMARY_SAMPLE_RESOLVED_ENDPOINT:-unknown}"
    printf 'primary_server_id=%s\n' "${PRIMARY_SAMPLE_SERVER_ID:-unknown}"
    printf 'primary_read_only=%s\n' "${PRIMARY_SAMPLE_READ_ONLY:-unknown}"
    printf 'local_gtid_binlog_state=%s\n' "${local_state:-<empty>}"
    printf 'primary_gtid_binlog_state=%s\n' "${primary_state:-<empty>}"
    printf 'marker_state=%s\n' "${marker_state}"
    printf 'primary_sample_attempts_begin\n'
    if [ -n "${PRIMARY_SAMPLE_LOG}" ]; then
      printf '%s\n' "${PRIMARY_SAMPLE_LOG}"
    else
      printf '<empty>\n'
    fi
    printf 'primary_sample_attempts_end\n'
    printf 'slave_status_begin\n'
    if [ -n "${slave_status}" ]; then
      printf '%s\n' "${slave_status}"
    else
      printf '<empty>\n'
    fi
    printf 'slave_status_end\n'
    printf '\n'
  } >> "${evidence_file}" 2>/dev/null || true

  {
    printf 'timestamp=%s\n' "${ts}"
    printf 'branch=%s\n' "${branch}"
    printf 'decision=divergence-pending\n'
    printf 'pod_name=%s\n' "${POD_NAME:-unknown}"
    printf 'active_primary_host=%s\n' "${ACTIVE_PRIMARY_HOST:-unknown}"
    printf 'primary_sample_host=%s\n' "${PRIMARY_SAMPLE_HOST:-unknown}"
    printf 'primary_sample_stable=%s\n' "${PRIMARY_SAMPLE_STABLE:-unknown}"
    printf 'primary_resolved_endpoint=%s\n' "${PRIMARY_SAMPLE_RESOLVED_ENDPOINT:-unknown}"
    printf 'primary_server_id=%s\n' "${PRIMARY_SAMPLE_SERVER_ID:-unknown}"
    printf 'local_gtid_binlog_state=%s\n' "${local_state:-<empty>}"
    printf 'primary_gtid_binlog_state=%s\n' "${primary_state:-<empty>}"
    printf 'marker_state=%s\n' "${marker_state}"
  } > "${marker_file}" 2>/dev/null || true
}

persist_gtid_sampling_evidence() {
  local branch="$1" local_state="$2" slave_status="$3"
  local ts marker_state evidence_file
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  marker_state=$(replication_marker_state)
  evidence_file="${DATA_DIR}/log/replication-divergence.log"
  mkdir -p "${DATA_DIR}/log" 2>/dev/null || true

  {
    printf 'timestamp=%s\n' "${ts}"
    printf 'branch=%s\n' "${branch}"
    printf 'decision=sampling-instability\n'
    printf 'pod_name=%s\n' "${POD_NAME:-unknown}"
    printf 'cluster_name=%s\n' "${CLUSTER_NAME:-unknown}"
    printf 'component_name=%s\n' "${COMPONENT_NAME:-unknown}"
    printf 'active_primary_host=%s\n' "${ACTIVE_PRIMARY_HOST:-unknown}"
    printf 'primary_host=%s\n' "${PRIMARY_HOST:-unknown}"
    printf 'primary_sample_host=%s\n' "${PRIMARY_SAMPLE_HOST:-unknown}"
    printf 'primary_sample_stable=%s\n' "${PRIMARY_SAMPLE_STABLE:-unknown}"
    printf 'primary_resolved_endpoint=%s\n' "${PRIMARY_SAMPLE_RESOLVED_ENDPOINT:-unknown}"
    printf 'primary_server_id=%s\n' "${PRIMARY_SAMPLE_SERVER_ID:-unknown}"
    printf 'primary_read_only=%s\n' "${PRIMARY_SAMPLE_READ_ONLY:-unknown}"
    printf 'local_gtid_binlog_state=%s\n' "${local_state:-<empty>}"
    printf 'primary_gtid_binlog_state=%s\n' "${PRIMARY_SAMPLE_GTID:-<empty>}"
    printf 'marker_state=%s\n' "${marker_state}"
    printf 'primary_sample_attempts_begin\n'
    if [ -n "${PRIMARY_SAMPLE_LOG}" ]; then
      printf '%s\n' "${PRIMARY_SAMPLE_LOG}"
    else
      printf '<empty>\n'
    fi
    printf 'primary_sample_attempts_end\n'
    printf 'slave_status_begin\n'
    if [ -n "${slave_status}" ]; then
      printf '%s\n' "${slave_status}"
    else
      printf '<empty>\n'
    fi
    printf 'slave_status_end\n'
    printf '\n'
  } >> "${evidence_file}" 2>/dev/null || true
}

has_existing_datadir() {
  [ -d "${DATA_DIR}/mysql" ] || ls "${DATA_DIR}"/binlog/*.bin* >/dev/null 2>&1
}

is_gtid_strict_mode_enabled() {
  local strict_mode
  strict_mode=$(local_sql -e "SELECT @@global.gtid_strict_mode;" 2>/dev/null | tr '[:lower:]' '[:upper:]')
  [ "${strict_mode}" = "ON" ] || [ "${strict_mode}" = "1" ]
}

gtid_state_is_covered_by() {
  local local_state="$1" primary_state="$2"
  [ -z "${local_state}" ] && return 0
  awk -v local_state="${local_state}" -v primary_state="${primary_state}" '
    function load_state(state, arr,    count, i, token, parts, key) {
      count = split(state, tokens, ",")
      for (i = 1; i <= count; i++) {
        token = tokens[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", token)
        if (token == "") {
          continue
        }
        if (split(token, parts, "-") != 3) {
          return 0
        }
        key = parts[1] "-" parts[2]
        arr[key] = parts[3] + 0
      }
      return 1
    }
    BEGIN {
      if (!load_state(primary_state, primary)) {
        exit 1
      }
      count = split(local_state, locals, ",")
      for (i = 1; i <= count; i++) {
        token = locals[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", token)
        if (token == "") {
          continue
        }
        if (split(token, parts, "-") != 3) {
          exit 1
        }
        key = parts[1] "-" parts[2]
        seq = parts[3] + 0
        if (!(key in primary) || primary[key] < seq) {
          exit 1
        }
      }
      exit 0
    }
  '
}

fail_closed_for_gtid_divergence() {
  local primary_state local_state slave_status
  has_existing_datadir || return 1
  is_gtid_strict_mode_enabled || return 1
  local_state=$(local_sql -e "SELECT @@global.gtid_binlog_state;" 2>/dev/null)
  [ -n "${local_state}" ] || return 1
  slave_status=$(local_sql -e "SHOW SLAVE STATUS;" 2>/dev/null || true)
  if ! sample_primary_for_divergence; then
    persist_gtid_sampling_evidence "sample_primary_for_gtid_divergence" "${local_state}" "${slave_status}"
    return 1
  fi
  primary_state="${PRIMARY_SAMPLE_GTID}"
  [ -n "${primary_state}" ] || return 1
  if gtid_state_is_covered_by "${local_state}" "${primary_state}"; then
    return 1
  fi
  local_sql -e "STOP SLAVE; SET GLOBAL read_only = 1;" 2>/dev/null || true
  mark_replication_divergence_pending
  persist_gtid_divergence_evidence "fail_closed_for_gtid_divergence" "${local_state}" "${primary_state}" "${slave_status}"
  echo "GTID divergence detected for existing datadir rejoin: local binlog state ${local_state}, primary binlog state ${primary_state}. Keeping replication pending for rebuild/resync."
  return 0
}

query_slave_status_verbose() {
  local mariadb_cli
  mariadb_cli=$(resolve_mariadb_cli) || return 1
  "${mariadb_cli}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    -P3306 -h127.0.0.1 -e "SHOW SLAVE STATUS\\G" 2>/dev/null || true
}

slave_status_is_ready_for_rejoin() {
  local slave_status="$1"
  [ -n "${slave_status}" ] || return 1
  printf "%s" "${slave_status}" | grep -q "Slave_IO_Running: Yes" || return 1
  printf "%s" "${slave_status}" | grep -q "Slave_SQL_Running: Yes" || return 1
  printf "%s" "${slave_status}" | grep -q "Last_IO_Errno: 0" || return 1
  printf "%s" "${slave_status}" | grep -q "Last_SQL_Errno: 0" || return 1
}

slave_status_has_gtid_out_of_order() {
  local slave_status="$1"
  [ -n "${slave_status}" ] || return 1
  printf "%s" "${slave_status}" | grep -q "Last_SQL_Errno: 1950" || return 1
  printf "%s" "${slave_status}" | grep -qi "out-of-order" || return 1
}

# Wait for the primary service endpoint to accept connections.
wait_for_primary() {
  local max_wait="${1:-120}" elapsed=0
  echo "Waiting for primary (${PRIMARY_HOST}) to be reachable..."
  while true; do
    if host_sql "${PRIMARY_HOST}" -e "SELECT 1;" >/dev/null 2>&1; then
      ACTIVE_PRIMARY_HOST="${PRIMARY_HOST}"
      return 0
    fi
    if [ -n "${POD_INDEX}" ] && [ "${POD_INDEX}" -gt 0 ] 2>/dev/null; then
      local direct_read_only
      direct_read_only=$(host_sql "${BOOTSTRAP_PRIMARY_HOST}" -e "SELECT @@global.read_only;" 2>/dev/null || echo "")
      if [ "${direct_read_only}" = "0" ]; then
        ACTIVE_PRIMARY_HOST="${BOOTSTRAP_PRIMARY_HOST}"
        echo "Using bootstrap primary ${ACTIVE_PRIMARY_HOST} while primary service has no endpoint."
        return 0
      fi
    fi
    if [ "$elapsed" -ge "$max_wait" ]; then
      echo "Timeout waiting for primary. Exiting."
      return 1
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
}

# Return 0 if the primary service currently routes to this pod (we are the primary).
is_self_primary() {
  local local_sid primary_sid
  local_sid=$(local_sql -e "SELECT @@server_id;" 2>/dev/null)
  primary_sid=$(primary_sql -e "SELECT @@server_id;" 2>/dev/null)
  [ -n "$primary_sid" ] && [ "$primary_sid" = "$local_sid" ]
}

# Return 0 if slave is configured AND IO thread is actively running.
is_slave_running() {
  local slave_status slave_running
  slave_status=$(local_sql -e "SHOW SLAVE STATUS;" 2>/dev/null)
  [ -z "$slave_status" ] && return 1
  slave_running=$(local_sql -e "SHOW STATUS LIKE 'Slave_running';" 2>/dev/null | awk '{print $2}')
  [ "$slave_running" = "ON" ]
}

# Configure and start GTID-based replication from the primary.
setup_replication() {
  # For fresh pods (empty gtid_slave_pos), replicate from earliest available binlog
  # so they receive full schema+data. For rejoining pods with existing datadir,
  # keep the local gtid_slave_pos so missing transactions are replayed.
  local master_gtid local_gtid
  master_gtid=$(primary_sql -e "SELECT @@global.gtid_binlog_pos;" 2>/dev/null)
  local_gtid=$(local_sql -e "SELECT @@global.gtid_slave_pos;" 2>/dev/null)
  echo "Primary GTID: ${master_gtid}, local GTID: ${local_gtid:-<empty>}"

  # Fresh pod: gtid_slave_pos stays empty → MariaDB replicates from earliest available binlog.
  # Rejoining pod: preserve local gtid_slave_pos and catch up from the local replay point.

  if fail_closed_for_gtid_divergence; then
    return 1
  fi

  if ! local_sql -e "
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='${PRIMARY_HOST}',
  MASTER_USER='${MARIADB_ROOT_USER}',
  MASTER_PASSWORD='${MARIADB_ROOT_PASSWORD}',
  MASTER_USE_GTID=slave_pos,
  MASTER_CONNECT_RETRY=10;
START SLAVE;
"; then
    echo "CHANGE MASTER TO failed. Keeping roleProbe pending."
    return 1
  fi
  if [ -z "$(local_sql -e "SHOW SLAVE STATUS;" 2>/dev/null)" ]; then
    echo "CHANGE MASTER TO did not store slave config. Keeping roleProbe pending."
    return 1
  fi

  # Enforce read_only on replica. MariaDB has no super_read_only; read_only=1 blocks
  # non-SUPER users. Root (SUPER) can still write, but application users cannot.
  local_sql -e "SET GLOBAL read_only = 1;" 2>/dev/null || true
  local slave_status_verbose
  slave_status_verbose=$(query_slave_status_verbose)
  if slave_status_is_ready_for_rejoin "${slave_status_verbose}"; then
    # Clear the initialization flag so roleProbe can correctly report "secondary".
    mark_replication_ready
    echo "Replication started via ${ACTIVE_PRIMARY_HOST}."
    return 0
  fi
  if slave_status_has_gtid_out_of_order "${slave_status_verbose}"; then
    if fail_closed_for_gtid_divergence; then
      return 1
    fi
    mark_replication_pending
    echo "WARNING: replication rejoin hit GTID out-of-order (1950) before primary truth stabilized; keeping roleProbe pending for retry"
    return 1
  fi
  mark_replication_pending
  echo "WARNING: replication rejoin not yet healthy; keeping roleProbe pending until Slave_IO/Slave_SQL are Yes and Last_IO/Last_SQL_Errno are 0"
}

main() {
  if [ -z "${MARIADB_CLI}" ]; then
    echo "MariaDB client is unavailable in current memberJoin runtime."
    return 1
  fi

  # Skip if replication is already configured AND running.
  # This fast-path must run before waiting on PRIMARY_HOST: after scale-out,
  # startup may already have configured replication successfully while the
  # memberJoin action is retried later. In that case, waiting on the primary
  # service again only keeps the control-plane stuck on MemberJoined=false.
  if is_slave_running; then
    echo "Replication already configured and running. Nothing to do."
    mark_replication_ready
    return 0
  fi

  wait_for_primary 120 || return 1

  # Guard: if the primary service routes to this pod, this pod IS the primary.
  # Do not configure replication — the startup command already handled it.
  if is_self_primary; then
    echo "Primary service routes to this pod. Already primary. Skipping memberJoin."
    local_sql -e "SET GLOBAL read_only = 0;" 2>/dev/null || true
    mark_replication_ready
    return 0
  fi

  local slave_status
  slave_status=$(local_sql -e "SHOW SLAVE STATUS;" 2>/dev/null)
  if [ -n "$slave_status" ]; then
    echo "Slave configured but stopped; reconfiguring..."
  fi

  setup_replication
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

set -e
main
