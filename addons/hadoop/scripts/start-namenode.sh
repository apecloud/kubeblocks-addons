#!/bin/bash

# shellcheck disable=SC1091

set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace # Uncomment this line for debugging purposes

# Load libraries
. /opt/scripts/libs/liblog.sh
. /opt/scripts/libs/lib.sh
. /opt/scripts/libs/libos.sh
. /opt/scripts/libs/libfs.sh

# Load NameNode environment variables
. /kubeblocks/scripts/common.sh

namenode_initialize() {
  info "** Initialize NameNode **"
  CURRENT_INDEX=$(echo $CURRENT_POD | awk -F '-' '{print $NF}')
  _METADATA_DIR=${DFS_NAME_NODE_NAME_DIR}/current

  if [[ "$CURRENT_INDEX" -eq 0 ]]; then
      if [[ ! -d $_METADATA_DIR ]]; then
        info "** NameNode MetaData not exists process format hdfs **"
        hdfs namenode -format -nonInteractive hdfs-k8s ||
            (rm -rf $_METADATA_DIR; exit 1)
      fi

      _ZKFC_FORMATTED=${_METADATA_DIR}/.hdfs-k8s-zkfc-formatted
      if [[ ! -f $_ZKFC_FORMATTED ]]; then
        info "** ZKFC not exists format ZKFC **"
        #gosu "$HADOOP_DAEMON_USER" hdfs zkfc -formatZK -nonInteractive
        if hdfs zkfc -formatZK -nonInteractive; then
            info "ZK  FC format executed successfully."
            touch $_ZKFC_FORMATTED
        else
            error "ZKFC format failed."
            exit 1
        fi
      fi
  else
    if [[ ! -d $_METADATA_DIR ]]; then
        info "** NameNode Running bootstrapStandby **"
      hdfs namenode -bootstrapStandby -nonInteractive ||
          (rm -rf $_METADATA_DIR; exit 1)
    fi
  fi
}

print_welcome_page
mkdir -p /hadoop/dfs/journal

info "** Starting NameNode setup **"
# Ensure NameNode is initialized
namenode_initialize
info "** NameNode setup finished! **"

START_COMMAND=("${HADOOP_HOME}/bin/hdfs" "namenode" "$@")

info "** Starting NameNode **"
if am_i_root; then
  info "** Starting zkfc **"
  exec_as_user "$HADOOP_DAEMON_USER" hadoop-daemon.sh start zkfc

  info "** Starting namenode **"
  exec_as_user "$HADOOP_DAEMON_USER" "${START_COMMAND[@]}"
  #exec gosu "$HADOOP_DAEMON_USER" hdfs --config $HADOOP_CONF_DIR namenode
else
  info "** Starting zkfc **"
  hadoop-daemon.sh start zkfc

  info "** Starting namenode **"
  exec "${START_COMMAND[@]}"
fi