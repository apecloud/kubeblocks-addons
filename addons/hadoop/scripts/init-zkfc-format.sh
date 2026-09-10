#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR

echo "Formatting ZKFC (creating HA znode in ZooKeeper)..."
if output=$(echo "N" | "${HADOOP_HOME}/bin/hdfs" zkfc -formatZK 2>&1); then
  printf '%s\n' "${output}"
else
  printf '%s\n' "${output}" >&2
  # ponytail: matching the known "already exists" case by message keeps the script short; upgrade to a direct znode existence check if Hadoop changes this text.
  if grep -Eqi 'already exists|node .* exists' <<< "${output}"; then
    echo "ZKFC znode already exists, treating format as complete"
  else
    exit 1
  fi
fi
echo "ZKFC format completed"
