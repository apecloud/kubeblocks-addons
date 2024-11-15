#!/bin/sh
set -ex

CURRENT_PATH=$(cd $(dirname $0);pwd)
source ${CURRENT_PATH}/utils.sh

paramName="${1:?missing config}"
paramValue="${2:?missing value}"

$OB_CLI --host 127.0.0.1 -uroot -P ${OB_SERVICE_PORT} var-update --set ${paramName}=\'${paramValue}\' -p ${OB_ROOT_PASSWD} ||
$OB_CLI --host 127.0.0.1 -uroot -P ${OB_SERVICE_PORT} var-update --set ${paramName}=${paramValue} -p ${OB_ROOT_PASSWD}
