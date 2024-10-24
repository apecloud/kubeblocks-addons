#!/bin/bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

generate_kafka_servers() {
  local servers=""
  
  if [[ -z "$BROKER_POD_FQDN_LIST" ]] && [[ -z "$COMBINE_POD_FQDN_LIST" ]]; then
    echo "Error: BROKER_POD_FQDN_LIST and COMBINE_POD_FQDN_LIST environment variable is not set, Please check and try again." >&2
    return 1
  fi

  ## try to use COMBINE_POD_FQDN_LIST first
  if [[ -n "$COMBINE_POD_FQDN_LIST" ]]; then
    IFS=',' read -r -a combine_pod_fqdn_list <<< "$COMBINE_POD_FQDN_LIST"
    for pod_fqdn in "${combine_pod_fqdn_list[@]}"; do
      servers="${servers} --kafka.server=${pod_fqdn}:9094"
    done
    echo "$servers"
    return 0
  fi

  # if COMBINE_POD_FQDN_LIST is not set, use BROKER_POD_FQDN_LIST
  IFS=',' read -r -a broker_pod_fqdn_list <<< "$BROKER_POD_FQDN_LIST"
  for pod_fqdn in "${broker_pod_fqdn_list[@]}"; do
    servers="${servers} --kafka.server=${pod_fqdn}:9094"
  done
  echo "$servers"
  return 0
}

get_start_kafka_exporter_cmd() {
  local servers
  local status
  servers=$(generate_kafka_servers)
  status=$?
  if [[ $status -ne 0 ]]; then
    echo "failed to generate kafka servers. Exiting." >&2
    return 1
  fi

  if [[ -n "$TLS_ENABLED" ]]; then
    echo "TLS_ENABLED is set to true, start kafka_exporter with tls enabled." >&2
    echo "kafka_exporter --web.listen-address=:9308 --tls.enabled ${servers}"
  else
    echo "TLS_ENABLED is not set, start kafka_exporter with tls disabled." >&2
    echo "kafka_exporter --web.listen-address=:9308 ${servers}"
  fi
  return 0
}

start_kafka_exporter() {
  local cmd
  cmd=$(get_start_kafka_exporter_cmd)
  status=$?
  if [[ $status -ne 0 ]]; then
    ehco "failed to get start kafka_exporter command. Exiting." >&2
    exit 1
  fi
  $cmd
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
start_kafka_exporter
