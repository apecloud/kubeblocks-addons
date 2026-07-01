#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR

NAME_DIRS=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey dfs.namenode.name.dir 2>/dev/null || echo "")
if [[ -z "$NAME_DIRS" ]]; then
  echo "No dfs.namenode.name.dir configured, skipping bootstrapStandby"
  exit 0
fi

NN_DIR="${NAME_DIRS%%,*}"
NN_DIR="${NN_DIR#file://}"
NN_CURRENT_DIR="${NN_DIR}/current"

has_valid_fsimage() {
  [[ -d "$NN_CURRENT_DIR" ]] || return 1
  find "$NN_CURRENT_DIR" -maxdepth 1 -type f -name 'fsimage_*' ! -name '*.md5' 2>/dev/null | grep -q .
}

if has_valid_fsimage; then
  echo "Valid fsimage found at ${NN_CURRENT_DIR}, skipping bootstrapStandby"
  exit 0
fi

if [[ -d "$NN_CURRENT_DIR" ]]; then
  BACKUP_DIR="${NN_CURRENT_DIR}.incomplete.$(date +%s)"
  echo "Incomplete metadata found, moving ${NN_CURRENT_DIR} to ${BACKUP_DIR}"
  mv "$NN_CURRENT_DIR" "$BACKUP_DIR" || true
fi

echo "No valid fsimage, running bootstrapStandby with retries..."
for attempt in $(seq 1 30); do
  if "${HADOOP_HOME}/bin/hdfs" namenode -bootstrapStandby -nonInteractive; then
    echo "bootstrapStandby succeeded on attempt ${attempt}"
    exit 0
  fi
  echo "bootstrapStandby failed on attempt ${attempt}, retrying in 10s..."
  sleep 10
done

echo "bootstrapStandby failed after 30 attempts"
exit 1
