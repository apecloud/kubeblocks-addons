#!/bin/bash

fe_role_probe()
{

    FE_HEADLESS_SERVICE="${CLUSTER_NAME}-${COMPONENT_NAME}-headless"
    SELF_FE_FQDN="${HOSTNAME}.${FE_HEADLESS_SERVICE}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
    
    probe_output=$(mysql -h "${SELF_FE_FQDN}" -P "${FE_QUERY_PORT}" -u "${DORIS_USER}" -e "SHOW FRONTENDS" 2>/dev/null || true)
    is_master_value=$(echo "${probe_output}" | grep -w "${SELF_FE_FQDN}" | awk '{print $9}' || true)

    if [[ "x${is_master_value}" == "x" ]]; then
        return 1
    fi

    if [[ "x${is_master_value}" == "xtrue" ]]; then
        echo "master"
        return 0
    fi

    if [[ "x${is_master_value}" == "xfalse" ]]; then
        echo "follower"
        return 0
    fi

}

fe_role_probe
