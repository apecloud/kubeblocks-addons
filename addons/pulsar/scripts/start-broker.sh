#!/bin/bash
set -x

extract_ordinal_from_pod_name() {
  local pod_name="$1"
  local ordinal="${pod_name##*-}"
  echo "$ordinal"
}

make_nodeport_domain() {
  local nodeport_env_name="$1"
  eval port="\$${nodeport_env_name}"
  echo "${KB_HOST_IP}:${port}"
}

if [[ "true" == "$KB_PULSAR_BROKER_NODEPORT" ]]; then
  echo "init NodePort config:"
  pod_ordinal=$(extract_ordinal_from_pod_name "$KB_POD_NAME")
  nodeport_pulsar_domain=$(make_nodeport_domain "NODE_PORT_PULSAR_${pod_ordinal}")
  nodeport_kafka_domain=$(make_nodeport_domain "NODE_PORT_KAFKA_${pod_ordinal}")
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