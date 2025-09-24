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
. /opt/scripts/hive/3.1.3/metastore/env.sh

print_welcome_page

cp /hive/base-conf/hive-site.xml $HIVE_CONF_DIR/hive-site.xml
MYSQL_PASSWORD=$COMPONENT_MYSQL_PASSWORD
if [ -z $COMPONENT_MYSQL_PASSWORD ]; then
   MYSQL_PASSWORD=${METADB_MYSQL_PASSWORD}
fi
sed -i "/<\/configuration>/i \
    <property>\
        <name>javax.jdo.option.ConnectionPassword</name>\
        <value>${MYSQL_PASSWORD}</value>\
    </property>" $HIVE_CONF_DIR/hive-site.xml

if [[ $DEBUG_MODEL == true ]]; then
  info ************** env-start **************
  env
  info ************** env-end **************
  info ************** conf-start **************
  cat /hive/base-conf/hive-site.xml
  info ************** conf-start **************
fi

info "** Starting HMS setup **"
/opt/scripts/hive/3.1.3/metastore/post-start.sh
info "** HMS setup finished! **"

START_COMMAND=("${HIVE_HOME_DIR}/bin/hive" "--service" "metastore")

info "** Starting HiveMetaStore **"
if am_i_root; then
    exec_as_user "$HIVE_DAEMON_USER" "${START_COMMAND[@]}"
else
    exec "${START_COMMAND[@]}"
fi