#!/bin/bash
set -x

extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

parse_advertised_svc_if_exist() {
  local pod_name="${KB_POD_NAME}"
  local pod_service_list="${1}"

  if [[ "$pod_service_list" == "" ]]; then
    echo "Ignoring."
    return 0
  fi

  # the value format of $pod_service_list is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  IFS=',' read -ra advertised_ports <<< "$pod_service_list"
  echo "~~~~~~advertised_ports:${advertised_ports}"
  local found=false
  pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
  echo "~~~~~~pod_name_ordinal:${pod_name_ordinal}"
  for advertised_port in "${advertised_ports[@]}"; do
    IFS=':' read -ra parts <<< "$advertised_port"
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_ordinal_from_object_name "$svc_name")
    echo "~~~~~~svc_name:${svc_name},port:${port},svc_name_ordinal:${svc_name_ordinal}"
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', BROKER_ADVERTISED_PORT: $pod_service_list. svcName: $svc_name, port: $port."
      advertised_svc_port_value="$port"
      found=true
      break
    fi
  done

  if [[ "$found" == false ]]; then
    echo "Error: No matching svcName and port found for podName '$pod_name', BROKER_ADVERTISED_PORT: $pod_service_list. Exiting."
    exit 1
  fi
}

if [[ "true" == "$KB_PULSAR_BROKER_NODEPORT" ]]; then
  echo "init NodePort config:"
  parse_advertised_svc_if_exist "${ADVERTISED_PORT_PULSAR}"
  nodeport_pulsar_domain="${KB_HOST_IP}:${advertised_svc_port_value}"
  parse_advertised_svc_if_exist "${ADVERTISED_PORT_KAFKA}"
  nodeport_kafka_domain="${KB_HOST_IP}:${advertised_svc_port_value}"
  export PULSAR_PREFIX_advertisedListeners="cluster:pulsar://${nodeport_pulsar_domain}"
  echo "[cfg]set PULSAR_PREFIX_advertisedListeners=${PULSAR_PREFIX_advertisedListeners}"
  export PULSAR_PREFIX_kafkaAdvertisedListeners="CLIENT://${nodeport_kafka_domain}"
  echo "[cfg]set PULSAR_PREFIX_kafkaAdvertisedListeners=${PULSAR_PREFIX_kafkaAdvertisedListeners}"
fi

/kb-scripts/merge_pulsar_config.py conf/client.conf /opt/pulsar/conf/client.conf && \
/kb-scripts/merge_pulsar_config.py conf/broker.conf /opt/pulsar/conf/broker.conf && \
bin/apply-config-from-env.py conf/broker.conf && \
bin/apply-config-from-env.py conf/client.conf && \

echo 'OK' > status;exec bin/pulsar broker