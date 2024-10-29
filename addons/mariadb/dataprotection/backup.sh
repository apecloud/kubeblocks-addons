#!/bin/bash
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -e".
  set -e;
}

backup_database() {
    echo "DB_HOST=${DP_DB_HOST} DB_USER=${DP_DB_USER} DB_PASSWORD=${DP_DB_PASSWORD} DATA_DIR=${DATA_DIR} BACKUP_DIR=${DP_BACKUP_DIR} BACKUP_NAME=${DP_BACKUP_NAME}";
    mariadb-backup --backup  --safe-slave-backup --slave-info --stream=mbstream --host=${DP_DB_HOST} \
    --user=${DP_DB_USER} --password=${DP_DB_PASSWORD} --datadir=${DATA_DIR} > ${DATASAFED_LOCAL_BACKEND_PATH}/${DP_BACKUP_NAME}.mbstream
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
backup_database