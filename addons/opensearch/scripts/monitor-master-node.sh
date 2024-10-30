#!/usr/bin/env bash
set -eo pipefail

http () {
    local path="${1}"
    if [ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ]; then
        BASIC_AUTH="-u ${USERNAME}:${PASSWORD}"
    else
        BASIC_AUTH=''
    fi
    curl -XGET -s -k --fail ${BASIC_AUTH} https://$(CLUSTER_NAME)-$(OPENSEARCH_COMPONENT_SHORT_NAME)-headless:9200:${path}
}

cleanup () {
    while true ; do
    local master="$(http "/_cat/master?h=node" || echo "")"
    if [[ $master == "$(CLUSTER_NAME)-$(OPENSEARCH_COMPONENT_SHORT_NAME)"* && $master != "${NODE_NAME}" ]]; then
        echo "This node is not master."
        break
    fi
    echo "This node is still master, waiting gracefully for it to step down"
    sleep 1
    done

    exit 0
}

trap cleanup SIGTERM

sleep infinity &
wait $!