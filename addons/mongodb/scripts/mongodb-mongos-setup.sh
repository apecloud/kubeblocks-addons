#!/bin/bash

MONGOS_PORT=${SERVICE_PORT:-27017}
MONGODB_ROOT=${DATA_VOLUME:-/data/mongodb}

mkdir -p $MONGODB_ROOT/logs
export PATH=$MONGODB_ROOT/tmp/bin:$PATH

. "/scripts/mongodb-common.sh"

cfg_server_endpoints="$(generate_endpoints "$CFG_SERVER_POD_FQDN_LIST" "$CFG_SERVER_INTERNAL_PORT")"
process="mongos --bind_ip_all --port $MONGOS_PORT --configdb $CFG_SERVER_REPLICA_SET_NAME/$cfg_server_endpoints --config /etc/mongodb/mongos.conf"

boot_or_enter_restore "$process"

$process &

process_restore_signal "$process" "start"

process_restore_signal "$process" "end"