[mysqld]
# aliyun buffer pool: https://help.aliyun.com/document_detail/162326.html?utm_content=g_1000230851&spm=5176.20966629.toubu.3.f2991ddcpxxvD1#title-rey-j7j-4dt

{{- $log_root := getVolumePathByName ( index $.podSpec.containers 0 ) "log" }}
{{- $data_root := getVolumePathByName ( index $.podSpec.containers 0 ) "data" }}
{{- $mysql_port_info := getPortByName ( index $.podSpec.containers 0 ) "mysql" }}
{{- $pool_buffer_size := ( callBufferSizeByResource ( index $.podSpec.containers 0 ) ) }}
{{- $phy_memory := getContainerMemory ( index $.podSpec.containers 0 ) }}
{{- $phy_cpu := getContainerCPU ( index $.podSpec.containers 0 ) }}

{{- if $pool_buffer_size }}
innodb_buffer_pool_size={{ $pool_buffer_size }}
{{- end }}

# require port
{{- $mysql_port := 3306 }}
{{- if $mysql_port_info }}
{{- $mysql_port = $mysql_port_info.containerPort }}
{{- end }}

{{- $thread_stack := 262144 }}
{{- $binlog_cache_size := 32768 }}
{{- $join_buffer_size := 262144 }}
{{- $sort_buffer_size := 262144 }}
{{- $read_buffer_size := 262144 }}
{{- $read_rnd_buffer_size := 524288 }}
{{- $single_thread_memory := add $thread_stack $binlog_cache_size $join_buffer_size $sort_buffer_size $read_buffer_size $read_rnd_buffer_size }}

{{- if gt $phy_memory 0 }}
# Global_Buffer = innodb_buffer_pool_size = PhysicalMemory *3/4
# max_connections = (PhysicalMemory  - Global_Buffer) / single_thread_memory
max_connections={{ div ( div $phy_memory 4 ) $single_thread_memory }}
{{- end}}

# if memory less than 8Gi, disable performance_schema
{{- if lt $phy_memory 8589934592 }}
performance_schema=OFF
{{- end }}

# alias replica_exec_mode. Aliyun slave_exec_mode=STRICT
slave_exec_mode=IDEMPOTENT

# gtid
gtid_mode=ON
enforce_gtid_consistency=ON

# consensus
loose_consensus_enabled=ON
loose_consensus_io_thread_cnt=8
loose_consensus_worker_thread_cnt=8
loose_consensus_election_timeout=1000
loose_consensus_auto_leader_transfer=OFF
loose_consensus_prefetch_window_size=100
loose_consensus_auto_reset_match_index=ON
loose_cluster_mts_recover_use_index=ON
# loose_replicate_same_server_id=ON
loose_consensus_large_trx=ON
loose_consensuslog_revise=ON
# loose_cluster_log_type_node=OFF

#server & instances
thread_stack={{ $thread_stack }}
thread_cache_size=60
# ulimit -n
open_files_limit=1048576
local_infile=ON
persisted_globals_load=OFF
sql_mode=NO_ENGINE_SUBSTITUTION
#Default 4000
table_open_cache=4000

# under high number thread (such as 128 threads), this value will cause sysbench fails
# if so, change it to 100000 or higher.
max_prepared_stmt_count=16382

performance_schema_digests_size=10000
performance_schema_events_stages_history_long_size=10000
performance_schema_events_transactions_history_long_size=10000
read_buffer_size={{ $read_buffer_size }}
read_rnd_buffer_size={{ $read_rnd_buffer_size }}
join_buffer_size={{ $join_buffer_size }}
sort_buffer_size={{ $sort_buffer_size }}

#default_authentication_plugin=mysql_native_password    #From mysql8.0.23 is deprecated.
authentication_policy=mysql_native_password,
back_log=5285
host_cache_size=867
connect_timeout=10

# character-sets-dir=/usr/share/mysql-8.0/charsets

port={{ $mysql_port }}
mysqlx_port=33060
mysqlx=0

datadir={{ $data_root }}/data

