[mysqld]
binlog_format = ROW
default_storage_engine = InnoDB
innodb_autoinc_lock_mode = 2
innodb_flush_log_at_trx_commit = 0
innodb_buffer_pool_size = 128M
max_connections = 200

# Galera / wsrep
wsrep_on = ON
wsrep_provider = /usr/lib/galera/libgalera_smm.so
# SST method = rsync (Path 3 bounded experiment per Jack TL ack 21:09 thread
# /msg=35fc973c). Background: mariabackup-based SST fails on the joiner with
# `--move-back ... 1 (Operation not permitted)` because mariabackup performs
# chown(2) on extracted files while running as the unprivileged mysql user
# (UID 999), and Linux setuid(mysql) drops effective capabilities to 0 even
# when the container's securityContext.capabilities.add includes CHOWN/FOWNER
# (those go to bounding set only; ambient set is empty). rsync SST does not
# perform such chown calls, so it should bypass the EPERM path.
#
# Tradeoffs accepted for the bounded experiment:
# - rsync SST is single-threaded and not encrypted-on-the-wire (vs mariabackup
#   which supports parallel + TLS). For our test harness this is acceptable;
#   production rollout requires re-evaluation per Jack's gate.
# - rsync SST blocks the donor (puts it into Donor/Desynced state) for the
#   duration of the transfer. Test datasets are small so impact is negligible.
wsrep_sst_method = rsync
wsrep_slave_threads = 4
wsrep_log_conflicts = ON
