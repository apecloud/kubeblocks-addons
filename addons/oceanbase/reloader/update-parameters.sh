#!/bin/sh
set -ex

OB_SERVICE_PORT=2881
OB_CLI="/kb_tools/obtools"

paramName="${1:?missing config}"
paramValue="${2:?missing value}"

#The effective scope of the parameter modification. Valid values:
#  * MEMORY: specifies to modify only parameters in the memory, and the modification takes effect immediately. The modification becomes invalid after the server is restarted. However, no parameter supports this mode.
#  * SPFILE: specifies to modify only parameters in the configuration table. The modification takes effect after the server is restarted.
#  * BOTH: specifies to modify parameters in both the configuration table and the memory. The modification takes effect immediately and remains effective after the server is restarted.
$OB_CLI --host 127.0.0.1 -uroot -P ${OB_SERVICE_PORT} param-update --set "${paramName}=${paramValue}" --scope BOTH
