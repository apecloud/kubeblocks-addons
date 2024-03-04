#!/bin/bash
#stop.sh
WORK_DIR=${WORK_DIR:-/home/yashan}
YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"
YASDB_INSTALL_FILE="${YASDB_MOUNT_HOME}/install.ini"

# shellcheck disable=SC1090
source "${YASDB_TEMP_FILE}"
YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"
YASDB_BIN="${YASDB_HOME}/bin/yasdb"

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

wait_yasdb_stop() {
    i=0
    retval=1
    while ((i < 5))
    do
        sleep 1
        is_yasdb_running
        ret=$?
        if [ "$ret" -eq 0 ]; then
            retval=0
            break
        fi
        i=$((i+1))
    done
    return $retval
}

is_yasdb_running
ret=$?
if [ "$ret" -ne 0 ]; then
    echo "yasdb is already stopped"
    exit 0
fi

# shellcheck disable=SC2009
pid=$(ps -aux | grep -w "$YASDB_BIN"  | grep -w "$YASDB_DATA" | grep -v -w grep | awk '{print $2}')
kill -15 "$pid"

wait_yasdb_stop
if [ "$ret" -eq 0 ]; then
    echo "Succeed !"
    exit 0
else
    echo "Failed !"
    exit 1
fi