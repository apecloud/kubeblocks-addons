#!/bin/bash

function create_mnode() {
  first_ep=${TAOS_FIRST_EP%:*}
  res=$(taos -h$first_ep -p$TAOS_ROOT_PASSWORD -s "create mnode on dnode ${1}" 2>&1)
  if [[ "$res" == *"Create OK"* ]]; then
     echo "create mnode success on dnode ${1}"
  elif [[ "$res" == *"already exists"* ]]; then
     echo "mnode already exists"
  else
     echo "create mnode failed: $res"
     exit 1
  fi
}

if [ $COMPONENT_REPLICAS -lt 3 ]; then
    exit 0
else
    echo "create mnode on dnode 2, 3"
    create_mnode 2
    create_mnode 3
fi