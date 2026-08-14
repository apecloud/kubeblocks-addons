[mysqld]
# Binary logging is required by the archive-binlog backup method. Keep the
# files on the data volume so the continuous-backup job can read them.
server_id = 1
log_bin = /var/lib/mysql/binlog/mariadb-bin
binlog_format = ROW
# InnoDB
innodb_flush_log_at_trx_commit = 1
innodb_buffer_pool_size = 128M

# Connections
max_connections = 200
max_allowed_packet = 64M

# Query cache (disabled by default; can be enabled via Reconfiguring)
query_cache_type = 0
query_cache_size = 0

# Logging
slow_query_log = 0
long_query_time = 10
