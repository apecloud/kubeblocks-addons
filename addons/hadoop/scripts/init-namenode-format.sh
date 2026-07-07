#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR

POD_NAME="${POD_NAME:-$(hostname)}"
if [[ "$POD_NAME" != *"-0" ]] && [[ "$(hostname)" != *"-0" ]]; then
  echo "Only namenode ordinal 0 formats; this pod is $(hostname), skipping format"
  exit 0
fi

SLEEP_TIME=$((RANDOM % 120))
echo "Sleeping ${SLEEP_TIME}s to reduce race risk between NN-0 and NN-1 bootstrap..."
sleep "$SLEEP_TIME"

NAME_DIRS=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey dfs.namenode.name.dir 2>/dev/null || echo "")
NN_DIR="${NAME_DIRS%%,*}"
NN_DIR="${NN_DIR#file://}"
NN_CURRENT_DIR="${NN_DIR}/current"

if [[ -d "$NN_CURRENT_DIR" ]] && find "$NN_CURRENT_DIR" -maxdepth 1 -type f -name 'fsimage_*' ! -name '*.md5' 2>/dev/null | grep -q .; then
  echo "Valid fsimage already exists, skipping format"
  exit 0
fi

NAMESERVICES=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey dfs.nameservices 2>/dev/null || echo "")
if [[ -z "$NAMESERVICES" ]]; then
  echo "No dfs.nameservices configured (standalone mode), using default format"
  echo "N" | "${HADOOP_HOME}/bin/hdfs" namenode -format || true
else
  echo "Formatting NameNode for nameservice ${NAMESERVICES}"
  echo "N" | "${HADOOP_HOME}/bin/hdfs" namenode -format "$NAMESERVICES" || true
fi
