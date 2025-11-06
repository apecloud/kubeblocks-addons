#!/bin/sh
set -ex

OB_CLI="/kb_tools/obtools"
paramName="${1:?missing config}"
paramValue="${2:?missing value}"

$OB_CLI --host 127.0.0.1 -uroot -P ${OB_SERVICE_PORT} var-update --set ${paramName}=\'${paramValue}\' -p ${OB_ROOT_PASSWD} ||
$OB_CLI --host 127.0.0.1 -uroot -P ${OB_SERVICE_PORT} var-update --set ${paramName}=${paramValue} -p ${OB_ROOT_PASSWD}
