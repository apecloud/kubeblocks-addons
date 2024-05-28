#!/bin/bash

# copy the orchestrator configuration file
WORKDIR=${WORKDIR:-/opt/orchestrator}
ORC_RAFT_ENABLED=${ORC_RAFT_ENABLED:-"true"}
ORC_BACKEND_DB=${ORC_BACKEND_DB:-sqlite}

META_MYSQL_PORT=${META_MYSQL_PORT:-3306}
META_MYSQL_ENDPOINT=${META_MYSQL_ENDPOINT:-""}
ORC_META_DATABASE=${ORC_META_DATABASE:-orchestrator}

mkdir -p $WORKDIR
mkdir -p $WORKDIR/raft $WORKDIR/sqlite

SUBDOMAIN=${KB_CLUSTER_COMP_NAME}-headless
replicas=$(eval echo ${KB_POD_LIST} | tr ',' '\n')
PEERS=""
for replica in ${replicas}; do
    host=${replica}.${SUBDOMAIN}
    PEERS="${PEERS},\"${host}\""
done
# remove the first comma
PEERS=${PEERS#,}

if [ $ORC_RAFT_ENABLED == 'true' ]; then
  ORC_PEERS=$PEERS
  ORC_POD_NAME=${KB_POD_NAME}.${SUBDOMAIN}
else
  ORC_PEERS=""
  ORC_POD_NAME=""
fi

cat /configs/orchestrator.tpl > $WORKDIR/orchestrator.conf.json
# set backend db
sed -i "s|\${ORC_BACKEND_DB}|${ORC_BACKEND_DB}|g" $WORKDIR/orchestrator.conf.json
# set workdir
sed -i "s|\${ORC_WORKDIR}|${WORKDIR}|g" $WORKDIR/orchestrator.conf.json
# set orch backed db info
sed -i "s/\${META_MYSQL_ENDPOINT}/$META_MYSQL_ENDPOINT/g" $WORKDIR/orchestrator.conf.json
sed -i "s/\${META_MYSQL_PORT}/$META_MYSQL_PORT/g" $WORKDIR/orchestrator.conf.json
sed -i "s/\${ORC_META_DATABASE}/$ORC_META_DATABASE/g" $WORKDIR/orchestrator.conf.json

# set raft mode
sed -i "s|\${ORC_RAFT_ENABLED}|${ORC_RAFT_ENABLED}|g" $WORKDIR/orchestrator.conf.json

# set peers
sed -i "s|\${ORC_PEERS}|${ORC_PEERS}|g" $WORKDIR/orchestrator.conf.json
sed -i "s|\${ORC_POD_NAME}|${ORC_POD_NAME}|g" $WORKDIR/orchestrator.conf.json

cat $WORKDIR/orchestrator.conf.json

/usr/local/orchestrator/orchestrator -quiet -config $WORKDIR/orchestrator.conf.json http