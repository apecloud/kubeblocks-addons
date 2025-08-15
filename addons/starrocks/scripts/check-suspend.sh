#!/bin/bash


suspend_file=/opt/starrocks/kb/suspend

if [ ! -f "$suspend_file" ]; then
    exit 0
fi

function info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

while grep "$KB_POD_NAME" $suspend_file > /dev/null; do
    info "waiting for $KB_POD_NAME to be removed from suspend list"
    sleep 5
done

info "$KB_POD_NAME is not in suspend list anymore, ready to start."
