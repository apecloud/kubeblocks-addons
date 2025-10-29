#!/usr/bin/env bash
. /opt/scripts/libs/libos.sh

HOSTNAME=$(hostname)
if [ -z "$DATANODE_DATA_HOST_PORT" ]; then
   HOSTNAME="${HOSTNAME}.${COMPONENT_NAME}-headless.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
fi
# 1. get excludeHosts from cm
configMapName=${CLUSTER_NAME}-namenode-hosts
excludeHosts=$(kubectl get cm "${configMapName}" -n ${CLUSTER_NAMESPACE} -o jsonpath='{.data.hosts.exclude}')
if [ $? -ne 0 ]; then
    echo "Failed to get exclude hosts config map: ${excludeHosts}"
    exit 1
fi

if echo "$excludeHosts" | grep -q "${HOSTNAME}"; then
    echo "This datanode (${HOSTNAME}) is already in the exclude list."
else
  # 2. add this host to excludeHosts
  if [ -z "$excludeHosts" ]; then
      excludeHosts="${HOSTNAME}"
  else
      excludeHosts="${excludeHosts}\n${HOSTNAME}"
  fi
  kubectl patch configmap "$configMapName" -n "$CLUSTER_NAMESPACE" --type strategic -p "{\"data\":{\"hosts.exclude\":\"$excludeHosts\"}}"
  sleep 10
fi

get_decommission_status(){
  sub_cmd=$1
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

export HADOOP_LOG_DIR=/hadoop/logs
export HADOOP_CONF_DIR=/hadoop/conf
export PATH=$PATH:$HADOOP_HOME/bin
export PATH=$PATH:$HADOOP_HOME/sbin

run_as_user "hadoop" hdfs dfsadmin -refreshNodes
decommissionStatus=$(get_decommission_status)
if [[ -z "$decommissionStatus" || "$decommissionStatus" = "Decommissioned" ]]; then
   # 3. remove this host from excludeHosts when datanode is decommissioned
   excludeHosts=$(echo -e "$excludeHosts" | sed "/^${HOSTNAME}$/d" | sed '/^$/d')
   kubectl patch configmap "$configMapName" -n "$CLUSTER_NAMESPACE" --type strategic -p "{\"data\":{\"hosts.exclude\":\"$excludeHosts\"}}"
else
  echo "Datanode ${HOSTNAME} is not decommissioned. Current status: ${decommissionStatus}, retry again"
  exit 1
fi


