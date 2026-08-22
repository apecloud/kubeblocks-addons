[pgbouncer]
listen_addr = *
listen_port = 6432
unix_socket_dir = /tmp
unix_socket_mode = 0770
auth_file = /opt/bitnami/pgbouncer/conf/userlist.txt
auth_type = md5
auth_user = postgres
auth_query = SELECT usename, passwd FROM pg_shadow WHERE usename=$1
auth_dbname = postgres
admin_users = postgres
stats_users = postgres
pidfile = /opt/bitnami/pgbouncer/tmp/pgbouncer.pid
pool_mode = session
ignore_startup_parameters = extra_float_digits
max_client_conn = 500
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 5
max_db_connections = 80
max_user_connections = 80
server_idle_timeout = 600
server_lifetime = 3600
query_wait_timeout = 120
client_idle_timeout = 0

;;; [databases] is appended by pgbouncer-setup.sh from the resolved
;;; PostgreSQL primary Service. Do not expose backend host/port as parameters.
