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

# Load JournalNode environment variables
. /kubeblocks/scripts/common.sh

print_welcome_page

if [[ $DEBUG_MODEL == true ]]; then
  info ************** env-start **************
  env
  info ************** env-end **************
fi

START_COMMAND=("${HADOOP_HOME}/bin/hdfs" "datanode" "$@")

info "** Starting DataNode **"
if am_i_root; then
    exec_as_user "$HADOOP_DAEMON_USER" "${START_COMMAND[@]}"
else
    exec "${START_COMMAND[@]}"
fi