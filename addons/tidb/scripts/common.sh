#!/bin/bash

set_component_tls_variables() {
    scheme="http"
    pdAddr="http://127.0.0.1:2379"
    extraArg=""
    if [[ $KB_ENABLE_TLS_BETWEEN_COMPONENTS == "true" ]]; then
        scheme="https"
        pdAddr="https://127.0.0.1:2379"
        extraArg+="--cacert /etc/pki/cluster-tls/ca.pem --cert /etc/pki/cluster-tls/cert.pem --key /etc/pki/cluster-tls/key.pem"
    fi
}
