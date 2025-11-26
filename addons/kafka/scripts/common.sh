#!/bin/bash
set -e

kafka_libs_path="/opt/bitnami/kafka/libs"
kafka_config_path="/opt/bitnami/kafka/config"

is_sasl_enabled() {
    isZkOrNot="$1"

    if [[ "${KB_KAFKA_ENABLE_SASL}" == "true" ]] || [[ "${KB_KAFKA_SASL_ENABLE}" == "true" ]]; then
        echo "true"
    elif [[ "${isZkOrNot}" == "true" ]] && [[ "${KB_KAFKA_ENABLE_SASL_SCRAM}" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

is_sasl_build_in_enabled() {
    if [[ "${KB_KAFKA_SASL_ENABLE:-false}" == "false" ]] || [[ "${KB_KAFKA_ENABLE_SASL_SCRAM:-false}" == "true" ]]; then
        echo "false"
    else
        echo "${KB_KAFKA_SASL_USE_KB_BUILTIN:-false}"
    fi
}

build_zk_server_sasl_properties() {
    local ENABLED_MECHANISMS="SCRAM-SHA-256,SCRAM-SHA-512"
    local INTER_BROKER_PROTOCOL="SCRAM-SHA-512"

    if [[ "${KB_KAFKA_SASL_ENABLE}" == "true" ]] && [[ -n "${KB_KAFKA_SASL_MECHANISMS}" ]] && [[ -n "${KB_KAFKA_SASL_INTER_BROKER_PROTOCOL}" ]]; then
        ENABLED_MECHANISMS=${KB_KAFKA_SASL_MECHANISMS}
        INTER_BROKER_PROTOCOL=${KB_KAFKA_SASL_INTER_BROKER_PROTOCOL}
    fi

    export KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:SASL_PLAINTEXT,CLIENT:SASL_PLAINTEXT
    echo "[sasl]KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=$KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP"
    export KAFKA_CFG_SASL_ENABLED_MECHANISMS="${ENABLED_MECHANISMS}"
    echo "[sasl]export KAFKA_CFG_SASL_ENABLED_MECHANISMS=${KAFKA_CFG_SASL_ENABLED_MECHANISMS}"
    export KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL="${INTER_BROKER_PROTOCOL}"
    echo "[sasl]export KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL=${KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL}"
}

build_kraft_server_sasl_properties() {
    local ENABLED_MECHANISMS="PLAIN"
    local INTER_BROKER_PROTOCOL="PLAIN"

    if [[ "${KB_KAFKA_SASL_ENABLE}" == "true" ]] && [[ -n "${KB_KAFKA_SASL_MECHANISMS}" ]] && [[ -n "${KB_KAFKA_SASL_INTER_BROKER_PROTOCOL}" ]]; then
        ENABLED_MECHANISMS=${KB_KAFKA_SASL_MECHANISMS}
        INTER_BROKER_PROTOCOL=${KB_KAFKA_SASL_INTER_BROKER_PROTOCOL}
    fi

    export KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,INTERNAL:SASL_PLAINTEXT,CLIENT:SASL_PLAINTEXT
    echo "[sasl]KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=$KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP"
    export KAFKA_CFG_SASL_ENABLED_MECHANISMS="${ENABLED_MECHANISMS}"
    echo "[sasl]export KAFKA_CFG_SASL_ENABLED_MECHANISMS=${KAFKA_CFG_SASL_ENABLED_MECHANISMS}"
    export KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL="${INTER_BROKER_PROTOCOL}"
    echo "[sasl]export KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL=${KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL}"
}

build_server_jaas_config() {
    local admin_password="${KAFKA_ADMIN_PASSWORD}"
    local client_password="${KAFKA_CLIENT_PASSWORD}"
    local login_module="${1}"

    if [ "$(is_sasl_build_in_enabled)" == "true" ]; then
        # build-in only support plain yet
        login_module="org.apache.kafka.common.security.plain.PlainLoginModule required"
    fi

    cat << EOF > ${kafka_config_path}/kafka_jaas.conf
KafkaServer {
  ${login_module}
  username="$KAFKA_ADMIN_USER"
  password="$admin_password";
};
KafkaClient {
  ${login_module}
  username="$KAFKA_CLIENT_USER"
  password="$client_password";
};
EOF

    echo "[sasl] write jaas config to /opt/bitnami/kafka/config/kafka_jaas.conf"
}

build_encode_password() {
    local password="${1}"
    echo -n "${password}" | md5sum | awk '{print $1}'
}

build_if_build_in_enabled() {
    if [ "$(is_sasl_build_in_enabled)" == "false" ]; then
        return 0
    fi

    if [ ! -d "/shared-tools/sasl" ]; then
        return 1
    fi
    if [ ! -f "/shared-tools/sasl/get-sasl-jar.sh" ]; then
        return 1
    fi
    if [ -z "${KB_CLUSTER_VERSION}" ]; then
        return 1
    fi

    local jar_path=$(/shared-tools/sasl/get-sasl-jar.sh ${KB_CLUSTER_VERSION} ${kafka_libs_path})
    if [ -z "${jar_path}" ]; then
        echo "no custom jar found. maybe build-in sasl not support for ${KB_CLUSTER_VERSION}"
        return 1
    fi

    export KAFKA_CFG_LISTENER_NAME_CLIENT_PLAIN_SASL_SERVER_CALLBACK_HANDLER_CLASS=${jar_path}
    echo "[sasl]export KAFKA_CFG_LISTENER_NAME_CLIENT_PLAIN_SASL_SERVER_CALLBACK_HANDLER_CLASS=${KAFKA_CFG_LISTENER_NAME_CLIENT_PLAIN_SASL_SERVER_CALLBACK_HANDLER_CLASS}"
    
    export KAFKA_CFG_LISTENER_NAME_INTERNAL_PLAIN_SASL_SERVER_CALLBACK_HANDLER_CLASS=${jar_path}
    echo "[sasl]export KAFKA_CFG_LISTENER_NAME_INTERNAL_PLAIN_SASL_SERVER_CALLBACK_HANDLER_CLASS=${KAFKA_CFG_LISTENER_NAME_INTERNAL_PLAIN_SASL_SERVER_CALLBACK_HANDLER_CLASS}"
}

get_client_default_mechanism() {
    isZkOrNot="$1"
    if [[ "$(is_sasl_enabled)" == "false" ]]; then
        echo ""
        return 0
    fi
    if [[ -n "$KB_KAFKA_SASL_MECHANISMS" ]]; then
        if [[ "$KB_KAFKA_SASL_MECHANISMS" == *,* ]]; then
            echo "${KB_KAFKA_SASL_MECHANISMS%%,*}"
        else
            echo "$KB_KAFKA_SASL_MECHANISMS"
        fi
        return 0
    fi
    if [[ "${isZkOrNot}" == "true" ]] && [[ "${KB_KAFKA_ENABLE_SASL_SCRAM}" == "true" ]]; then
        echo "SCRAM-SHA-512"
        return 0
    fi
    echo "PLAIN"
}