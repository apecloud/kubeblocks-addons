#!/bin/bash

INCLUDE_PATH=""
for dir in $(find addons -maxdepth 2 -type d -name "scripts-ut-spec"); do
    if [ -z "$INCLUDE_PATH" ]; then
        INCLUDE_PATH=$dir
    else
        INCLUDE_PATH=${INCLUDE_PATH},$dir
    fi
done

echo "${INCLUDE_PATH}"
