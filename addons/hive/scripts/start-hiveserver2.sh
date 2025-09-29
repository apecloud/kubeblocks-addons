#!/bin/bash

# shellcheck disable=SC1091

set -o errexit
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

cp /hive/base-conf/hive-site.xml $HIVE_CONF_DIR/hive-site.xml
cp /hive/base-conf/hive-log4j2.properties $HIVE_CONF_DIR/hive-log4j2.properties

bind_host="0.0.0.0"
if [[ -n "${LB_ADVERTISED_HOST}" ]]; then
   for lb_composed_name in $(echo "$LB_ADVERTISED_HOST" | tr ',' '\n' ); do
     svc_name=${lb_composed_name%:*}
     pod_name=$(echo ${svc_name} | sed 's/lb-advertised-//')
      if [[ "${pod_name}" == "$CURRENT_POD" ]]; then
        bind_host=${lb_composed_name#*:}
        break
      fi
   done
   info "LB_ADVERTISED_HOST is set, bind hots to ${bind_host}"
fi

sed -i "/<\/configuration>/i \
    <property>\\
        <name>hive.server2.thrift.bind.host</name>\\
        <value>${bind_host}</value>\\
    </property>" $HIVE_CONF_DIR/hive-site.xml


# TODO: 支持添加用户名密码，从secret里拿
password_md5=$(echo -n "$ADMIN_PASSWORD" | md5sum | awk '{print $1}')
echo "${ADMIN_USER},${password_md5}" > /hive/metadata/hive-server2-users.conf

START_COMMAND=("${HIVE_HOME_DIR}/bin/hive" "--service" "hiveserver2")

info "** Starting HiveServer2 **"
if am_i_root; then
    exec_as_user "$HIVE_DAEMON_USER" "${START_COMMAND[@]}"
else
    exec "${START_COMMAND[@]}"
fi