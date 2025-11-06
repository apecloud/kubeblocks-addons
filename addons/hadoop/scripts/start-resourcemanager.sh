#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace # Uncomment this line for debugging purposes

# Load libraries
. /opt/scripts/libs/liblog.sh
. /opt/scripts/libs/lib.sh
. /kubeblocks/scripts/common.sh
mkdir -p /hadoop/tmp
mkdir -p /hadoop/yarn/resourcemanager

info "** Starting Resource Manager **"
if [[ "$ENABLE_JMX_EXPORTER" == true ]]; then
  export YARN_RESOURCEMANAGER_OPTS="-javaagent:/hadoop/jmx_prometheus_javaagent.jar=${JMX_EXPORTER_PORT}:/hadoop/conf/jmx-exporter.yaml"
fi
exec ${HADOOP_HOME}/bin/yarn --config ${HADOOP_CONF_DIR} resourcemanager
