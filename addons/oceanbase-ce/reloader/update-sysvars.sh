#!/bin/sh
set -ex

OB_CLI="/kb_tools/obtools"
paramName="${1:?missing config}"
paramValue="${2:?missing value}"

case "$paramName" in
  ""|"_"|KB_*|*[!abcdefghijklmnopqrstuvwxyz0123456789_]*)
    echo "invalid oceanbase sysvar name: $paramName" >&2
    exit 1
    ;;
esac

if [ -n "${OB_ROOT_PASSWD:-}" ]; then
  "$OB_CLI" --host 127.0.0.1 -uroot -P "${OB_SERVICE_PORT}" var-update --set "${paramName}='${paramValue}'" -p "${OB_ROOT_PASSWD}" ||
  "$OB_CLI" --host 127.0.0.1 -uroot -P "${OB_SERVICE_PORT}" var-update --set "${paramName}=${paramValue}" -p "${OB_ROOT_PASSWD}"
else
  "$OB_CLI" --host 127.0.0.1 -uroot -P "${OB_SERVICE_PORT}" var-update --set "${paramName}='${paramValue}'" ||
  "$OB_CLI" --host 127.0.0.1 -uroot -P "${OB_SERVICE_PORT}" var-update --set "${paramName}=${paramValue}"
fi
