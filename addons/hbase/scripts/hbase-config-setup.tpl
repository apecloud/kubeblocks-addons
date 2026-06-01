#!/bin/bash
set -ex

declare -g primary
declare -g primary_port
declare -g default_initialize_pod_ordinal
declare -g headless_postfix="headless"

extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

get_minimum_initialize_pod_ordinal() {
  if [ -z "$KB_POD_LIST" ]; then
    echo "KB_POD_LIST is empty, use default initialize pod_ordinal:0 as primary node."
    default_initialize_pod_ordinal=0
    return
  fi

  # parse minimum ordinal from env $KB_POD_LIST, the value format is "pod1,pod2,..."
  IFS=',' read -ra pod_list <<< "$KB_POD_LIST"
  for pod in "${pod_list[@]}"; do
    if [ -z "$default_initialize_pod_ordinal" ]; then
      default_initialize_pod_ordinal=$(extract_ordinal_from_object_name "$pod")
      continue
    fi
    pod_ordinal=$(extract_ordinal_from_object_name "$pod")
    if [ "$pod_ordinal" -lt "$default_initialize_pod_ordinal" ]; then
      default_initialize_pod_ordinal="$pod_ordinal"
    fi
  done
}

cluster_domain="${CLUSTER_DOMAIN:-cluster.local}"
kb_component_full="${KB_POD_NAME%-*}"
kb_pod_fqdn="$KB_POD_NAME.$kb_component_full-headless.$KB_NAMESPACE.svc.$cluster_domain"
hadoop_cluster_name="$HADOOP_CLUSTER_NAME"
sed -e "/<name>hbase.regionserver.hostname<\/name>/,/<\/property>/ {
    /<value>/ {
    s|<value>.*</value>|<value>${kb_pod_fqdn}</value>|
    }
}" /hbase/origconf/hbase-site.xml > /hbase/conf/hbase-site.xml

zk_quorum=$(grep -A1 'hbase.zookeeper.quorum' /hbase/conf/hbase-site.xml | tail -1 | sed 's/.*<value>\(.*\)<\/value>.*/\1/')
zk_quorum_fqdn="${zk_quorum}.${KB_NAMESPACE}.svc.${cluster_domain}"
sed -i "s|<value>${zk_quorum}</value>|<value>${zk_quorum_fqdn}</value>|" /hbase/conf/hbase-site.xml

cp /hbase/conf/hbase-site.xml /tmp/hbase-site.xml.tmp
sed -e "s/ENV_HADOOP_CLUSTER_NAME/${hadoop_cluster_name}/g" \
    -e "s|ENV_HBASE_ROOT_DIR|${HBASE_ROOT_DIR:-hbase}|g" \
    -e "s|ENV_HBASE_ZK_PARENT|${HBASE_ZK_PARENT:-/hbase}|g" \
    /tmp/hbase-site.xml.tmp > /hbase/conf/hbase-site.xml

cp /hbase/origconf/log4j.properties /hbase/conf/log4j.properties
