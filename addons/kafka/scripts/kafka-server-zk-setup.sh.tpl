#!/bin/bash

# TLS setting
{{- if $.component.tlsConfig }}
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
  export KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,CLIENT:SSL
  echo "KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=$KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP"
  # Todo: enable encrypted transmission inside the service
  #export KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:SSL,INTERNAL:SSL,CLIENT:SSL
  #export KAFKA_CFG_SECURITY_INTER_BROKER_PROTOCOL=SSL
  #echo "KAFKA_CFG_SECURITY_INTER_BROKER_PROTOCOL=SSL"

  mkdir -p /opt/bitnami/kafka/config/certs
  PEM_CA="$KB_TLS_CERT_PATH/ca.crt"
  PEM_CERT="$KB_TLS_CERT_PATH/tls.crt"
  PEM_KEY="$KB_TLS_CERT_PATH/tls.key"
  if [[ -f "$PEM_CERT" ]] && [[ -f "$PEM_KEY" ]] && [[ -f "$PEM_CA" ]]; then
      CERT_DIR="/opt/bitnami/kafka/config/certs"
      PEM_CA_LOCATION="${CERT_DIR}/kafka.truststore.pem"
      PEM_CERT_LOCATION="${CERT_DIR}/kafka.keystore.pem"
          if [[ -f "$PEM_CA" ]]; then
              cp "$PEM_CA" "$PEM_CA_LOCATION"
              cp "$PEM_CERT" "$PEM_CERT_LOCATION"
          else
              echo "[tls]PEM_CA not provided, and auth.tls.pemChainIncluded was not true. One of these values must be set when using PEM type for TLS."
              exit 1
          fi

      # Ensure the key used PEM format with PKCS#8
      openssl pkcs8 -topk8 -nocrypt -in "$PEM_KEY" > "${CERT_DIR}/kafka.keystore.key"
      # combined the certificate and private-key for client use
      cat ${CERT_DIR}/kafka.keystore.key ${PEM_CERT_LOCATION} > ${CERT_DIR}/client.combined.key
  else
      echo "[tls]Couldn't find the expected PEM files! They are mandatory when encryption via TLS is enabled."
      exit 1
  fi
  export KAFKA_TLS_TRUSTSTORE_FILE="/opt/bitnami/kafka/config/certs/kafka.truststore.pem"
  echo "[tls]KAFKA_TLS_TRUSTSTORE_FILE=$KAFKA_TLS_TRUSTSTORE_FILE"

{{- end }}

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

# override SASL settings
if [[ "true" == "$KB_KAFKA_ENABLE_SASL" ]]; then
  # bitnami default jaas setting: /opt/bitnami/kafka/config/kafka_jaas.conf
  if [[ "${KB_KAFKA_SASL_CONFIG_PATH}" ]]; then
    cp ${KB_KAFKA_SASL_CONFIG_PATH} /opt/bitnami/kafka/config/kafka_jaas.conf
    echo "[sasl]do: cp ${KB_KAFKA_SASL_CONFIG_PATH} /opt/bitnami/kafka/config/kafka_jaas.conf "
  fi
  export KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:SASL_PLAINTEXT,CLIENT:SASL_PLAINTEXT
  echo "[sasl]KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=$KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP"
  export KAFKA_CFG_SASL_ENABLED_MECHANISMS="PLAIN"
  echo "[sasl]export KAFKA_CFG_SASL_ENABLED_MECHANISMS=${KAFKA_CFG_SASL_ENABLED_MECHANISMS}"
  export KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL="PLAIN"
  echo "[sasl]export KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL=${KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL}"
fi

IFS=',' read -ra ZOOKEEPER_FDQN_ARRAY <<< "$ZOOKEEPER_POD_FQDN"
endpoints=""
for fdqd in "${ZOOKEEPER_FDQN_ARRAY[@]}"; do
  endpoints+="${fdqd}:${ZOOKEEPER_CLIENT_PORT},"
done
endpoints="${endpoints%,}"
export KAFKA_CFG_ZOOKEEPER_CONNECT=$endpoints
echo "[cfg]KAFKA_CFG_ZOOKEEPER_CONNECT=${KAFKA_CFG_ZOOKEEPER_CONNECT}"

# jvm setting
if [[ -n "$KB_KAFKA_BROKER_HEAP" ]]; then
  export KAFKA_HEAP_OPTS=${KB_KAFKA_BROKER_HEAP}
  echo "[jvm][KB_KAFKA_BROKER_HEAP]export KAFKA_HEAP_OPTS=${KB_KAFKA_BROKER_HEAP}"
fi

extract_ordinal_from_object_name() {
    local object_name="$1"
    local ordinal="${object_name##*-}"
    echo "$ordinal"
}

parse_advertised_svc_if_exist() {
    local pod_name="${KB_POD_NAME}"

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
            advertised_svc_host_value="$KB_HOST_IP"
            found=true
            break
        fi
    done

    if [[ "$found" == false ]]; then
        echo "Error: No matching svcName and port found for podName '$pod_name', BROKER_ADVERTISED_PORT: $BROKER_ADVERTISED_PORT. Exiting."
        exit 1
    fi
}

# cfg setting
headless_domain="${KB_POD_FQDN}${cluster_domain}"
parse_advertised_svc_if_exist

# Todo: currently only nodeport and clusterip network modes are supported. LoadBalance is not supported yet and needs future support.
if [ -n "$advertised_svc_host_value" ] && [ -n "$advertised_svc_port_value" ] && [ "$advertised_svc_port_value" != "9092" ]; then
    # enable NodePort, use node ip + mapped port as client connection
    nodeport_domain="${advertised_svc_host_value}:${advertised_svc_port_value}"
    export KAFKA_CFG_ADVERTISED_LISTENERS="INTERNAL://${headless_domain}:9094,CLIENT://${nodeport_domain}"
    echo "[cfg]KAFKA_CFG_ADVERTISED_LISTENERS=$KAFKA_CFG_ADVERTISED_LISTENERS"
else
    # default, use headless service url as client connection
    export KAFKA_CFG_ADVERTISED_LISTENERS="INTERNAL://${headless_domain}:9094,CLIENT://${headless_domain}:9092"
    echo "[cfg]KAFKA_CFG_ADVERTISED_LISTENERS=$KAFKA_CFG_ADVERTISED_LISTENERS"
fi
INDEX=$(echo $KB_POD_NAME | grep -o "\-[0-9]\+\$")
INDEX=${INDEX#-}
BROKER_NODE_ID=$(( $INDEX + $BROKER_MIN_NODE_ID ))
export KAFKA_CFG_BROKER_ID="$BROKER_NODE_ID"
echo "[cfg]KAFKA_CFG_BROKER_ID=$BROKER_NODE_ID"


exec /entrypoint.sh /run.sh