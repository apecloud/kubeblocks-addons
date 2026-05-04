[mysqld]
# Replication
log_bin = /var/lib/mysql/binlog/mariadb-bin
binlog_format = ROW
log_slave_updates = ON
gtid_strict_mode = OFF
skip_slave_start = 1

# Semi-sync is built-in to MariaDB 11.4 (no plugin .so files needed).
# Enable both master and slave sides; MariaDB uses the appropriate one based on role.
rpl_semi_sync_master_enabled = ON
rpl_semi_sync_slave_enabled = ON
# Block writes if no semi-sync slave is connected (reduces MDEV-36934 deadlock risk)
rpl_semi_sync_master_wait_no_slave = ON
# Ack timeout: fall back to async after 5s (default 10s causes race with mariadb client timeouts)
rpl_semi_sync_master_timeout = 5000
# AFTER_COMMIT: primary commits locally first, then waits for slave ACK.
# This keeps the server responsive when the ACK receiver hangs (e.g. after a slave RST-kill),
# at the cost of a narrow window where committed-but-not-replicated data could be lost.
# AFTER_SYNC (default) would block ALL commits if the ACK receiver deadlocks.
rpl_semi_sync_master_wait_point = AFTER_COMMIT

# InnoDB
innodb_flush_log_at_trx_commit = 1
innodb_buffer_pool_size = 128M

# Connections
# 500 slots: kbagent roleProbe timeouts can accumulate CLOSE-WAIT connections;
# generous headroom prevents "Too many connections" errors under load.
max_connections = 500
# Close idle connections quickly to prevent CLOSE-WAIT accumulation during semi-sync fallback
wait_timeout = 60
interactive_timeout = 60
# Short network I/O timeouts so the semi-sync ACK receiver recovers quickly
# when a slave is RST-killed (avoids ~150s deadlock on the primary).
net_read_timeout = 10
net_write_timeout = 10
