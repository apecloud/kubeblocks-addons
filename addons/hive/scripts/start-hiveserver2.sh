#!/bin/bash

# shellcheck disable=SC1091

set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace # Uncomment this line for debugging purposes

# Load libraries
. /opt/scripts/libs/libos.sh
. /opt/scripts/libs/liblog.sh
. /opt/scripts/libs/lib.sh

# Load JournalNode environment variables
. /opt/scripts/hive/env.sh

print_welcome_page
mkdir -p /hive/metadata
mkdir -p /hive/conf

cat > ${HOME}/.bashrc <<EOF
export HIVE_HOME_DIR=/opt/hive
export HIVE_CONF_DIR=/hive/conf
export HIVE_DATA_DIR=/hive/metadata
export PATH=$PATH:$HADOOP_HOME/sbin:$HADOOP_HOME/bin:$HIVE_HOME/bin:$HIVE_HOME/sbin
export HADOOP_CONF_DIR=/hadoop/conf
export HADOOP_LOG_DIR=/hadoop/logs
EOF


START_COMMAND=("${HIVE_HOME_DIR}/bin/hive" "--service" "hiveserver2")

info "** Starting HiveServer2 **"
if am_i_root; then
    exec_as_user "$HIVE_DAEMON_USER" "${START_COMMAND[@]}"
else
    exec "${START_COMMAND[@]}"
fi