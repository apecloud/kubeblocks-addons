#!/bin/bash

# shellcheck disable=SC2153
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

kafka_config_certs_path="/opt/bitnami/kafka/config/certs"
kafka_kraft_config_path="/opt/bitnami/kafka/config/kraft"
kafka_config_path="/opt/bitnami/kafka/config"

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

set_tls_configuration_if_needed() {
  ## check env TLS_ENABLED and TLS_CERT_PATH env variables
  ## TODO: how to pass TLS_ENABLED and TLS_CERT_PATH to kafka-server-setup.sh？ currently, it is not supported.
  if [[ -z "$TLS_ENABLED" ]] || [[ -z "$TLS_CERT_PATH" ]]; then
    echo "TLS_ENABLED or TLS_CERT_PATH is not set, skipping TLS configuration"
    return 0
  fi

  # override TLS and auth settings
  export KAFKA_TLS_TYPE="PEM"
  echo "[tls]KAFKA_TLS_TYPE=$KAFKA_TLS_TYPE"
  export KAFKA_CFG_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=""
  echo "[tls]KAFKA_CFG_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=$KAFKA_CFG_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM"
  export KAFKA_CERTIFICATE_PASSWORD=""
  echo "[tls]KAFKA_CERTIFICATE_PASSWORD=$KAFKA_CERTIFICATE_PASSWORD"
  export KAFKA_TLS_CLIENT_AUTH=none
  echo "[tls]KAFKA_TLS_CLIENT_AUTH=$KAFKA_TLS_CLIENT_AUTH"

  # override TLS protocol
  export KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,CLIENT:SSL
  echo "KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=$KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP"
  # Todo: enable encrypted transmission inside the service
  #export KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:SSL,INTERNAL:SSL,CLIENT:SSL
  #export KAFKA_CFG_SECURITY_INTER_BROKER_PROTOCOL=SSL
  #echo "KAFKA_CFG_SECURITY_INTER_BROKER_PROTOCOL=SSL"

  mkdir -p "$kafka_config_certs_path"
  PEM_CA="$TLS_CERT_PATH/ca.crt"
  PEM_CERT="$TLS_CERT_PATH/tls.crt"
  PEM_KEY="$TLS_CERT_PATH/tls.key"
  if [[ -f "$PEM_CERT" ]] && [[ -f "$PEM_KEY" ]]; then
    CERT_DIR="$kafka_config_certs_path"
    PEM_CA_LOCATION="${CERT_DIR}/kafka.truststore.pem"
    PEM_CERT_LOCATION="${CERT_DIR}/kafka.keystore.pem"
      if [[ -f "$PEM_CA" ]]; then
        cp "$PEM_CA" "$PEM_CA_LOCATION"
        cp "$PEM_CERT" "$PEM_CERT_LOCATION"
      else
        echo "[tls]PEM_CA not provided, and auth.tls.pemChainIncluded was not true. One of these values must be set when using PEM type for TLS." >&2
        return 1
      fi

    # Ensure the key used PEM format with PKCS#8
    openssl pkcs8 -topk8 -nocrypt -in "$PEM_KEY" > "${CERT_DIR}/kafka.keystore.key"
    # combined the certificate and private-key for client use
    cat ${CERT_DIR}/kafka.keystore.key ${PEM_CERT_LOCATION} > ${CERT_DIR}/client.combined.key
  else
    echo "[tls]Couldn't find the expected PEM files! They are mandatory when encryption via TLS is enabled." >&2
    return 1
  fi
  export KAFKA_TLS_TRUSTSTORE_FILE="$kafka_config_certs_path/kafka.truststore.pem"
  echo "[tls]KAFKA_TLS_TRUSTSTORE_FILE=$KAFKA_TLS_TRUSTSTORE_FILE"
  echo "[tls]ssl.endpoint.identification.algorithm=" >> $kafka_kraft_config_path/server.properties
  echo "[tls]ssl.endpoint.identification.algorithm=" >> $kafka_config_path/server.properties
  return 0
}

