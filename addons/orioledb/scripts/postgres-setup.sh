#!/bin/bash

tmp_patroni_yaml="tmp_patroni.yaml"

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
    if [ "$ETCDCTL_API" = "3" ]; then
      export ETCD3_HOSTS=$PATRONI_DCS_ETCD_SERVICE_ENDPOINT
    else
      export ETCD_HOSTS=$PATRONI_DCS_ETCD_SERVICE_ENDPOINT
    fi
  fi
}

regenerate_spilo_configuration_and_start_postgres() {
  if [ -d "/home/postgres/pgdata/conf" ]; then
    chmod 750 /home/postgres/pgdata/pgroot/data
  else
    mkdir -p /home/postgres/pgdata/conf
    chmod 777 -R /home/postgres/pgdata
    cp /home/postgres/conf/postgresql.conf /home/postgres/pgdata/conf
    chmod 777 -R /home/postgres/pgdata/conf
  fi

  IFS='-' read -ra parts <<< "$CURRENT_POD_NAME"
  if [ ${parts[-1]} != '0' ]; then
    MAX_RETRIES=30
    WAIT_INTERVAL=5
    retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
      POD_0_FQDN="$POSTGRES_COMPONENT_NAME-0-$POSTGRES_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.cluster.local"
      pg_isready -h $POD_0_FQDN
      status=$?
      if [ $status -eq 0 ]; then
        echo "PostgreSQL is ready!"
        break
      else
        echo "PostgreSQL is not ready yet. Retrying in $WAIT_INTERVAL seconds..."
        sleep $WAIT_INTERVAL
        retries=$((retries + 1))
      fi
    done
  else
    cp /kb-scripts/init.sql /docker-entrypoint-initdb.d
    bash /usr/local/bin/docker-entrypoint.sh postgres
  fi

  python3 /kb-scripts/generate_patroni_yaml.py /var/lib/postgresql/tmp_patroni.yaml
  chmod 777 /var/lib/postgresql/tmp_patroni.yaml
  su - postgres -c "patroni /var/lib/postgresql/tmp_patroni.yaml"
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
