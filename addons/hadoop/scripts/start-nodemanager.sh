set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace # Uncomment this line for debugging purposes

# Load libraries
. /opt/scripts/libs/liblog.sh
. /opt/scripts/libs/lib.sh
. /kubeblocks/scripts/common-env.sh
mkdir -p /hadoop/tmp

info "** Starting Node Manager **"
# sleep 10000
exec ${HADOOP_HOME}/bin/yarn --config ${HADOOP_CONF_DIR} nodemanager