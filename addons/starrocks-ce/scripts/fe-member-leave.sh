#!/usr/bin/env bash
set -o errexit
set -o pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

query_frontends() {
  mysql -N -B -h "${FE_DISCOVERY_SERVICE_NAME}" -P 9030 \
    -u"${STARROCKS_USER}" -p"${STARROCKS_PASSWORD}" \
    -e "SHOW FRONTENDS"
}

leave_host=""
leave_port=""
leader_host=""
helper_endpoints=""
candidate_names=""

output=$(query_frontends)
while IFS= read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  ip=$(echo "$line" | awk '{print $2}')
  edit_log_port=$(echo "$line" | awk '{print $3}')
  role=$(echo "$line" | awk '{print $7}')

  if [[ "${ip}" == "${KB_LEAVE_MEMBER_POD_NAME}"* ]]; then
    leave_host=${ip}
    leave_port=${edit_log_port}
  else
    if [ -n "${helper_endpoints}" ]; then
      helper_endpoints="${helper_endpoints},${ip}:${edit_log_port}"
      candidate_names="${candidate_names},${name}"
    else
      helper_endpoints="${ip}:${edit_log_port}"
      candidate_names="${name}"
    fi
  fi

  if [ "${role}" == "LEADER" ]; then
    leader_host=${ip}
  fi
done <<< "$output"

log "leaving member: ${leave_host}:${leave_port}"
log "current leader: ${leader_host}"
log "helper endpoints: ${helper_endpoints}"
log "transfer candidates: ${candidate_names}"

if [ -z "${leave_host}" ] || [ -z "${leave_port}" ]; then
  log "leaving member ${KB_LEAVE_MEMBER_POD_NAME} not found in SHOW FRONTENDS — already removed"
  exit 0
fi

LEADER_TRANSFER_TIMEOUT_SECS=120

if [[ "${leader_host}" == "${KB_LEAVE_MEMBER_POD_NAME}"* ]]; then
  log "leaving member is the current leader — transferring leadership via BDBJE"
  java -jar /opt/starrocks/fe/lib/starrocks-bdb-je*.jar \
    DbGroupAdmin \
    -helperHosts "${helper_endpoints}" \
    -groupName PALO_JOURNAL_GROUP \
    -transferMaster \
    -force "${candidate_names}" 5000

  log "waiting for leadership transfer (timeout ${LEADER_TRANSFER_TIMEOUT_SECS}s)"
  elapsed=0
  while true; do
    new_leader=$(query_frontends | grep 'LEADER' | awk '{print $2}')
    if [[ -n "${new_leader}" && "${new_leader}" != "${KB_LEAVE_MEMBER_POD_NAME}"* ]]; then
      leader_host=${new_leader}
      log "leadership transferred to ${leader_host}"
      break
    fi
    if [ ${elapsed} -ge ${LEADER_TRANSFER_TIMEOUT_SECS} ]; then
      log "ERROR: leader transfer did not complete within ${LEADER_TRANSFER_TIMEOUT_SECS}s"
      log "SHOW FRONTENDS at timeout:"
      query_frontends || true
      exit 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    log "leader still on leaving member, elapsed ${elapsed}s..."
  done
fi

if [ -z "${leader_host}" ]; then
  log "ERROR: no leader found after transfer — cannot drop follower safely"
  query_frontends || true
  exit 1
fi

log "dropping follower ${leave_host}:${leave_port} from FE cluster via leader ${leader_host}"
mysql -h "${leader_host}" -P 9030 \
  -u"${STARROCKS_USER}" -p"${STARROCKS_PASSWORD}" \
  -e "ALTER SYSTEM DROP FOLLOWER '${leave_host}:${leave_port}';"

log "member leave completed for ${KB_LEAVE_MEMBER_POD_NAME}"