log_statements_unsafe_for_binlog=OFF
log_error_verbosity=2
log_output=FILE
log_error=/data/mysql/log/mysqld-error.log
slow_query_log=ON
long_query_time=5
slow_query_log_file=/data/mysql/log/mysqld-slowquery.log
general_log=OFF
general_log_file=/data/mysql/log/mysqld.log

# audit log
plugin_load_add=audit_log=audit_log.so
loose_audit_log_handler=FILE # FILE, SYSLOG
loose_audit_log_file={{ $data_root }}/auditlog/audit.log
loose_audit_log_buffer_size=1Mb
loose_audit_log_policy=QUERIES # ALL, LOGINS, QUERIES, NONE
loose_audit_log_strategy=ASYNCHRONOUS
loose_audit_log_rotate_on_size=10485760
loose_audit_log_rotations=5
## mysql> select host, user from mysql.user;
## +-----------+------------------+
## | host      | user             |
## +-----------+------------------+
## | %         | root             |
## | %         | u1               |
## | localhost | mysql.infoschema |
## | localhost | mysql.session    |
## | localhost | mysql.sys        |
## | localhost | root             |
## +-----------+------------------+
loose_audit_log_exclude_accounts=root@%,root@localhost

#innodb
innodb_doublewrite_batch_size=16
innodb_doublewrite_pages=32
innodb_flush_method=O_DIRECT
innodb_io_capacity=200
innodb_io_capacity_max=2000
innodb_log_buffer_size=8388608
#innodb_log_file_size and innodb_log_files_in_group are deprecated in MySQL 8.0.30. These variables are superseded by innodb_redo_log_capacity.
#innodb_log_file_size=134217728
#innodb_log_files_in_group=2

{{- /* dynamic render innodb_redo_log_capacity */}}
{{- /* reference url: https://dev.mysql.com/doc/refman/8.0/en/innodb-dedicated-server.html */}}
{{- if gt $phy_memory 0 }}
  {{- $redo_log_capacity := 104857600 }}
  {{- $phy_memory_gb := div $phy_memory 1073741824 | int }}
  {{- if lt $phy_memory_gb  2 }}
    {{- /* < 2GB: 100MB */}}
    {{- $redo_log_capacity = 104857600 }}
  {{- else if lt $phy_memory_gb 4 }}
    {{- /* [2GB: 4GB):  round(0.5 * detected server memory in GB) * 0.5 GB */}}
    {{- $redo_log_capacity = ( mulf ( round ( mulf $phy_memory_gb 0.5 ) 0 )  512 1024 1024 ) | int }}
  {{- else if lt $phy_memory_gb 11 }}
    {{- /* [4GB: 11GB):  round(0.75 * detected server memory in GB) * 0.5 GB */}}
    {{- $redo_log_capacity = ( mulf ( round ( mulf $phy_memory_gb 0.75 ) 0 ) 512 1024 1024 ) | int }}
  {{- else if lt $phy_memory_gb 170 }}
    {{- /* [11GB: 170GBH):  round(0.6525 * detected server memory in GB) * 0.5 GB */}}
    {{- $redo_log_capacity = ( mulf ( round ( mulf $phy_memory_gb 0.6525 ) 0 ) 512 1024 1024 ) | int }}
  {{- else }}
    {{- /* >= 17GB: 128GB */}}
    {{- $redo_log_capacity = ( mul 128 1024 1024 1024 ) | int }}
  {{- end }}
innodb_redo_log_capacity={{- $redo_log_capacity }}
{{- end }}
innodb_open_files=4000
innodb_purge_threads=1
innodb_read_io_threads=4
# innodb_print_all_deadlocks=ON    # AWS not set
key_buffer_size=16777216

