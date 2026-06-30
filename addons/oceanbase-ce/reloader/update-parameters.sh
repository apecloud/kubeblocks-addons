#!/bin/sh
set -ex

if [ -x "/kb_reload_tools/obtools" ]; then
  OB_CLI="/kb_reload_tools/obtools"
else
  OB_CLI="/kb_tools/obtools"
fi
paramName="${1:?missing config}"
paramValue="${2:?missing value}"

case "$paramName" in
  ""|"_"|KB_*|*[!abcdefghijklmnopqrstuvwxyz0123456789_]*)
    echo "invalid oceanbase parameter name: $paramName" >&2
    exit 1
    ;;
esac

#The effective scope of the parameter modification. Valid values:
#  * MEMORY: specifies to modify only parameters in the memory, and the modification takes effect immediately. The modification becomes invalid after the server is restarted. However, no parameter supports this mode.
#  * SPFILE: specifies to modify only parameters in the configuration table. The modification takes effect after the server is restarted.
#  * BOTH: specifies to modify parameters in both the configuration table and the memory. The modification takes effect immediately and remains effective after the server is restarted.
if [ -n "${OB_ROOT_PASSWD:-}" ]; then
  "$OB_CLI" --host 127.0.0.1 -uroot -P "${OB_SERVICE_PORT}" param-update --set "${paramName}=${paramValue}" --scope BOTH -p "${OB_ROOT_PASSWD}"
else
  "$OB_CLI" --host 127.0.0.1 -uroot -P "${OB_SERVICE_PORT}" param-update --set "${paramName}=${paramValue}" --scope BOTH
fi
