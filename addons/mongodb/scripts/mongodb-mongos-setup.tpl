#!/bin/bash
set -x

{{- $mongodb_root := getVolumePathByName ( index $.podSpec.containers 0 ) "data" }}
MONGODB_ROOT={{ $mongodb_root }}
mkdir -p $MONGODB_ROOT/logs
# require port
{{- $mongodb_port_info := getPortByName ( index $.podSpec.containers 0 ) "mongos" }}
{{- $mongodb_port := 27017 }}
{{- if $mongodb_port_info }}
{{- $mongodb_port = $mongodb_port_info.containerPort }}
{{- end }}
MONGOS_PORT={{ $mongodb_port }}
export PATH=$MONGODB_ROOT/tmp/bin:$PATH

. "/scripts/mongodb-common.sh"

cfg_server_endpoints="$(generate_endpoints "$CFG_SERVER_POD_FQDN_LIST" "$CFG_SERVER_INTERNAL_PORT")"
process="mongos --bind_ip_all --port $MONGOS_PORT --configdb $CFG_SERVER_REPLICA_SET_NAME/$cfg_server_endpoints --config /etc/mongodb/mongos.conf"

boot_or_enter_restore "$process"

$process &

process_restore_signal "$process" "start"

process_restore_signal "$process" "end"