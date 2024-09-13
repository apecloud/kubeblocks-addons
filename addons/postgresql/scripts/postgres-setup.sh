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
