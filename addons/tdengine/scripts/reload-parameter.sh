#!/bin/bash
paramName="${1:?missing param name}"
paramValue="${2:?missing value}"
taos -p$TAOS_ROOT_PASSWORD -s "alter all dnodes '${paramName} ${paramValue}'"