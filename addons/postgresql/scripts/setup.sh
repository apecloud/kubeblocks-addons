#!/bin/bash
set -o errexit
set -e

function wait_pod_restarted() {
  for i in $(seq 1 10); do
    pending_restart=$(curl --connect-timeout 3 -s http://localhost:8008/cluster | jq -r ".members[] | select(.name == \"${KB_POD_NAME}\") | .pending_restart")
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
    pod_info_tmp_path="/tmp/pod_info.tmp"
    curl --connect-timeout 3 -s http://localhost:8008 > ${pod_info_tmp_path}

    if grep -q "state" ${pod_info_tmp_path}; then
      pod_info=$(<${pod_info_tmp_path})
      state=$(echo $pod_info | jq -r .state)
      if [[ "$state" != "running" && "$state" != "streaming" ]]; then
        continue
      fi
      if [ -f /home/postgres/pgdata/pgroot/data/recovery.signal ]; then
        replica_state=$(echo $pod_info | jq -r .replication_state)
        echo $pod_info
        if [[ "$replica_state" == "in archive recovery" ]]; then
           echo "$(date) ${KB_POD_NAME} is in archive recovery, restart it"
           curl -XPOST http://localhost:8008/restart
           rm -rf /home/postgres/pgdata/pgroot/data/recovery.signal
        fi
      fi
    else
        continue
    fi

    if grep -q "pending_restart" ${pod_info_tmp_path}; then
      pod_info=$(<${pod_info_tmp_path})
      pending_restart=$(echo $pod_info | jq -r .pending_restart)
      if [[ "$pending_restart" != "true" ]]; then
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
    if [[ "${pending_restart}" == "true" && (-z $leader_pending_restart_pod || "${leader_pod}" == "${KB_POD_NAME}") ]]; then
      # if leader pod is not pending_restart or current pod is leader pod, restart it
      echo "$(date) ${KB_POD_NAME} is pending restart, restart it"
      curl -XPOST http://localhost:8008/restart
      wait_pod_restarted
    fi
  done
}

# usage: retry <command>
# e.g. retry pg_isready -U postgres -h $primary_fqdn -p 5432
function retry {
  local max_attempts=10
  local attempt=1
  until "$@" || [ $attempt -eq $max_attempts ]; do
    echo "Command '$*' failed. Attempt $attempt of $max_attempts. Retrying in 5 seconds..."
    attempt=$((attempt + 1))
    sleep 5
  done
  if [ $attempt -eq $max_attempts ]; then
    echo "Command '$*' failed after $max_attempts attempts. Exiting..."
    exit 1
  fi
}

if [ -f /kb-podinfo/primary-pod ]; then
  # Waiting for primary pod information from the DownwardAPI annotation to be available, with a maximum of 5 attempts
  attempt=1
  max_attempts=10
  while [ $attempt -le $max_attempts ] && [ -z "$(cat /kb-podinfo/primary-pod)" ]; do
    sleep 3
    attempt=$((attempt + 1))
  done
  primary=$(cat /kb-podinfo/primary-pod)
  echo "DownwardAPI get primary=$primary" >> /home/postgres/pgdata/.kb_set_up.log
  echo "KB_POD_NAME=$KB_POD_NAME" >> /home/postgres/pgdata/.kb_set_up.log
else
   echo "DownwardAPI get /kb-podinfo/primary-pod is empty" >> /home/postgres/pgdata/.kb_set_up.log
fi

if  [ ! -z "$primary" ] && [ "$primary" != "$KB_POD_NAME" ]; then
    primary_fqdn="$primary.$KB_CLUSTER_NAME-$KB_COMP_NAME-headless.$KB_NAMESPACE.svc.${CLUSTER_DOMAIN}"
    echo "primary_fqdn=$primary_fqdn" >> /home/postgres/pgdata/.kb_set_up.log
    # waiting for the primary to be ready, if the wait time exceeds the maximum number of retries, then the script will fail and exit.
    retry pg_isready -U "postgres" -h $primary_fqdn -p 5432
fi

if [ -f ${RESTORE_DATA_DIR}/kb_restore.signal ]; then
    chown -R postgres ${RESTORE_DATA_DIR}
fi

if [ "$PG_MODE" == "standby" ]; then
    if [ ! -z "$KB_PGUSER_STANDBY" ]; then
        echo "override PGUSER_STANDBY:${PGUSER_STANDBY} to KB_PGUSER_STANDBY:${KB_PGUSER_STANDBY}" >> /home/postgres/pgdata/.kb_set_up.log
        export PGUSER_STANDBY="$KB_PGUSER_STANDBY"
    fi
    
    if [ ! -z "$KB_PGPASSWORD_STANDBY" ]; then
        echo "override PGPASSWORD_STANDBY:${PGPASSWORD_STANDBY} to KB_PGPASSWORD_STANDBY:${KB_PGPASSWORD_STANDBY}" >> /home/postgres/pgdata/.kb_set_up.log
        export PGPASSWORD_STANDBY="$KB_PGPASSWORD_STANDBY"
    fi
fi
restart_for_pending_restart_flag 2>&1 >> /home/postgres/.kb_set_up.log &
echo "$(date) restart_for_pending_restart_flag PID=$!" >> /home/postgres/.kb_set_up.log
python3 /kb-scripts/generate_patroni_yaml.py tmp_patroni.yaml
export SPILO_CONFIGURATION=$(cat tmp_patroni.yaml)

# if ETCD exist, unset KUBERNETES_SERVICE_HOST to use ETCD as DCS
if [ ! -z "$ETCD3_HOST" ] || [ ! -z "$ETCD_HOST" ]; then
  unset KUBERNETES_SERVICE_HOST
  unset DCS_ENABLE_KUBERNETES_API
fi

exec /launch.sh init
