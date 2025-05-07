# neo4j.conf
db.tx_log.rotation.retention_policy: 1 days
dbms.ssl.policy.bolt.client_auth: NONE
dbms.ssl.policy.https.client_auth: NONE
internal.dbms.ssl.system.ignore_dot_files: true
server.bolt.connection_keep_alive: 30s
server.bolt.connection_keep_alive_for_requests: ALL
server.bolt.connection_keep_alive_streaming_scheduling_interval: 30s
server.windows_service_name: neo4j

server.default_listen_address: 0.0.0.0