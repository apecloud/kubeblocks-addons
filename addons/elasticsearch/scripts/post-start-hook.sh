#!/usr/bin/env bash

# Check if we are using IPv6
if [[ $POD_IP =~ .*:.* ]]; then
  LOOPBACK="[::1]"
else
  LOOPBACK=127.0.0.1
fi
if [ -n "${KB_TLS_CERT_FILE}" ]; then
    READINESS_PROBE_PROTOCOL=https
else
    READINESS_PROBE_PROTOCOL=http
fi
ENDPOINT="${READINESS_PROBE_PROTOCOL}://${LOOPBACK}:9200"
COMMON_OPTIONS="--connect-timeout 3 -k -u root:${ELASTIC_USER_PASSWORD}"

function wait_for_cluster_health() {
    while true; do
        result=$(curl ${COMMON_OPTIONS} -X GET "${ENDPOINT}/_cluster/health?pretty" | grep 'green')
        if [ $? == 0 ]; then
            echo "cluster is formed"
            break
        fi
        echo "waiting for cluster to be formed"
        sleep 1
    done
}

# TODO: it's better to do this in component postProvision lifecycle action
if grep '\- master\|master: true' config/elasticsearch.yml > /dev/null 2>&1; then
    if [ ! -f ${CLUSTER_FORMED_FILE} ]; then
        wait_for_cluster_health
        touch ${CLUSTER_FORMED_FILE}
    fi
fi

