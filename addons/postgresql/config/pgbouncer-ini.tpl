[pgbouncer]
listen_addr = *
listen_port = 6432
unix_socket_dir = /tmp/
unix_socket_mode = 0777
auth_file = /opt/bitnami/pgbouncer/conf/userlist.txt
auth_user = postgres
auth_query = SELECT usename, passwd FROM pg_shadow WHERE usename=$1
pidfile =/opt/bitnami/pgbouncer/tmp/pgbouncer.pid
logfile =/opt/bitnami/pgbouncer/logs/pgbouncer.log
# `md5` is PgBouncer's dual-mode auth_type: when the secret fetched via
# auth_query is a SCRAM verifier it automatically performs SCRAM on the wire.
# `auth_type = scram-sha-256` would be SCRAM-only and lock out accounts whose
# stored verifier is still md5 (created by older addon versions) — the server
# side keeps the same dual-mode posture via pg_hba `md5` lines.
auth_type = md5
pool_mode = session
ignore_startup_parameters = extra_float_digits
{{- $max_client_conn := 10000 }}
{{- $phy_memory := int64 $.POSTGRESQL_MEMORY_LIMIT }}
{{- if gt $phy_memory 0 }}
{{- $max_client_conn = min ( div $phy_memory 9531392 ) 5000 }}
{{- end }}
max_client_conn = {{ $max_client_conn }}
admin_users = postgres
;;; [database]
