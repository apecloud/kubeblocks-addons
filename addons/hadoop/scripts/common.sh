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
. /opt/scripts/libs/liblog.sh
. /opt/scripts/libs/lib.sh
. /opt/scripts/libs/libos.sh
. /opt/scripts/libs/libfs.sh

export HADOOP_DATA_DIR="/hadoop"
export HADOOP_VOLUME_DIR="/hadoop/dfs"
# Logging configuration
# export MODULE="${MODULE:-namenode}"
# Paths
export HADOOP_HOME_DIR="/opt/hadoop"
export HADOOP_HOME="${HADOOP_HOME:-${HADOOP_HOME_DIR}}"

export DFS_NAME_NODE_NAME_DIR="${DFS_NAME_NODE_NAME_DIR:-${HADOOP_DATA_DIR}/dfs/metadata}"
export DFS_JOURNAL_NODE_EDITS_DIR="${DFS_JOURNAL_NODE_EDITS_DIR:-${HADOOP_DATA_DIR}/dfs/journal}"
export HADOOP_CONF_DIR="${HADOOP_DATA_DIR}/conf"
export HADOOP_LOG_DIR="${HADOOP_DATA_DIR}/logs"

export PATH=$PATH:$HADOOP_HOME/bin
export PATH=$PATH:$HADOOP_HOME/sbin

# System users (when running with a privileged user)
export HADOOP_DAEMON_USER="hadoop"
export HADOOP_DAEMON_GROUP="hadoop"

export DEBUG_MODEL="${DEBUG_MODEL:-true}"
export WAIT_ZK_TO_READY="${WAIT_ZK_TO_READY:-true}"

if [[ $DEBUG_MODEL == true ]]; then
  info ************** env-start **************
  env
  info ************** env-end **************
fi

# Ensure JournalNode environment variables are valid
# jnamenode_validate
# Ensure JournalNode user and group exist when running as 'root'
if am_i_root; then
    ensure_user_exists "$HADOOP_DAEMON_USER" --uid 10000 --group "$HADOOP_DAEMON_GROUP"
    HADOOP_OWNERSHIP_USER="$HADOOP_DAEMON_USER"
else
    HADOOP_OWNERSHIP_USER=""
fi
# Ensure directories used by JournalNode exist and have proper ownership and permissions
for dir in "$HADOOP_DATA_DIR" "$HADOOP_VOLUME_DIR" "$DFS_NAME_NODE_NAME_DIR" "$DFS_JOURNAL_NODE_EDITS_DIR" "$HADOOP_CONF_DIR" "$HADOOP_LOG_DIR"; do
    ensure_dir_exists "$dir" "$HADOOP_OWNERSHIP_USER"
done

cat > ${HOME}/.bashrc <<EOF
export PATH=$PATH:$HADOOP_HOME/sbin:$HADOOP_HOME/bin
export HADOOP_CONF_DIR=/hadoop/conf
export HADOOP_LOG_DIR=/hadoop/logs
EOF