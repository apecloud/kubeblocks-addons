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


MYSQL_PASSWORD=$COMPONENT_MYSQL_PASSWORD
if [ -z $COMPONENT_MYSQL_PASSWORD ]; then
   MYSQL_PASSWORD=${METADB_MYSQL_PASSWORD}
fi

if [ -f /hive/metadata/hive.jceks ]; then
  info "hive.jceks already exists, skip creating"
else
  info "creating hive.jceks"
  hadoop credential create javax.jdo.option.ConnectionPassword -provider jceks://file/hive/metadata/hive.jceks -value $MYSQL_PASSWORD
fi

if [[ $DEBUG_MODEL == true ]]; then
  info ************** env-start **************
  env
  info ************** env-end **************
  info ************** conf-start **************
  cat /hive/hive-site.xml
  info ************** conf-start **************
fi

info "** Starting HMS setup **"
/opt/scripts/hive/post-start.sh
info "** HMS setup finished! **"

START_COMMAND=("${HIVE_HOME_DIR}/bin/hive" "--service" "metastore")

info "** Starting HiveMetaStore **"
if am_i_root; then
    exec_as_user "$HIVE_DAEMON_USER" "${START_COMMAND[@]}"
else
    exec "${START_COMMAND[@]}"
fi