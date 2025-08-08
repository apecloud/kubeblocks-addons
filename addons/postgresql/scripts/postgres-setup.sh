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

function pending_restart_parameters_values() {
  sql="select setting from pg_settings where name in ('max_connections','max_locks_per_transaction','max_worker_processes','max_prepared_transactions','wal_level','track_commit_timestamp')"
  result=$(psql "host=$1 dbname=postgres user=${POSTGRES_USER}  connect_timeout=5" -t -c "${sql}" 2>/dev/null)
  echo $result
}

function restart_for_pending_restart_flag() {
  while true; do
    sleep 5
    pod_info=$(curl --connect-timeout 3 -s http://localhost:8008)
    pending_restart=$(echo $pod_info | jq -r .pending_restart)
    if [[ "$pending_restart" != "true" ]]; then
       continue
    fi
    state=$(echo $pod_info | jq -r .state)
    if [[ "$state" != "running" && "$state" != "streaming" ]]; then
       continue
    fi
    result=$(curl --connect-timeout 3 -s http://localhost:8008/cluster)
    leader_pending_restart_pod=$(echo ${result} | jq -r ".members[] | select(.role == \"leader\" and .pending_restart == true) | .name")
    if [[ -z "$leader_pending_restart_pod"  ]]; then
      # check if the pending_restart parameters are inconsistent
      primary_pod_ip=$(echo $result | jq -r ".members[] | select(.role == \"leader\") | .host")
      primary_parameter_values=$(pending_restart_parameters_values ${primary_pod_ip})
      curr_parameter_values=$(pending_restart_parameters_values localhost)
      if [[ -z "${primary_parameter_values}" || "${curr_parameter_values}" == "${primary_parameter_values}" ]]; then
         continue
      fi
      echo "$(date) primary parameters values: ${primary_parameter_values}, current parameters values: ${curr_parameter_values}"
    fi
    # Re-check pending_restart to avoid duplicate restarts
    sleep 5
    pending_restart=$(curl --connect-timeout 3 -s http://localhost:8008 | jq -r .pending_restart)
    if [[ "${pending_restart}" == "true" && (-z $leader_pending_restart_pod || "${leader_pod}" == "${CURRENT_POD_NAME}") ]]; then
      # if leader pod is not pending_restart or current pod is leader pod, restart it
      echo "$(date) ${CURRENT_POD_NAME} is pending restart, restart it"
      curl -XPOST http://localhost:8008/restart
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
  fi
}

regenerate_spilo_configuration_and_start_postgres() {
  restart_for_pending_restart_flag 2>&1 >> /home/postgres/.kb_set_up.log &
  echo "$(date) restart_for_pending_restart_flag PID=$!" >> /home/postgres/.kb_set_up.log
  if [ -f "${RESTORE_DATA_DIR}"/kb_restore.signal ]; then
      chown -R postgres "${RESTORE_DATA_DIR}"
  fi
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
