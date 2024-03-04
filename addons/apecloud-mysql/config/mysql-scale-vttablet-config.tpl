[vttablet]
health_check_interval=1s
shard_sync_retry_delay=1s
remote_operation_timeout=1s
db_connect_timeout_ms=500
table_acl_config_mode=mysqlbased
enable_logs=true
enable_query_log=true
table_acl_config=
queryserver_config_strict_table_acl=true
table_acl_config_reload_interval=5s
enforce_tableacl_config=false

{{- $phy_memory := getContainerMemory ( index $.podSpec.containers 0 ) }}
{{- $thread_stack := 262144 }}
{{- $binlog_cache_size := 32768 }}
{{- $join_buffer_size := 262144 }}
{{- $sort_buffer_size := 262144 }}
{{- $read_buffer_size := 262144 }}
{{- $read_rnd_buffer_size := 524288 }}
{{- $single_thread_memory := add $thread_stack $binlog_cache_size $join_buffer_size $sort_buffer_size $read_buffer_size $read_rnd_buffer_size }}
{{- if gt $phy_memory 0 }}
# max_connections={{ div ( div $phy_memory 4 ) $single_thread_memory }}
{{- end}}

{{- $max_connections := div ( div $phy_memory 4 ) $single_thread_memory }}
# 10 percentage
{{- $pool_k := max 1 ( div (sub $max_connections 35) 10 ) }}

# TxPool
queryserver_config_transaction_cap={{ mul 5 $pool_k }}

# OltpReadPool
queryserver_config_pool_size={{ mul 4 $pool_k }}

# OlapReadPool
queryserver_config_stream_pool_size={{ mul $pool_k }}


# the size of database connection pool in non transaction dml
non_transactional_dml_database_pool_size=3

# the number of rows to be processed in one batch by default
non_transactional_dml_default_batch_size=2000

# the interval of batch processing in milliseconds by default
non_transactional_dml_default_batch_interval=1

# the interval of table GC in hours
non_transactional_dml_table_gc_interval=24

# the interval of job scheduler running in seconds
non_transactional_dml_job_manager_running_interval=24

# the interval of throttle check in milliseconds
non_transactional_dml_throttle_check_interval=250

# the threshold of batch size
non_transactional_dml_batch_size_threshold=10000

# final threshold = ratio * non_transactional_dml_batch_size_threshold / table index numbers
non_transactional_dml_batch_size_threshold_ratio=0.5