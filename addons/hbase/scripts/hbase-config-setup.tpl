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
  if [ -z "$HBASE_MASTER_POD_LIST" ]; then
    echo "HBASE_MASTER_POD_LIST is empty, use default initialize pod_ordinal:0 as primary node."
    default_initialize_pod_ordinal=0
    return
  fi

  # parse minimum ordinal from env $HBASE_MASTER_POD_LIST, the value format is "pod1,pod2,..."
  IFS=',' read -ra pod_list <<< "$HBASE_MASTER_POD_LIST"
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

kb_pod_fqdn="$POD_NAME.$CLUSTER_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.cluster.local"
hadoop_cluster_name="$HADOOP_CLUSTER_NAME"
sed -e "/<name>hbase.regionserver.hostname<\/name>/,/<\/property>/ {
    /<value>/ {
    s|<value>.*</value>|<value>${kb_pod_fqdn}</value>|
    }
}" /hbase/origconf/hbase-site.xml > /hbase/conf/hbase-site.xml

cp /hbase/conf/hbase-site.xml /tmp/hbase-site.xml.tmp
sed -e "s/ENV_HADOOP_CLUSTER_NAME/${hadoop_cluster_name}/g" /tmp/hbase-site.xml.tmp > /hbase/conf/hbase-site.xml

cp /hbase/origconf/log4j.properties /hbase/conf/log4j.properties
