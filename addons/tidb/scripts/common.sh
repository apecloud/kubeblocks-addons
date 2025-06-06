#!/bin/bash

write_component_tls_env_to_file() {
    if [[ $KB_ENABLE_TLS_BETWEEN_COMPONENTS != "true" ]]; then
        return
    fi
    mkdir -p /etc/pki/cluster-tls/
    echo "$KB_TLS_BETWEEN_COMPONENTS_CA" > /etc/pki/cluster-tls/ca.pem
    echo "$KB_TLS_BETWEEN_COMPONENTS_CERT" > /etc/pki/cluster-tls/cert.pem
    echo "$KB_TLS_BETWEEN_COMPONENTS_KEY" > /etc/pki/cluster-tls/key.pem
}
