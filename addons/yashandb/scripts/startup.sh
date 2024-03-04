#!/bin/bash
#startup.sh
WORK_DIR=${WORK_DIR:-/home/yashan}

YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"
YASDB_INSTALL_FILE="${YASDB_MOUNT_HOME}/install.ini"

# shellcheck disable=SC1090
source "${YASDB_TEMP_FILE}"
YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"
YASDB_BIN="${YASDB_HOME}/bin/yasdb"
START_LOG_FILE="$YASDB_DATA/log/start.log"

# shellcheck disable=SC1090
source "${YASDB_ENV_FILE}"

is_yasdb_running() {
    # shellcheck disable=SC2009 disable=SC2126
    alive=$(ps -aux | grep -w "$YASDB_BIN"  | grep -w "$YASDB_DATA" | grep -v -w grep | wc -l)
    if [ "$alive" -eq 0 ]; then
        return 1
    fi
    return 0
}

is_yasdb_running
ret=$?
if [ "$ret" -eq 0 ]; then
    echo "yasdb is already running"
    sleep infinity
fi
rm -rf "${START_LOG_FILE}"
"${YASDB_BIN}" open -D "$YASDB_DATA" >"$START_LOG_FILE" 2>&1 &
i=0
while ((i < 5))
do
    sleep 2
    # shellcheck disable=SC2002 disable=SC2126
    alive=$(cat "$START_LOG_FILE" | grep "Instance started" | wc -l)
    if [ "$alive" -ne 0 ]; then
        echo "process started!"
        break
    fi
    i=$((i+1))
done

if [ "$i" -eq "5" ];then
    echo "start process failed. read $START_LOG_FILE"
    cat "$START_LOG_FILE"
    exit 1
fi

sleep infinity