#!/bin/bash
. /scripts/set_config_variables.sh
set_config_variables vtgate

cell=${CELL:-'zone1'}
web_port=${VTGATE_WEB_PORT:-'15001'}
grpc_port=${VTGATE_GRPC_PORT:-'15991'}
mysql_server_port=${VTGATE_MYSQL_PORT:-'15306'}
mysql_server_socket_path="/tmp/mysql.sock"

endpoints=${ETCD_SERVER:-'127.0.0.1:2379'}

echo $endpoints

topology_fags="--topo_implementation etcd2 --topo_global_server_address ${endpoints} --topo_global_root /vitess/${KB_CLUSTER_NAME}/global"

echo "starting vtgate."
su vitess <<EOF
exec vtgate \
  $topology_fags \
  --alsologtostderr \
  $(if [ "$enable_logs" == "true" ]; then echo "--log_dir $VTDATAROOT"; fi) \
  $(if [ "$enable_query_log" == "true" ]; then echo "--log_queries_to_file $VTDATAROOT/vtgate_querylog.txt"; fi) \
  --port $web_port \
  --grpc_port $grpc_port \
  --mysql_server_port $mysql_server_port \
  --mysql_server_socket_path $mysql_server_socket_path \
  --cell $cell \
  --cells_to_watch $cell \
  --tablet_types_to_wait PRIMARY,REPLICA \
  --service_map 'grpc-vtgateservice' \
  --pid_file $VTDATAROOT/vtgate.pid
EOF