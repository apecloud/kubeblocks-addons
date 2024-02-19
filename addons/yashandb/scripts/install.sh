#!/bin/bash
#install.sh
WORK_DIR=${WORK_DIR:-/home/yashan}

YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"
YASDB_INSTALL_FILE="${YASDB_MOUNT_HOME}/install.ini"

# copy file if not exists
if [ ! -f "$YASDB_INSTALL_FILE" ]; then
    cp "/home/yashan/kbconfigs/install.ini" "${YASDB_INSTALL_FILE}"
    # shellcheck disable=SC2002
    cat "${YASDB_INSTALL_FILE}" | grep "=" > "${YASDB_TEMP_FILE}"
fi
    # shellcheck disable=SC1090
source "${YASDB_TEMP_FILE}"

if [ -f "$YASDB_DATA"/config/yasdb.ini ]; then
    echo "yasdb.ini is already exists"
    sed -i '/'"source ${YASDB_HOME//\//\\/}\/conf\/yasdb.bashrc"'/d' ~/.bashrc

    YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"

    cat >"${YASDB_ENV_FILE}" <<EOF
    export YASDB_HOME=$YASDB_HOME
    export YASDB_DATA=$YASDB_DATA
    export PATH=\$YASDB_HOME/bin:\$PATH
    export LD_LIBRARY_PATH=\$YASDB_HOME/lib:\$LD_LIBRARY_PATH
EOF

    cat >>~/.bashrc <<EOF
    [ -f $YASDB_ENV_FILE ] && source $YASDB_ENV_FILE
EOF
    source /home/yashan/kbscripts/startup.sh
else
    mkdir -p "$YASDB_HOME"
    cp -ra "$WORK_DIR"/{admin,bin,conf,gitmoduleversion.dat,include,java,lib,plug-in,scripts} "$YASDB_HOME"
    mkdir -p "$YASDB_HOME"/client
    touch "$YASDB_HOME"/client/yasc_service.ini

    mkdir -p "$YASDB_DATA"/{config,data,dbfiles,instance,archive,local_fs,log/{run,audit,trace,alarm,alert,listener},diag/{metadata,hm,blackbox}}

    sed -i '/'"source ${YASDB_HOME//\//\\/}\/conf\/yasdb.bashrc"'/d' ~/.bashrc

    YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"

    cat >"${YASDB_ENV_FILE}" <<EOF
    export YASDB_HOME=$YASDB_HOME
    export YASDB_DATA=$YASDB_DATA
    export PATH=\$YASDB_HOME/bin:\$PATH
    export LD_LIBRARY_PATH=\$YASDB_HOME/lib:\$LD_LIBRARY_PATH
EOF

    cat >>~/.bashrc <<EOF
    [ -f $YASDB_ENV_FILE ] && source $YASDB_ENV_FILE
EOF

    source /home/yashan/kbscripts/initDB.sh
fi