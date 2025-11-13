#!/bin/bash

result=$(curl -s "http://127.0.0.1:16010/jmx?qry=Hadoop:service=HBase,name=Master,sub=Server" | grep '"tag.isActiveMaster"' | awk -F'"' '{print $4}')
if [ "$result" = "true" ]; then
    echo "active" | tr -d '\n'
elif [ "$result" = "false" ]; then
    echo "standby" | tr -d '\n'
fi