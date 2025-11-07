#!/bin/bash

# shellcheck disable=SC1091

set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace # Uncomment this line for debugging purposes

# Load libraries
. /opt/scripts/libs/liblog.sh
. /opt/scripts/libs/lib.sh
. /opt/scripts/libs/libnet.sh
. /opt/scripts/libs/libos.sh

# Load NameNode environment variables
. /kubeblocks/scripts/common.sh

print_welcome_page

if [[ $DEBUG_MODEL == true ]]; then
  info ************** env-start **************
  env
  info ************** env-end **************
fi

if [[ $WAIT_ZK_TO_READY == true ]]; then
  ZOOKEEPER_HOSTNAME=$(echo "$ZOOKEEPER_ENDPOINTS" | cut -d':' -f1)
  echo "Waiting zookeeper to start..."
  wait_for_dns_lookup "$ZOOKEEPER_HOSTNAME" 30 5
fi
echo "Wait zookeeper started successfully."

if [[ "$ENABLE_JMX_EXPORTER" == true ]]; then
  export HDFS_JOURNALNODE_OPTS="-javaagent:/hadoop/jmx_prometheus_javaagent.jar=${JMX_EXPORTER_PORT}:/hadoop/conf/jmx-exporter.yaml"
fi

START_COMMAND=("${HADOOP_HOME}/bin/hdfs" "journalnode" "$@")

info "** Starting JournalNode **"
if am_i_root; then
    exec_as_user "$HADOOP_DAEMON_USER" "${START_COMMAND[@]}"
else
    exec "${START_COMMAND[@]}"
fi