[mysqld]
# Replication
log_bin = /var/lib/mysql/binlog/mariadb-bin
binlog_format = ROW
log_slave_updates = ON
gtid_strict_mode = ON
skip_slave_start = 1

# Semi-sync plugins (loaded at startup; enabled/disabled dynamically by syncer)
plugin_load_add = semisync_master.so
plugin_load_add = semisync_slave.so

# InnoDB
innodb_flush_log_at_trx_commit = 1
innodb_buffer_pool_size = 128M

# Connections
max_connections = 200
