#!/bin/bash
set -e

declare -g primary
declare -g primary_port
declare -g default_initialize_pod_ordinal
declare -g headless_postfix="headless"

#kb_pod_fqdn="$POD_NAME.$CLUSTER_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.cluster.local"
#hadoop_cluster_name="$HADOOP_CLUSTER_NAME"
#sed -e "/<name>hbase.regionserver.hostname<\/name>/,/<\/property>/ {
#    /<value>/ {
#    s|<value>.*</value>|<value>${kb_pod_fqdn}</value>|
#    }
#}" /hbase/origconf/hbase-site.xml > /hbase/conf/hbase-site.xml

cp /hbase/origconf/hbase-site.xml /hbase/conf/hbase-site.xml
sed -i "s/ENV_HADOOP_CLUSTER_NAME/${HADOOP_CLUSTER_NAME}/g" /hbase/conf/hbase-site.xml

cp /hbase/origconf/log4j.properties /hbase/conf/log4j.properties
