# https://www.elastic.co/guide/en/elasticsearch/reference/7.7/add-elasticsearch-nodes.html
set -x
# setup basic auth if credentials are available
if [ -n "${ELASTIC_USER_PASSWORD}" ]; then
  BASIC_AUTH="-u elastic:${ELASTIC_USER_PASSWORD}"
else
  BASIC_AUTH=''
fi
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
endpoint="${READINESS_PROBE_PROTOCOL}://${LOOPBACK}:9200"
common_options="-k --fail --max-time 3 --retry 3 ${BASIC_AUTH}"
echo "removing node $KB_LEAVE_MEMBER_POD_NAME"
version=`curl ${common_options} -s ${endpoint} | jq -r .version.number`
if [ $? != 0 ]; then
  echo "failed to get es version"
  exit 1
fi
version=${version%.*}
if awk "BEGIN {exit !($version < 7.8)}"; then
  url=${endpoint}/_cluster/voting_config_exclusions/$KB_LEAVE_MEMBER_POD_NAME
else
  url=${endpoint}/_cluster/voting_config_exclusions?node_names=$KB_LEAVE_MEMBER_POD_NAME
fi
curl ${common_options} -v -X POST $url
if [ $? != 0 ]; then
  echo "failed to add node $KB_LEAVE_MEMBER_POD_NAME to voting config exclusion list"
  echo "may be the voting config exclusion list is full, try to remove it first"
  curl ${common_options} -X DELETE "${endpoint}/_cluster/voting_config_exclusions?pretty&wait_for_removal=false"
  exit 1
else
  echo "successfully added node $KB_LEAVE_MEMBER_POD_NAME to voting config exclusion list"
fi