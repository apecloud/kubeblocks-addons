[pgbouncer]
listen_addr = *
listen_port = 6432
unix_socket_dir = /tmp
unix_socket_mode = 0770
auth_file = /etc/pgbouncer/userlist.txt
auth_type = md5
auth_user = postgres
auth_query = SELECT rolname, CASE WHEN rolvaliduntil IS NOT NULL AND rolvaliduntil < pg_catalog.now() THEN NULL ELSE rolpassword END FROM pg_catalog.pg_authid WHERE rolname=$1 AND rolcanlogin
auth_dbname = postgres
admin_users = postgres
stats_users = postgres
pool_mode = session
client_tls_sslmode = disable
server_tls_sslmode = disable
ignore_startup_parameters = extra_float_digits
;;; Static product defaults. default_pool_size applies to each user/database
;;; pool, max_db_connections to each database, and max_user_connections to
;;; each user. They are configurable guardrails, not a global PostgreSQL cap.
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