# binlog
# master_info_repository=TABLE
# From mysql8.0.23 is deprecated.
binlog_cache_size={{ $binlog_cache_size }}
# AWS binlog_format=MIXED, Aliyun is ROW
binlog_format=ROW
binlog_row_image=FULL
# Aliyun AWS binlog_order_commits=ON
binlog_order_commits=ON
log_bin={{ $data_root }}/binlog/mysql-bin
log_bin_index={{ $data_root }}/binlog/mysql-bin.index
binlog_expire_logs_seconds=604800
binlog_purge_size=102400M
max_binlog_size=134217728
log_replica_updates=1
# binlog_rows_query_log_events=ON #AWS not set
# binlog_transaction_dependency_tracking=WRITESET    #Default Commit Order, Aws not set

# replay log
# relay_log_info_repository=TABLE
# From mysql8.0.23 is deprecated.
relay_log_recovery=ON
relay_log=relay-bin
relay_log_index=relay-bin.index

pid_file=/var/run/mysqld/mysqld.pid
socket=/var/run/mysqld/mysqld.sock

{{- if eq (index $ "TLS_ENABLED") "true" }}
# tls
# require_secure_transport=ON
ssl_ca=/etc/pki/tls/ca.pem
ssl_cert=/etc/pki/tls/cert.pem
ssl_key=/etc/pki/tls/key.pem
{{- end }}

## smartengine base config
#default_storage_engine=smartengine
default_tmp_storage_engine=innodb
loose_smartengine=0

# log_error_verbosity=3
# binlog_format=ROW

## non classes config

loose_smartengine_datadir={{ $data_root }}/smartengine
loose_smartengine_wal_dir={{ $data_root }}/smartengine
loose_smartengine_flush_log_at_trx_commit=1
loose_smartengine_enable_2pc=1
loose_smartengine_batch_group_slot_array_size=5
loose_smartengine_batch_group_max_group_size=15
loose_smartengine_batch_group_max_leader_wait_time_us=50
loose_smartengine_block_size=16384
loose_smartengine_disable_auto_compactions=0
loose_smartengine_dump_memtable_limit_size=0

loose_smartengine_min_write_buffer_number_to_merge=1
loose_smartengine_level0_file_num_compaction_trigger=64
loose_smartengine_level0_layer_num_compaction_trigger=2
loose_smartengine_level1_extents_major_compaction_trigger=1000
loose_smartengine_level2_usage_percent=70
loose_smartengine_flush_delete_percent=70
loose_smartengine_compaction_delete_percent=50
loose_smartengine_flush_delete_percent_trigger=700000
loose_smartengine_flush_delete_record_trigger=700000
loose_smartengine_scan_add_blocks_limit=100

loose_smartengine_compression_per_level=kZSTD:kZSTD:kZSTD


## classes classes config

{{- if gt $phy_memory 0 }}
{{- $phy_memory := div $phy_memory ( mul 1024 1024 ) }}
loose_smartengine_write_buffer_size={{ min ( max 32 ( mulf $phy_memory 0.01 ) ) 256 | int | mul 1024 1024 }}
loose_smartengine_db_write_buffer_size={{ mulf $phy_memory 0.3 | int | mul 1024 1024 }}
loose_smartengine_db_total_write_buffer_size={{ mulf $phy_memory 0.3 | int | mul 1024 1024 }}
loose_smartengine_block_cache_size={{ mulf $phy_memory 0.3 | int | mul 1024 1024 }}
loose_smartengine_row_cache_size={{ mulf $phy_memory 0.1 | int | mul 1024 1024 }}
loose_smartengine_max_total_wal_size={{ min ( mulf $phy_memory 0.3 ) ( mul 12 1024 ) | int | mul 1024 1024 }}
{{- end }}

{{- if gt $phy_cpu 0 }}
loose_smartengine_max_background_flushes={{ max 1 ( min ( div $phy_cpu 2 ) 8 ) | int }}
loose_smartengine_base_background_compactions={{ max 1 ( min ( div $phy_cpu 2 ) 8 ) | int }}
loose_smartengine_max_background_compactions={{ max 1 (min ( div $phy_cpu 2 ) 12 ) | int }}
{{- end }}

skip_name_resolve=ON


[client]
port={{ $mysql_port }}
socket=/var/run/mysqld/mysqld.sock
