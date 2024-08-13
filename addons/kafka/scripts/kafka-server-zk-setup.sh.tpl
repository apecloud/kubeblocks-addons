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
  if [[ -f "$PEM_CERT" ]] && [[ -f "$PEM_KEY" ]]; then
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
  echo "[tls]ssl.endpoint.identification.algorithm=" >> /opt/bitnami/kafka/config/kraft/server.properties
  echo "[tls]ssl.endpoint.identification.algorithm=" >> /opt/bitnami/kafka/config/server.properties
  
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

echo "zookeeper.connect=$KAFKA_CFG_ZOOKEEPER_CONNECT" >> /opt/bitnami/kafka/config/server.properties
echo "zookeeper.session.timeout.ms=18000" >> /opt/bitnami/kafka/config/server.properties
echo "zookeeper.connection.timeout.ms=6000" >> /opt/bitnami/kafka/config/server.properties

# jvm setting
if [[ -n "$KB_KAFKA_BROKER_HEAP" ]]; then
  export KAFKA_HEAP_OPTS=${KB_KAFKA_BROKER_HEAP}
  echo "[jvm][KB_KAFKA_BROKER_HEAP]export KAFKA_HEAP_OPTS=${KB_KAFKA_BROKER_HEAP}"
fi

# for support access Kafka brokers from outside the k8s cluster
if [[ -n "$KAFKA_CFG_K8S_NODEPORT" ]];then
  if [[ "broker" = "$KAFKA_CFG_PROCESS_ROLES" ]]; then
    export KAFKA_CFG_ADVERTISED_LISTENERS="PLAINTEXT://${KB_HOST_IP}:${KAFKA_CFG_K8S_NODEPORT}"
    echo "[cfg]KAFKA_CFG_ADVERTISED_LISTENERS=$KAFKA_CFG_ADVERTISED_LISTENERS"
    echo "[cfg]KAFKA_CFG_LISTENERS=$KAFKA_CFG_LISTENERS"
    echo "[cfg]KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=$KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP"
    echo "[cfg]KAFKA_CFG_INTER_BROKER_LISTENER_NAME=$KAFKA_CFG_INTER_BROKER_LISTENER_NAME"
  fi
fi

echo "listeners=$KAFKA_CFG_LISTENERS" >>  /opt/bitnami/kafka/config/server.properties
echo "listener.security.protocol.map=$KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP" >>  /opt/bitnami/kafka/config/server.properties
echo "advertised.listeners=$KAFKA_CFG_ADVERTISED_LISTENERS" >>  /opt/bitnami/kafka/config/server.properties
echo "inter.broker.listener.name=$KAFKA_CFG_INTER_BROKER_LISTENER_NAME"  >>  /opt/bitnami/kafka/config/server.properties

# cfg setting
if [[ "broker" = "$KAFKA_CFG_PROCESS_ROLES" ]]; then
    INDEX=$(echo $KB_POD_NAME | grep -o "\-[0-9]\+\$")
    INDEX=${INDEX#-}
    BROKER_NODE_ID=$(( $INDEX + $BROKER_MIN_NODE_ID ))
    export KAFKA_CFG_NODE_ID="$BROKER_NODE_ID"
    export KAFKA_CFG_BROKER_ID="$BROKER_NODE_ID"
    echo "[cfg]KAFKA_CFG_NODE_ID=$KAFKA_CFG_NODE_ID"
fi

exec /entrypoint.sh /run.sh