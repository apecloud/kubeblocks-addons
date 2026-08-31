{{- if not (has $.PGBOUNCER_POOL_MODE (list "session" "transaction" "statement")) -}}
{{- fail "PGBOUNCER_POOL_MODE must be session, transaction, or statement" -}}
{{- end -}}
{{- $positivePoolValues := dict
  "PGBOUNCER_MAX_CLIENT_CONN" $.PGBOUNCER_MAX_CLIENT_CONN
  "PGBOUNCER_DEFAULT_POOL_SIZE" $.PGBOUNCER_DEFAULT_POOL_SIZE
-}}
{{- range $name, $value := $positivePoolValues -}}
{{- if not (regexMatch "^[1-9][0-9]{0,5}$" $value) -}}
{{- fail (printf "%s must be a decimal integer in 1..999999" $name) -}}
{{- end -}}
{{- end -}}
{{- $nonNegativePoolValues := dict
  "PGBOUNCER_MIN_POOL_SIZE" $.PGBOUNCER_MIN_POOL_SIZE
  "PGBOUNCER_RESERVE_POOL_SIZE" $.PGBOUNCER_RESERVE_POOL_SIZE
  "PGBOUNCER_MAX_DB_CONNECTIONS" $.PGBOUNCER_MAX_DB_CONNECTIONS
  "PGBOUNCER_MAX_USER_CONNECTIONS" $.PGBOUNCER_MAX_USER_CONNECTIONS
-}}
{{- range $name, $value := $nonNegativePoolValues -}}
{{- if not (regexMatch "^(0|[1-9][0-9]{0,5})$" $value) -}}
{{- fail (printf "%s must be a decimal integer in 0..999999" $name) -}}
{{- end -}}
{{- end -}}
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
pool_mode = {{ $.PGBOUNCER_POOL_MODE }}
client_tls_sslmode = disable
server_tls_sslmode = disable
ignore_startup_parameters = extra_float_digits
;;; Static product defaults. default_pool_size applies to each user/database
;;; pool, max_db_connections to each database, and max_user_connections to
;;; each user. They are configurable guardrails, not a global PostgreSQL cap.
max_client_conn = {{ $.PGBOUNCER_MAX_CLIENT_CONN }}
default_pool_size = {{ $.PGBOUNCER_DEFAULT_POOL_SIZE }}
min_pool_size = {{ $.PGBOUNCER_MIN_POOL_SIZE }}
reserve_pool_size = {{ $.PGBOUNCER_RESERVE_POOL_SIZE }}
reserve_pool_timeout = 5
max_db_connections = {{ $.PGBOUNCER_MAX_DB_CONNECTIONS }}
max_user_connections = {{ $.PGBOUNCER_MAX_USER_CONNECTIONS }}
server_idle_timeout = 600
server_lifetime = 3600
query_wait_timeout = 120
client_idle_timeout = 0

;;; [databases] is appended by pgbouncer-setup.sh from the resolved
;;; PostgreSQL primary Service. Do not expose backend host/port as parameters.