idx=${KB_POD_NAME##*-}
if [ $idx -ne 0 ]; then
    exit 0
fi

if [ -z "${KB_TLS_CERT_FILE}" ]; then
    echo "tls and authentication is disabled, skip account initialization"
    exit 0
fi

#version=$(curl --fail ${COMMON_OPTIONS} ${ENDPOINT}?pretty | grep '"number" :' | tr -d '":,' | awk '{print $2}')
#if [ $? != 0 ]; then
#    echo "Failed to get elasticsearch version number"
#    exit 1
#fi
#major_minor_version=${version%.*}

function add_local_user()
{
    username=$1
    password=$2
    result=$(bin/elasticsearch-users useradd ${username} -r superuser -p "${password}" 2>&1)
    if [ $? != 0 ]; then
        echo "${result}" | grep 'already exists'
        if [ $? != 0 ]; then
            echo "Failed to create user ${user}"
            exit 1
        fi
    fi
}

function reset_password()
{
    username=$1
    password=$2
    curl --fail ${COMMON_OPTIONS} -X POST "${ENDPOINT}/_security/user/${username}/_password?pretty" -H 'Content-Type: application/json' -d "{\"password\":\"${password}\"}"
}

function wait_for_cluster_health()
{
    while true; do
        result=$(curl ${COMMON_OPTIONS} -X GET "${ENDPOINT}/_cluster/health?pretty" | grep 'green')
        if [ $? != 0 ]; then
            sleep 1
            continue
        fi
        break
    done
}

# add a temporary superuser user to reset built-in elastic and kibana_system password
add_local_user root ${ELASTIC_USER_PASSWORD}

echo "wait for cluster ready"
wait_for_cluster_health

echo "reset elastic password"
reset_password elastic ${ELASTIC_USER_PASSWORD}
if [ $? != 0 ]; then
    exit 1
fi

users=$(curl --fail ${COMMON_OPTIONS} "${ENDPOINT}/_security/user?pretty=false")
if [ $? != 0 ]; then
    echo "Failed to get user list"
    exit 1
fi
kibana_user=kibana_system
# version little than 7.8 doesn't have a built-in user kibana_system, so we create it manually
# https://www.elastic.co/guide/en/elasticsearch/reference/7.7/built-in-users.html
echo "${users}" | grep "\"username\":\"${kibana_user}\""
if [ $? != 0 ]; then
    echo "create user ${kibana_user}"
    curl --fail ${COMMON_OPTIONS} -X POST "${ENDPOINT}/_security/user/${kibana_user}?pretty" -H 'Content-Type: application/json' -d "{\"password\":\"${KIBANA_SYSTEM_USER_PASSWORD}\",\"roles\":[\"kibana_system\"]}"
    if [ $? != 0 ]; then
        echo "Failed to create user ${kibana_user}"
        exit 1
    fi
else
    echo "reset ${kibana_user} password"
    reset_password ${kibana_user} ${KIBANA_SYSTEM_USER_PASSWORD}
    if [ $? != 0 ]; then
        exit 1
    fi
fi


# FIXME: share the ca.crt with kibana by using index, this is a workaround as KB doesn't support cluster level certificates now
# FIXME: should be removed after KB support cluster level certificates: https://github.com/apecloud/kubeblocks/issues/8278
index_name=kubeblocks_ca_crt
ca_crt=$(cat /usr/share/elasticsearch/config/ca.crt | base64 -w 0)
echo "fill elastic ca into index ${index_name}"
#{
#  "_index" : "kubeblocks_ca_crt",
#  "_id" : "1",
#  "_version" : 1,
#  "_seq_no" : 0,
#  "_primary_term" : 1,
#  "found" : true,
#  "_source" : {
#    "ca.crt" : "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURGekNDQWYrZ0F3SUJBZ0lRTzNaOXRpR3A0cGRESGRyK24xOExYVEFOQmdrcWhraUc5dzBCQVFzRkFEQVYKTVJNd0VRWURWUVFERXdwTGRXSmxRbXh2WTJ0ek1DQVhEVEkwTVRBeE5UQTRNVFF5TTFvWUR6SXhNalF3T1RJeApNRGd4TkRJeldqQVZNUk13RVFZRFZRUURFd3BMZFdKbFFteHZZMnR6TUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGCkFBT0NBUThBTUlJQkNnS0NBUUVBczBRMjJYVHc0MkMreGN4T01mU3BHbG9hTVYramxyRVlvUEF6YXRLLytYcnQKL0pGNWNjT1JsTy9WVmpHVzJxRnRNd3JKT1NPS0dQejJCRGhDZ00xR25xRFF1RFlTanpDL3RoZ2RCaFRMWGx0Zwo5TEl0czlGMGZpQUd6NnM2WHZSYnd2ZkJUd21idWdqaEcxK2ZWb1VFdkc2Wm1CdFdhZTh5VDBFbmNjeDVwaDlZCjN1d0VRSHpmdzBYaWpwVmJIK0F6eGpNUlFFN05aa1FHdWJ6ZGNhWEVaUDVGTDE2eWFkZmtERTAya2praENJVTQKdGFFclJQUzlCUG9TQnlpUlR3OEQ2a0tqdzlMY25yemZITjBBdVQrM3RIQUJNWEtZUEhReTRDNWlLdjliRlMzVQpYSjdnRzR5RElIdDAvc2JSemFnaHptajlWL1RDT2tPRUwrMkgwTFR2TVFJREFRQUJvMkV3WHpBT0JnTlZIUThCCkFmOEVCQU1DQXFRd0hRWURWUjBsQkJZd0ZBWUlLd1lCQlFVSEF3RUdDQ3NHQVFVRkJ3TUNNQThHQTFVZEV3RUIKL3dRRk1BTUJBZjh3SFFZRFZSME9CQllFRk0walZBTmV0ZGRtOXl4WGZnY0x1V3JhalVodk1BMEdDU3FHU0liMwpEUUVCQ3dVQUE0SUJBUUJsYVBaQ0VLUnNNQW15TDR2UDhEOGFydUY3NEdPRXdKclhWdE4zWWxJWTdpUURsNUNGCm96ZEhuSEE3ZjhxdlE0dklFNEVJcEloZW9DZURzc3Z0QnJwVnpEWXVaaE51VTl1cWVFdjNSRTREb3hES0RxamYKeU4xMnZ5U0JqVXhxR0FLNnNzLzRDTXVjei9KMWdDcXpqdzVRQXJFeng4STIraFljK0Z1RDBYWjVlZUNxVm1wWAoxQUUyQ2hQbS9BRXhQdnZKTk5pL2h1eWpyRUc2NjI0aFNPSzl1TnA1Zk1ibTJyQmR6SlhwWlMxRWVjNFBSYUVwClgxcjhISG9Lais4S2hpTWdCUndCMU9wM09kZVhwcGtZZjhhb2ZZbjV5MVFQMm1mbSt6VzZ3NTV3WFJTVm44aG0KT0ozUDVBRTFxUS9jRmJjSmp5bGJHM2huSWM0UkRBZ24yUldmCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
#  }
#}
curl ${COMMON_OPTIONS} -X POST -H "Content-Type: application/json" -d "{\"ca.crt\": \"${ca_crt}\"}" "${ENDPOINT}/${index_name}/_doc/1"
