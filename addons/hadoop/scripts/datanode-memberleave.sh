#!/usr/bin/env bash
. /opt/scripts/libs/libos.sh
export HADOOP_LOG_DIR=/hadoop/logs
export HADOOP_CONF_DIR=/hadoop/conf
export PATH=$PATH:$HADOOP_HOME/bin
export PATH=$PATH:$HADOOP_HOME/sbin

get_hostname(){
  local host_info=$1
  hdfs dfsadmin -report -live | grep -A 5 "$host_info" | grep "^Hostname:" | awk '{print $2}'
}

HOSTNAME=$(hostname)
if [ -z "$DATANODE_DATA_HOST_PORT" ]; then
   HOSTNAME="${KB_LEAVE_MEMBER_POD_FQDN}"
else
  HOST_IP=$(/hadoop/kubectl get pod "${KB_LEAVE_MEMBER_POD_NAME}" -n "${CLUSTER_NAMESPACE}" -o jsonpath='{.status.hostIP}')
  HOST_INFO="${HOST_IP}:${DATANODE_DATA_HOST_PORT}"
  HOSTNAME=$(get_hostname "$HOST_INFO")
  if [ -z "$HOSTNAME" ]; then
    echo "No hostname found for host info: ${HOST_INFO}, exit 0"
    exit 0
  fi
fi
# 1. get excludeHosts from cm
configMapName=${CLUSTER_NAME}-namenode-hosts
excludeHosts=$(/hadoop/kubectl get cm "${configMapName}" -n ${CLUSTER_NAMESPACE} -o jsonpath='{.data.hosts\.exclude}')
if [ $? -ne 0 ]; then
    echo "Failed to get exclude hosts config map: ${excludeHosts}" >&2
    exit 1
fi
echo "Current excludeHosts: $excludeHosts, HOSTNAME: $HOSTNAME"
if echo "$excludeHosts" | grep -q "${HOSTNAME}"; then
    echo "This datanode (${HOSTNAME}) is already in the exclude list."
    sleep 5
else
  # 2. add this host to excludeHosts
  if [ -z "$excludeHosts" ]; then
      excludeHosts="${HOSTNAME}"
  else
      excludeHosts="${HOSTNAME}
${excludeHosts}"
  fi
  echo "
data:
  hosts.exclude: |-
$(echo "$excludeHosts" | sed 's/^/    /')
" > /tmp/excludeHosts.yaml
  /hadoop/kubectl patch configmap $configMapName --type strategic --patch-file /tmp/excludeHosts.yaml
  rm /tmp/excludeHosts.yaml
  sleep 15
fi

get_decommission_status(){
  hdfs dfsadmin -report -live | awk -v host="$HOSTNAME" '
  $1 == "Hostname:" && $2 == host {
      hostname_match = 1
  }
  hostname_match && $1 == "Decommission" && $2 == "Status" {
      gsub(/^[ \t]+/, "", $4)  # 去除可能的前导空格
      print $4
      exit
  }
  /^Name:/ {
      hostname_match = 0  # 新节点开始，重置匹配状态
  }
  '
}

hdfs dfsadmin -refreshNodes
decommissionStatus=$(get_decommission_status)
if [[ -z "$decommissionStatus" || "$decommissionStatus" = "Decommissioned" ]]; then
   echo "DecommissionStatus: $decommissionStatus"
else
  echo "Datanode ${HOSTNAME} is not decommissioned. Current status: ${decommissionStatus}, retry again" >&2
  exit 1
fi


