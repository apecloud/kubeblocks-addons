#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch an error in command pipes. e.g. mysqldump fails (but gzip succeeds)
# in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging.
set -o xtrace

_PORTS="${HDFS_JOURNALNODE_HTTP_PORT:-8480}"
_URL_PATH="jmx?qry=Hadoop:service=JournalNode,name=JournalNodeInfo"
for _PORT in $_PORTS; do
  _RESPONSE="$(curl -fsS --max-time 2 "http://localhost:${_PORT}/${_URL_PATH}")"
  if grep -Eq '"HostAndPort"[[:space:]]*:[[:space:]]*"[^"]+"' <<< "${_RESPONSE}"; then
    exit 0
  fi
done
exit 1
