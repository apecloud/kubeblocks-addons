#!/bin/bash

# shellcheck disable=SC2154
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

extract_ordinal_from_object_name() {
  local object_name="$1"
  echo "${object_name##*-}"
}

parse_advertised_svc_if_exist() {
  # shellcheck disable=SC2153
  local pod_name="${POD_NAME}"
  local pod_service_list="$1"

  if [[ -z "$pod_service_list" ]]; then
    echo "Ignoring."
    return 0
  fi

  IFS=',' read -ra advertised_ports <<< "$pod_service_list"
  echo "advertised_ports: ${advertised_ports[*]}"

  local pod_name_ordinal
  pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
  echo "pod_name_ordinal: $pod_name_ordinal"

  for advertised_port in "${advertised_ports[@]}"; do
    process_advertised_port "$advertised_port" "$pod_name_ordinal" "$pod_name"
  done

  # check advertised_svc_port_value is set
  if [[ -z "$advertised_svc_port_value" ]]; then
    handle_no_matching_service
  fi
}

process_advertised_port() {
  local advertised_port="$1"
  local pod_name_ordinal="$2"
  local pod_name="$3"

  IFS=':' read -ra parts <<< "$advertised_port"
  local svc_name="${parts[0]}"
  local port="${parts[1]}"
  local svc_name_ordinal
  svc_name_ordinal=$(extract_ordinal_from_object_name "$svc_name")
  echo "svc_name: $svc_name, port: $port, svc_name_ordinal: $svc_name_ordinal, pod_name_ordinal: $pod_name_ordinal"

  if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
    echo "Found matching svcName and port for podName '$pod_name', BROKER_ADVERTISED_PORT: $ADVERTISED_PORT_PULSAR. svcName: $svc_name, port: $port."
    advertised_svc_port_value="$port"
    return 0
  fi
}

handle_no_matching_service() {
  echo "Error: No matching svcName and port found for podName '$POD_NAME', BROKER_ADVERTISED_PORT: $ADVERTISED_PORT_PULSAR. Exiting."
  exit 1
}

initialize_nodeport_config() {
  echo "init NodePort config:"
  parse_advertised_svc_if_exist "${ADVERTISED_PORT_PULSAR}"
  local nodeport_pulsar_domain="${POD_HOST_IP}:${advertised_svc_port_value}"

  parse_advertised_svc_if_exist "${ADVERTISED_PORT_KAFKA}"
  local nodeport_kafka_domain="${POD_HOST_IP}:${advertised_svc_port_value}"

  export PULSAR_PREFIX_advertisedListeners="cluster:pulsar://${nodeport_pulsar_domain}"
  echo "[cfg] set PULSAR_PREFIX_advertisedListeners=${PULSAR_PREFIX_advertisedListeners}"

  export PULSAR_PREFIX_kafkaAdvertisedListeners="CLIENT://${nodeport_kafka_domain}"
  echo "[cfg] set PULSAR_PREFIX_kafkaAdvertisedListeners=${PULSAR_PREFIX_kafkaAdvertisedListeners}"
}

merge_configuration_files() {
  /kb-scripts/merge_pulsar_config.py conf/client.conf /opt/pulsar/conf/client.conf
  /kb-scripts/merge_pulsar_config.py conf/broker.conf /opt/pulsar/conf/broker.conf
  bin/apply-config-from-env.py conf/broker.conf
  bin/apply-config-from-env.py conf/client.conf
}

start_broker() {
  ## TODO: $KB_PULSAR_BROKER_NODEPORT define in cluster annotation extra-envs, which need to be refactored
  if [[ "$KB_PULSAR_BROKER_NODEPORT" == "true" ]]; then
    initialize_nodeport_config
  fi

  merge_configuration_files

  echo 'OK' > status
  exec bin/pulsar broker
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
start_broker