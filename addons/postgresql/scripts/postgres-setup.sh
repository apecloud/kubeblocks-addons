#!/bin/bash

tmp_patroni_yaml="tmp_patroni.yaml"

function wait_pod_restarted() {
  for i in $(seq 1 10); do
    pending_restart=$(curl --connect-timeout 3 -s http://localhost:8008/cluster | jq -r ".members[] | select(.name == \"${CURRENT_POD_NAME}\") | .pending_restart")
    if [[ "${pending_restart}" != "true" ]]; then
      break
    fi
    sleep 3
  done
}

# NOTE: this loop used to compare a 6-parameter whitelist against the primary
# and skip the restart when those values matched — which starved every OTHER
# restart-class parameter (shared_buffers, max_wal_senders, archive_mode, ...):
# secondaries kept the old value and stayed pending_restart forever. Patroni's
# own per-member pending_restart flag (already checked at the top of the loop)
# is the ground truth for "this node needs a restart"; no extra gate is needed.

# decide whether the current pod should restart now: only when it has
# pending_restart, and either no leader is pending or the pending leader
# is the current pod (the leader restarts first, secondaries follow).
function need_restart_for_pending() {
  local pending_restart=$1
  local leader_pending_restart_pod=$2
  [[ "${pending_restart}" == "true" && ( -z "${leader_pending_restart_pod}" || "${leader_pending_restart_pod}" == "${CURRENT_POD_NAME}" ) ]]
}

function restart_for_pending_restart_flag() {
  while true; do
    sleep 5
    pod_info_tmp_path="/tmp/pod_info.tmp"
    curl --connect-timeout 3 -s http://localhost:8008 > ${pod_info_tmp_path}

    if grep -q "pending_restart" ${pod_info_tmp_path}; then
      pod_info=$(<${pod_info_tmp_path})
      pending_restart=$(echo $pod_info | jq -r .pending_restart)
      if [[ "$pending_restart" != "true" ]]; then
        continue
      fi
    else
        continue
    fi

    if grep -q "state" ${pod_info_tmp_path}; then
      pod_info=$(<${pod_info_tmp_path})
      rm -f ${pod_info_tmp_path}
      state=$(echo $pod_info | jq -r .state)
      if [[ "$state" != "running" && "$state" != "streaming" ]]; then
        continue
      fi
    else
        continue
    fi

    result_tmp_path="/tmp/cluster_result.tmp"
    curl --connect-timeout 3 -s http://localhost:8008/cluster > ${result_tmp_path}
    result=$(<${result_tmp_path})
    rm -f ${result_tmp_path}

    leader_pending_restart_pod=$(echo ${result} | jq -r ".members[] | select(.role == \"leader\" and .pending_restart == true) | .name")
    # Serialize member restarts: if any member is already mid-restart, wait
    # for the next loop iteration instead of taking a second replica down in
    # the same window (a simultaneous secondary restart leaves zero live
    # replicas and blocks commits under synchronous mode).
    restarting_member=$(echo ${result} | jq -r '.members[] | select(.state == "restarting") | .name' | head -n 1)
    if [[ -n "${restarting_member}" && "${restarting_member}" != "${CURRENT_POD_NAME}" ]]; then
      continue
    fi
    # Re-check pending_restart to avoid duplicate restarts
    sleep 5
    pending_restart=$(curl --connect-timeout 3 -s http://localhost:8008 | jq -r .pending_restart)
    if need_restart_for_pending "${pending_restart}" "${leader_pending_restart_pod}"; then
      # if leader pod is not pending_restart or current pod is leader pod, restart it
      echo "$(date) ${CURRENT_POD_NAME} is pending restart, restart it"
      curl -m 30 -XPOST http://localhost:8008/restart
      wait_pod_restarted
    fi
  done
}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/kb-scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

init_etcd_dcs_config_if_needed() {
  if ! is_empty "$PATRONI_DCS_ETCD_SERVICE_ENDPOINT"; then
    echo "PATRONI_DCS_ETCD_SERVICE_ENDPOINT is set. Use etcd as DCS backend and unset DCS_ENABLE_KUBERNETES_API"
    export ETCDCTL_API=${PATRONI_DCS_ETCD_VERSION:-'2'}
    export DCS_ENABLE_KUBERNETES_API=""
    # if ETCD exist, unset KUBERNETES_SERVICE_HOST to use ETCD as DCS
    unset KUBERNETES_SERVICE_HOST
    if [ "$ETCDCTL_API" = "3" ]; then
      export ETCD3_HOSTS=$PATRONI_DCS_ETCD_SERVICE_ENDPOINT
    else
      export ETCD_HOSTS=$PATRONI_DCS_ETCD_SERVICE_ENDPOINT
    fi
    SCOPE="${CLUSTER_NAME}-${POSTGRES_COMPONENT_NAME}-patroni${CLUSTER_UID: -8}"
  else
    SCOPE=${POSTGRES_COMPONENT_NAME}
  fi
  export SCOPE
}

regenerate_spilo_configuration_and_start_postgres() {
  restart_for_pending_restart_flag >> /home/postgres/.kb_set_up.log 2>&1 &
  echo "$(date) restart_for_pending_restart_flag PID=$!" >> /home/postgres/.kb_set_up.log
  if [ -f "${RESTORE_DATA_DIR}"/kb_restore.signal ]; then
      chown -R postgres "${RESTORE_DATA_DIR}"
  fi
  # Ensure postgres user owns the entire config directory (Patroni needs to write pg_hba.conf, etc.)
  chown -R postgres:postgres /home/postgres/pgdata/conf
  python3 /kb-scripts/generate_patroni_yaml.py $tmp_patroni_yaml
  # SPILO_CONFIGURATION is defined by spilo image
  SPILO_CONFIGURATION=$(cat $tmp_patroni_yaml)
  export SPILO_CONFIGURATION
  exec /launch.sh init
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
init_etcd_dcs_config_if_needed
regenerate_spilo_configuration_and_start_postgres
