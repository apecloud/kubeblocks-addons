#!/bin/bash
#initDB.sh
WORK_DIR=${WORK_DIR:-/home/yashan}

YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"
YASDB_INSTALL_FILE="${YASDB_MOUNT_HOME}/install.ini"
INSTALL_INI_FILE="${YASDB_INSTALL_FILE}"

YASDB_PASSWORD="yasdb_123"

# shellcheck disable=SC1090
source "${YASDB_TEMP_FILE}"
YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"
YASDB_HOME_BIN_PATH="${YASDB_HOME}/bin"
YASDB_BIN="${YASDB_HOME_BIN_PATH}/yasdb"
YASQL_BIN="${YASDB_HOME_BIN_PATH}/yasql"
YASPWD_BIN="${YASDB_HOME_BIN_PATH}/yaspwd"

# shellcheck disable=SC1090
source "${YASDB_ENV_FILE}"

e_i=$(sed -n '$=' "$INSTALL_INI_FILE")
s_i=$(sed -n -e '/\<instance\>/=' "$INSTALL_INI_FILE")
n_i=$((s_i + 1))

sed -n "${n_i},${e_i} p" "$INSTALL_INI_FILE" >>"$YASDB_DATA"/config/yasdb.ini

if [ ! -f "$YASDB_HOME/admin/yasdb.pwd" ]; then
    "$YASPWD_BIN" file="$YASDB_HOME"/admin/yasdb.pwd password="$YASDB_PASSWORD"
else
    rm -f "$YASDB_HOME"/admin/yasdb.pwd
    "$YASPWD_BIN" file="$YASDB_HOME"/admin/yasdb.pwd password="$YASDB_PASSWORD"
fi
cp "$YASDB_HOME"/admin/yasdb.pwd "$YASDB_DATA"/instance/yasdb.pwd

REDOFILE="("
for ((i = 0; i < "$REDO_FILE_NUM"; i++)); do
    if [ $i == $((REDO_FILE_NUM - 1)) ]; then
        REDOFILE=${REDOFILE}"'redo${i}'"" size $REDO_FILE_SIZE)"
    else
        REDOFILE=${REDOFILE}"'redo${i}'"" size $REDO_FILE_SIZE,"
    fi
done

START_LOG_FILE="$YASDB_DATA/log/start.log"
rm -rf "${START_LOG_FILE}"
"${YASDB_BIN}" nomount -D "$YASDB_DATA" >"$START_LOG_FILE" 2>&1 &
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

"${YASQL_BIN}" sys/$YASDB_PASSWORD >>"$START_LOG_FILE" <<EOF
create database yasdb CHARACTER SET $NLS_CHARACTERSET logfile $REDOFILE;
exit;
EOF

i=0
while ((i < 60))
do
    sleep 1
    alive=$($YASQL_BIN sys/$YASDB_PASSWORD -c "select open_mode from v\$database" | grep -c READ_WRITE)
    if [ "$alive" -eq 1 ]; then
        echo "Database open succeed !"
        break
    fi
    i=$((i+1))
done

if [ "$i" -eq "60" ];then
    echo "Failed ! please check logfile $START_LOG_FILE ."
    exit 1
fi

if [ "$INSTALL_SIMPLE_SCHEMA_SALES" == 'Y' ] || [ "$INSTALL_SIMPLE_SCHEMA_SALES" == 'y' ]; then
    "${YASQL_BIN}" sys/$YASDB_PASSWORD -f "$YASDB_HOME"/admin/simple_schema/sales.sql >>"$START_LOG_FILE"
fi

sleep infinity