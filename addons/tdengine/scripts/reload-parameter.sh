#!/bin/bash
paramName="${1:?missing param name}"
paramValue="${2:?missing value}"
res=$(taos -p$TAOS_ROOT_PASSWORD -s "alter all dnodes '${paramName} ${paramValue}'")
if [[ "$res" == *"Query OK"* ]]; then
  exit 0
fi
exit 1