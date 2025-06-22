#!/bin/bash

role=$(curl -s 127.0.0.1:8008 | jq | grep -i '"role"' | awk -F'"' '{print $4}')

if [ $? -ne 0 ]; then
    exit -1
fi

role_lower=$(echo "$role" | tr '[:upper:]' '[:lower:]')

case $role_lower in
    "master" | "standby_leader" | "primary")
        echo -n "primary"
        ;;
    "replica")
        echo -n "secondary"
        ;;
    *)
        echo -n "unknown"
        ;;
esac


