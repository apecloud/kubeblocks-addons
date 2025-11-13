#!/bin/bash
#
# Environment configuration for zookeeper

# The values for all environment variables will be set in the below order of precedence
# 1. Custom environment variables defined below after Bitnami defaults
# 2. Constants defined in this file (environment variables with no default), i.e. BITNAMI_ROOT_DIR
# 3. Environment variables overridden via external files using *_FILE variables (see below)
# 4. Environment variables set externally (i.e. current Bash context/Dockerfile/userdata)

# Load logging library
# shellcheck disable=SC1090,SC1091

function tail_logs() {
  while true; do
    sleep 1
    if [[ -f ${HBASE_LOG_DIR}/hbase-${HBASE_IDENT_STRING}-$1-`hostname`.log ]] ; then
      break
    fi
  done
  tail -F ${HBASE_LOG_DIR}/hbase-${HBASE_IDENT_STRING}-$1-`hostname`.log
}


# Paths
export HBASE_HOME_DIR="/opt/hbase"
export HBASE_HOME="${HBASE_HOME:-${HBASE_HOME_DIR}}"
export HBASE_DATA_DIR="/hbase"
export MODULE="${MODULE:-master}"

# ENV Path
export HBASE_CONF_DIR="${HBASE_DATA_DIR}/conf"
export HBASE_MASTER_DIR="${HBASE_CONF_DIR}/backup-masters"
export HBASE_REGION_SERVERS_DIR="${HBASE_CONF_DIR}/regionservers"
export PATH=$PATH:$HBASE_HOME/bin

# log4j config
export HBASE_LOG_DIR="${HBASE_DATA_DIR}/logs"
export HBASE_ROOT_LOGGER="INFO,console,DRFA"
export HBASE_IDENT_STRING=hbase
export HBASE_LOG4J_PROPS="${HBASE_CONF_DIR}/conf/log4j.properties"
HBASE_OPTS=${HBASE_OPTS:-""}
export HBASE_OPTS="$HBASE_OPTS -Dlog4j.configuration=file://${HBASE_CONF_DIR}/log4j.properties"

# Hadoop ENV
export HADOOP_DATA_DIR="/hadoop"
export HADOOP_HOME_DIR="/opt/hadoop"
export HADOOP_HOME="${HADOOP_HOME:-${HADOOP_HOME_DIR}}"
export HADOOP_CONF_DIR="${HADOOP_DATA_DIR}/conf"

# System users (when running with a privileged user)
export HBASE_DAEMON_USER="hadoop"
export HBASE_DAEMON_GROUP="hadoop"
export HBASE_NO_REDIRECT_LOG=true

#
export DEBUG_MODEL="${DEBUG_MODEL:-true}"
export HBASE_MANAGES_ZK=false

cat > ${HOME}/.bashrc <<EOF
export PATH=$PATH:$HADOOP_HOME/sbin:$HADOOP_HOME/bin:$HBASE_HOME/bin
export HADOOP_CONF_DIR=/hadoop/conf
export HADOOP_LOG_DIR=/hadoop/logs
export HBASE_CONF_DIR="${HBASE_DATA_DIR}/conf"
export HBASE_LOG_DIR="${HBASE_DATA_DIR}/logs"
EOF

print_welcome_page

if [[ $DEBUG_MODEL == true ]]; then
  info ************** env-start **************
  env
  info ************** env-end **************
fi

bash /hbase/scripts/hbase-config-setup.sh