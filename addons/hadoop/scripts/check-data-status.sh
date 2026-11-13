#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

_PORTS="${HDFS_DATANODE_HTTP_PORT:-9864}"
_URL_PATH="jmx?qry=Hadoop:service=DataNode,name=DataNodeInfo"
for _PORT in $_PORTS; do
  _RESPONSE="$(curl -fsS --max-time 2 "http://localhost:${_PORT}/${_URL_PATH}")"
  if grep -q '"ClusterId"[[:space:]]*:[[:space:]]*"[^"]\+"' <<< "${_RESPONSE}"; then
    exit 0
  fi
done
exit 1
