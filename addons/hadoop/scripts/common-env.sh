
export HADOOP_DATA_DIR="/hadoop"
# Paths
export HADOOP_HOME_DIR="/opt/hadoop-3.3.4"
export HADOOP_HOME="${HADOOP_HOME:-${HADOOP_HOME_DIR}}"

export HADOOP_CONF_DIR="${HADOOP_DATA_DIR}/conf"
export HADOOP_LOG_DIR="${HADOOP_DATA_DIR}/logs"

export PATH=$PATH:$HADOOP_HOME/bin
export PATH=$PATH:$HADOOP_HOME/sbin

# System users (when running with a privileged user)
export HADOOP_DAEMON_USER="hadoop"
export HADOOP_DAEMON_GROUP="hadoop"

export DEBUG_MODEL="${DEBUG_MODEL:-true}"
# Hadoop tmp dir for nodemanagers
export HADOOP_TMP_DIR="${HADOOP_TMP_DIR:-${HADOOP_DATA_DIR}/tmp}"