convert_server_properties_to_env_var() {
  # cfg setting with props
  # convert server.properties to 'export KAFKA_CFG_{prop}' env variables
  SERVER_PROP_PATH=${SERVER_PROP_PATH:-/bitnami/kafka/config/server.properties}
  SERVER_PROP_FILE=${SERVER_PROP_FILE:-server.properties}

  if [[ -f "$SERVER_PROP_FILE" ]]; then
    IFS='='
    while read -r line; do
      if [[ "$line" =~ ^#.* ]]; then
        continue
      fi
      echo "convert prop ${line}"
      read -ra kv <<< "$line"
      len=${#kv[@]}
      if [[ $len != 2 ]]; then
        echo "line '${line}' has no value; skipped"
        continue
      fi
      env_suffix=${kv[0]^^}
      env_suffix=${env_suffix//./_}
      env_suffix=`eval echo "${env_suffix}"`
      env_value=`eval echo "${kv[1]}"`
      export KAFKA_CFG_${env_suffix}="${env_value}"
      echo "[cfg]export KAFKA_CFG_${env_suffix}=${env_value}"
    done <$SERVER_PROP_FILE
    unset IFS
  fi
}

override_sasl_configuration() {
  # override SASL settings
  if [[ "true" == "$KB_KAFKA_ENABLE_SASL" ]]; then
    # bitnami default jaas setting: /opt/bitnami/kafka/config/kafka_jaas.conf
    if [[ "${KB_KAFKA_SASL_CONFIG_PATH}" ]]; then
      cp ${KB_KAFKA_SASL_CONFIG_PATH} $kafka_config_path/kafka_jaas.conf 2>/dev/null
      echo "[sasl]do: cp ${KB_KAFKA_SASL_CONFIG_PATH} $kafka_config_path/kafka_jaas.conf "
    fi
    export KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,INTERNAL:SASL_PLAINTEXT,CLIENT:SASL_PLAINTEXT
    echo "[sasl]KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=$KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP"
    export KAFKA_CFG_SASL_ENABLED_MECHANISMS="PLAIN"
    echo "[sasl]export KAFKA_CFG_SASL_ENABLED_MECHANISMS=${KAFKA_CFG_SASL_ENABLED_MECHANISMS}"
    export KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL="PLAIN"
    echo "[sasl]export KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL=${KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL}"
  fi
}

generate_kraft_cluster_id() {
  if [[ -n "$KAFKA_KRAFT_CLUSTER_ID" ]]; then
    echo KAFKA_KRAFT_CLUSTER_ID="${KAFKA_KRAFT_CLUSTER_ID}"
    kraft_id_len=${#KAFKA_KRAFT_CLUSTER_ID}
    if [[ kraft_id_len -gt 22 ]]; then
      export KAFKA_KRAFT_CLUSTER_ID=$(echo $KAFKA_KRAFT_CLUSTER_ID | cut -b 1-22)
      echo export KAFKA_KRAFT_CLUSTER_ID="${KAFKA_KRAFT_CLUSTER_ID}"
    fi
  fi
}

set_jvm_configuration() {
  # jvm setting
  if [[ -n "$KB_KAFKA_BROKER_HEAP" ]]; then
    export KAFKA_HEAP_OPTS=${KB_KAFKA_BROKER_HEAP}
    echo "[jvm][KB_KAFKA_BROKER_HEAP]export KAFKA_HEAP_OPTS=${KB_KAFKA_BROKER_HEAP}"
  fi
}

extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

parse_advertised_svc_if_exist() {
  local pod_name="${MY_POD_NAME}"

  if [[ -z "${BROKER_ADVERTISED_PORT}" ]]; then
    echo "Environment variable BROKER_ADVERTISED_PORT not found. Ignoring."
    return 0
  fi

  # the value format of BROKER_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  IFS=',' read -ra advertised_ports <<< "${BROKER_ADVERTISED_PORT}"
  echo "find advertised_ports:${advertised_ports}"
  local found=false
  pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
  echo "find pod_name_ordinal:${pod_name_ordinal}"
  for advertised_port in "${advertised_ports[@]}"; do
    IFS=':' read -ra parts <<< "$advertised_port"
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_ordinal_from_object_name "$svc_name")
    echo "find svc_name:${svc_name},port:${port},svc_name_ordinal:${svc_name_ordinal}"
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', BROKER_ADVERTISED_PORT: $BROKER_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      advertised_svc_port_value="$port"
      advertised_svc_host_value="$MY_POD_HOST_IP"
      found=true
      break
    fi
  done

  if [[ "$found" == false ]]; then
    echo "Error: No matching svcName and port found for podName '$pod_name', BROKER_ADVERTISED_PORT: $BROKER_ADVERTISED_PORT. Exiting." >&2
    return 1
  fi
}

set_cfg_metadata() {
  # independent broker component in separate cluster or combine component in combine-cluster need to set advertised.listeners
  if [[ "broker,controller" = "$KAFKA_CFG_PROCESS_ROLES" ]] || [[ "broker" = "$KAFKA_CFG_PROCESS_ROLES" ]]; then
    # deleting this information can reacquire the controller members when the broker restarts,
    # and avoid the mismatch between the controller in the quorum-state and the actual controller in the case of a controller scale,
    # which will cause the broker to fail to start
    if [ -f "$KAFKA_CFG_METADATA_LOG_DIR/__cluster_metadata-0/quorum-state" ]; then
      echo "[action]Removing quorum-state file when restart."
      rm -f "$KAFKA_CFG_METADATA_LOG_DIR/__cluster_metadata-0/quorum-state"
    fi

    current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$POD_FQDN_LIST" "$MY_POD_NAME")
    if is_empty "$current_pod_fqdn"; then
      echo "Error: Failed to get current pod: $MY_POD_NAME fqdn from pod fqdn list: $POD_FQDN_LIST. Exiting." >&2
      return 1
    fi

    if ! parse_advertised_svc_if_exist ; then
      echo "Error: Failed to parse advertised svc from BROKER_ADVERTISED_PORT: $BROKER_ADVERTISED_PORT. Exiting." >&2
      return 1
    fi

    # Todo: currently only nodeport and clusterIp network modes are supported. LoadBalance is not supported yet and needs future support.
    if [ -n "$advertised_svc_host_value" ] && [ -n "$advertised_svc_port_value" ] && [ "$advertised_svc_port_value" != "9092" ]; then
      # enable NodePort, use node ip + mapped port as client connection
      nodeport_domain="${advertised_svc_host_value}:${advertised_svc_port_value}"
      export KAFKA_CFG_ADVERTISED_LISTENERS="INTERNAL://${current_pod_fqdn}:9094,CLIENT://${nodeport_domain}"
      echo "[cfg]KAFKA_CFG_ADVERTISED_LISTENERS=$KAFKA_CFG_ADVERTISED_LISTENERS"
    else
      # default, use headless service url as client connection
      export KAFKA_CFG_ADVERTISED_LISTENERS="INTERNAL://${current_pod_fqdn}:9094,CLIENT://${current_pod_fqdn}:9092"
      echo "[cfg]KAFKA_CFG_ADVERTISED_LISTENERS=$KAFKA_CFG_ADVERTISED_LISTENERS"
    fi
  fi

  if [[ "broker" = "$KAFKA_CFG_PROCESS_ROLES" ]]; then
    # override node.id setting
    # increments based on a specified base to avoid conflicts with controller settings
    INDEX=$(echo $MY_POD_NAME | grep -o "\-[0-9]\+\$")
    INDEX=${INDEX#-}
    BROKER_NODE_ID=$(( $INDEX + $BROKER_MIN_NODE_ID ))
    export KAFKA_CFG_NODE_ID="$BROKER_NODE_ID"
    export KAFKA_CFG_BROKER_ID="$BROKER_NODE_ID"
    echo "[cfg]KAFKA_CFG_NODE_ID=$KAFKA_CFG_NODE_ID"

    # generate KAFKA_CFG_CONTROLLER_QUORUM_VOTERS for broker if not a combine-cluster
    local pod_index
    local pod_fqdn
    local voters=""
    IFS=',' read -r -a controller_pod_name_list <<< "$CONTROLLER_POD_NAME_LIST"
    for pod_name in "${controller_pod_name_list[@]}"; do
      # pod_fqdn format: kafka-controller-0.kafka-controller-headless.svc.cluster.local, get pod_index from pod_fqdn
      pod_index=$(extract_ordinal_from_object_name "$pod_name")
      pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CONTROLLER_POD_FQDN_LIST" "$pod_name")
      local voter="${pod_index}@${pod_fqdn}:9093"
      voters="${voters},${voter}"
    done
    voters=${voters#,}
    export KAFKA_CFG_CONTROLLER_QUORUM_VOTERS="$voters"
    echo "[cfg]export KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=$KAFKA_CFG_CONTROLLER_QUORUM_VOTERS,for kafka-broker."
  else
    if [[ "controller" = "$KAFKA_CFG_PROCESS_ROLES" ]] && [[ -n "$KB_KAFKA_CONTROLLER_HEAP" ]]; then
      export KAFKA_HEAP_OPTS=${KB_KAFKA_CONTROLLER_HEAP}
      echo "[jvm][KB_KAFKA_CONTROLLER_HEAP]export KAFKA_HEAP_OPTS=${KB_KAFKA_CONTROLLER_HEAP}"
    fi
    # generate node.id
    ID="${MY_POD_NAME#${COMPONENT_NAME}-}"
    export KAFKA_CFG_NODE_ID="$((ID + 0))"
    export KAFKA_CFG_BROKER_ID="$((ID + 0))"
    echo "[cfg]KAFKA_CFG_NODE_ID=$KAFKA_CFG_NODE_ID"

    # generate KAFKA_CFG_CONTROLLER_QUORUM_VOTERS if is a combine-cluster or controller
    local pod_index
    local pod_fqdn
    local voters=""
    IFS=',' read -r -a pod_name_list <<< "$POD_NAME_LIST"
    for pod_name in "${pod_name_list[@]}"; do
      # pod_fqdn format: kafka-controller-0.kafka-controller-headless.svc.cluster.local, get pod_index from pod_fqdn
      pod_index=$(extract_ordinal_from_object_name "$pod_name")
      pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$POD_FQDN_LIST" "$pod_name")
      local voter="${pod_index}@${pod_fqdn}:9093"
      voters="${voters},${voter}"
    done
    voters=${voters#,}
    export KAFKA_CFG_CONTROLLER_QUORUM_VOTERS="$voters"
    echo "[cfg]export KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=$KAFKA_CFG_CONTROLLER_QUORUM_VOTERS,for kafka-server."
  fi
}

start_server() {
  load_common_library
  set_tls_configuration_if_needed
  convert_server_properties_to_env_var
  override_sasl_configuration
  generate_kraft_cluster_id
  set_jvm_configuration
  set_cfg_metadata

  exec /entrypoint.sh /run.sh
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
start_server