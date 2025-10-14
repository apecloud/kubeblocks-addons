#BEParameter: {
	// DYNAMIC parameters
	// The interval for cleaning the recycle bin is 24 hours. When the disk space is insufficient, the file retention period under trash may not comply with this parameter
	trash_file_expire_time_sec: int | *86400

	// The timeout period for connecting to ES via http. Unit is millisecond
	es_http_timeout_ms: int | *5000

	// The timeout when establishing connection with external table such as ODBC table
	external_table_connect_timeout_sec: int | *30

	// Interval between profile reports. Unit is second
	status_report_interval: int | *5

	// This configuration is used to control whether to serialize the protoBuf request and embed the Tuple/Block data into the controller attachment and send it through http brpc when the length of the Tuple/Block data is greater than 1.8G. To avoid errors when the length of the protoBuf request exceeds 2G: Bad request, error_text=[E1003]Fail to compress request. In the past version, after putting Tuple/Block data in the attachment, it was sent through the default baidu_std brpc, but when the attachment exceeds 2G, it will be truncated. There is no 2G limit for sending through http brpc.
	transfer_large_data_by_brpc: bool | *true

	// thrift default timeout time
	thrift_rpc_timeout_ms: int | *60000

	// Used to set retry interval for thrift client in be to avoid avalanche disaster in fe thrift server, the unit is ms
	thrift_client_retry_interval_ms: int | *1000

	// The default thrift client connection timeout time, the unit is second
	thrift_connect_timeout_seconds: int | *3

	// The maximum size of a (received) message of the thrift server, in bytes. If the size of the message sent by the client exceeds this limit, the Thrift server will reject the request and close the connection. As a result, the client will encounter the error: "connection has been closed by peer." In this case, you can try increasing this parameter. The default value is 104857600(100MB).
	thrift_max_message_size: int | *104857600

	// txn submit rpc timeout, the unit is ms
	txn_commit_rpc_timeout_ms: int | *60000

	// Time interval for clearing expired Rowset, the unit is second
	unused_rowset_monitor_interval: int | *30

	// The soft limit of the maximum length of String type.
	string_type_length_soft_limit_bytes: int | *1048576

	// When using the odbc external table, if a column type of the odbc source table is HLL, CHAR or VARCHAR, and the length of the column value exceeds this value, the query will report an error 'column value length longer than buffer length'. You can increase this value
	big_column_size_buffer: int | *65535

	// When using the odbc external table, if a column type of the odbc source table is not HLL, CHAR or VARCHAR, and the length of the column value exceeds this value, the query will report an error 'column value length longer than buffer length'. You can increase this value
	small_column_size_buffer: int | *100

	// The soft limit of the maximum length of JSONB type.
	jsonb_type_length_soft_limit_bytes: int & >= 1 & <= 2147483643 | *1048576

	// number of max scan keys
	doris_max_scan_key_num: int | *48

	// When BE performs data scanning, it will split the same scanning range into multiple ScanRanges. This parameter represents the scan data range of each ScanRange. This parameter can limit the time that a single OlapScanner occupies the io thread.
	doris_scan_range_row_count: int | *1000000

	// The maximum number of data rows returned by each scanning thread in a single execution
	doris_scanner_row_num: int | *16384

	// single read execute fragment row bytes. If there are too many columns in the table, you can adjust this config if you encounter a select * stuck
	doris_scanner_row_bytes: int | *10485760

	// The size of the Buffer queue of the ExchangeNode node, in bytes. After the amount of data sent from the Sender side is larger than the Buffer size of ExchangeNode, subsequent data sent will block until the Buffer frees up space for writing
	exchg_node_buffer_size_bytes: int | *20485760

	max_pushdown_conditions_per_column: int | *1024

	max_send_batch_parallelism_per_job: int & >= 1 | *5

	doris_scan_range_max_mb: int | *1024

	disable_auto_compaction: bool | *false

	enable_vertical_compaction: bool | *true

	vertical_compaction_num_columns_per_group: int | *5

	vertical_compaction_max_segment_size: int | *1073741824

	enable_ordered_data_compaction
	ordered_data_compaction_min_segment_size
	max_base_compaction_threads
	generate_compaction_tasks_interval_ms
	base_compaction_min_rowset_num
	base_compaction_min_data_ratio
	total_permits_for_compaction_score
	compaction_promotion_size_mbytes
	compaction_promotion_ratio
	compaction_promotion_min_size_mbytes
	compaction_min_size_mbytes
	cumulative_compaction_min_deltas
	cumulative_compaction_max_deltas
	base_compaction_trace_threshold
	cumulative_compaction_trace_threshold
	compaction_task_num_per_disk
	compaction_task_num_per_fast_disk
	cumulative_compaction_rounds_for_each_base_compaction_round
	max_cumu_compaction_threads
	segcompaction_num_threads
	disable_compaction_trace_log
	pick_rowset_to_compact_interval_sec
	max_single_replica_compaction_threads
	update_replica_infos_interval_seconds
	enable_stream_load_record
	load_error_log_reserve_hours
	load_error_log_limit_bytes
	slave_replica_writer_rpc_timeout_sec
	max_segment_num_per_rowset
	routine_load_consumer_pool_size
	load_task_high_priority_threshold_second
	min_load_rpc_timeout_ms
	max_consumer_num_per_group
	streaming_load_max_mb
	streaming_load_json_max_mb
	olap_table_sink_send_interval_microseconds
	olap_table_sink_send_interval_auto_partition_factor
	max_memory_sink_batch_count
	memtable_mem_tracker_refresh_interval_ms
	zone_map_row_num_threshold
	memory_limitation_per_thread_for_schema_change_bytes
	mem_tracker_consume_min_size_bytes
	write_buffer_size
	remote_storage_read_buffer_mb
	path_gc_check_interval_second
	path_gc_check_step
	path_gc_check_step_interval_ms
	scan_context_gc_interval_min
	default_num_rows_per_column_file_block
	disable_storage_page_cache
	disk_stat_monitor_interval
	max_percentage_of_error_disk
	read_size
	storage_flood_stage_left_capacity_bytes
	storage_flood_stage_usage_percent
	sync_tablet_meta
	pending_data_expire_time_sec
	max_tablet_version_num
	tablet_meta_checkpoint_min_interval_secs
	tablet_meta_checkpoint_min_new_rowsets_num
	tablet_rowset_stale_sweep_time_sec
	tablet_writer_ignore_eovercrowded
	streaming_load_rpc_max_alive_time_sec
	report_disk_state_interval_seconds
	result_buffer_cancelled_interval_time
	snapshot_expire_time_sec
	sys_log_level
	report_tablet_interval_seconds
	report_task_interval_seconds
	enable_token_check
	max_runnings_transactions_per_txn_map
	max_download_speed_kbps
	download_low_speed_time
	download_low_speed_limit_kbps
	priority_queue_remaining_tasks_increased_frequency
	enable_simdjson_reader
	enable_query_memory_overcommit
	user_files_secure_path
	brpc_streaming_client_batch_bytes
	grace_shutdown_wait_seconds
	ca_cert_file_paths



	// STATIC parameters

	// Specifies whether to enable the hedged read feature. This parameter is supported from v3.0 onwards.
	hdfs_client_enable_hedged_read: bool | *false

	// Specifies the size of the Hedged Read thread pool on your HDFS client. The thread pool size limits the number of threads to dedicate to the running of hedged reads in your HDFS client. This parameter is supported from v3.0 onwards. It is equivalent to the dfs.client.hedged.read.threadpool.size parameter in the hdfs-site.xml file of your HDFS cluster.
	hdfs_client_hedged_read_threadpool_size: int | *128

	// Specifies the number of milliseconds to wait before starting up a hedged read. For example, you have set this parameter to 30. In this situation, if a read from a block has not returned within 30 milliseconds, your HDFS client immediately starts up a new read against a different block replica. This parameter is supported from v3.0 onwards. It is equivalent to the dfs.client.hedged.read.threshold.millis parameter in the hdfs-site.xml file of your HDFS cluster.
	hdfs_client_hedged_read_threshold_millis: int | *2500

	// The BE thrift server port, which is used to receive requests from FEs.
	be_port: int | *9060

	// The BE bRPC port, which is used to view the network statistics of bRPCs.
	brpc_port: int | *8060

	// The number of bthreads of a bRPC. The value -1 indicates the same number with the CPU threads.
	brpc_num_threads: int | *-1

	// The CIDR-formatted IP address that is used to specify the priority IP address of a BE node if the machine that hosts the BE node has multiple IP addresses.
	priority_networks: string | *""

	// A boolean value to control whether to use IPv6 addresses preferentially when priority_networks is not specified. true indicates to allow the system to use an IPv6 address preferentially when the server that hosts the node has both IPv4 and IPv6 addresses and priority_networks is not specified.
	net_use_ipv6_when_priority_networks_empty: bool | *false

	// The BE heartbeat service port, which is used to receive heartbeats from FEs.
	heartbeat_service_port: int | *9050

	// The thread count of the BE heartbeat service.
	heartbeat_service_thread_count: int | *1

	// The number of threads used to create a tablet.
	create_tablet_worker_count: int | *3

	// The number of threads used to drop a tablet.
	drop_tablet_worker_count: int | *3

	// The number of threads used to handle a load task with NORMAL priority.
	push_worker_count_normal_priority: int | *3

	// The number of threads used to handle a load task with HIGH priority.
	push_worker_count_high_priority: int | *3

	// The maximum number of threads used to publish a version. When this value is set to less than or equal to 0, the system uses half of the CPU core count as the value, so as to avoid insufficient thread resources when import concurrency is high but only a fixed number of threads are used. From v2.5, the default value has been changed from 8 to 0.
	transaction_publish_version_worker_count: int | *0

	// The number of threads used for clearing transaction.
	clear_transaction_task_worker_count: int | *1

	// The number of threads used for schema change.
	alter_tablet_worker_count: int | *3

	// The number of threads used for clone.
	clone_worker_count: int | *3

	// The number of threads used for storage medium migration (from SATA to SSD).
	storage_medium_migrate_count: int | *1

	// The number of threads used for checking the consistency of tablets.
	check_consistency_worker_count: int | *1

	// The directory that stores system logs (including INFO, WARNING, ERROR, and FATAL).
	sys_log_dir: string | *"/opt/starrocks/be/log"

	// The directory used to store User-defined Functions (UDFs).
	user_function_dir: string | *"/opt/starrocks/be/lib/udf"

	// The directory used to store the files downloaded by the file manager.
	small_file_dir: string | *"/opt/starrocks/be/lib/small_file"

	// The severity levels into which system log entries are classified. Valid values: INFO, WARN, ERROR, and FATAL.
	sys_log_level: string | *"INFO"

	// The mode in which system logs are segmented into log rolls. Valid values include `TIME-DAY`, `TIME-HOUR`, and `SIZE-MB-`size. The default value indicates that logs are segmented into rolls, each of which is 1 GB.
	sys_log_roll_mode: string | *"SIZE-MB-1024"

	// The number of log rolls to reserve.
	sys_log_roll_num: int | *10

	// The module of the logs to be printed. For example, if you set this configuration item to OLAP, StarRocks only prints the logs of the OLAP module. Valid values are namespaces in BE, including starrocks, starrocks::debug, starrocks::fs, starrocks::io, starrocks::lake, starrocks::pipeline, starrocks::query_cache, starrocks::stream, and starrocks::workgroup.
	sys_log_verbose_modules: string | *""

	// The level of the logs to be printed. This configuration item is used to control the output of logs initiated with VLOG in codes.
	sys_log_verbose_level: int | *10

	// The strategy for flushing logs. The default value indicates that logs are buffered in memory. Valid values are -1 and 0. -1 indicates that logs are not buffered in memory.
	log_buffer_level: string | *""

	// The number of threads started on each CPU core.
	num_threads_per_core: int | *3

	// A boolean value to control whether to compress the row batches in RPCs between BEs. TRUE indicates compressing the row batches, and FALSE indicates not compressing them.
	compress_rowbatches: bool | *true

	// A boolean value to control whether to serialize the row batches in RPCs between BEs. TRUE indicates serializing the row batches, and FALSE indicates not serializing them.
	serialize_batch: bool | *false

	// The directory and medium of the storage volume. Multiple volumes are separated by semicolons (`;`). If the storage medium is SSD, add `medium:ssd` at the end of the directory. If the storage medium is HDD, add ,medium:hdd at the end of the directory.
	storage_root_path: string | *"/opt/starrocks/be/storage"

	// The maximum length of input values for bitmap functions.
	max_length_for_bitmap_function: int | *1000000

	// The maximum length of input values for the to_base64() function.
	max_length_for_to_base64: int | *200000

	// The maximum number of tablets in each shard. This configuration item is used to restrict the number of tablet child directories under each storage directory.
	max_tablet_num_per_shard: int | *1024

	// The maximum time interval for garbage collection on storage volumes.
	max_garbage_sweep_interval: int | *3600

	// The minimum time interval for garbage collection on storage volumes.
	min_garbage_sweep_interval: int | *180

	// The number of file descriptors that can be cached.
	file_descriptor_cache_capacity: int | *16384

	// The minimum number of file descriptors in the BE process.
	min_file_descriptor_number: int | *60000

	// The cache capacity for the statistical information of BloomFilter, Min, and Max.
	index_stream_cache_capacity: int | *10737418240

	// A boolean value to control whether to disable PageCache. When PageCache is enabled, StarRocks caches the recently scanned data. PageCache can significantly improve the query performance when similar queries are repeated frequently. TRUE indicates disabling PageCache. The default value of this item has been changed from TRUE to FALSE since StarRocks v2.4.
	disable_storage_page_cache: bool | *false

	// The number of threads used for Base Compaction on each storage volume.
	base_compaction_num_threads_per_disk: int | *1

	// The ratio of cumulative file size to base file size. The ratio reaching this value is one of the conditions that trigger the Base Compaction.
	base_cumulative_delta_ratio: float | *0.3

	// The time threshold for each compaction. If a compaction takes more time than the time threshold, StarRocks prints the corresponding trace.
	compaction_trace_threshold: int | *60

	// The HTTP server port.
	be_http_port: int | *8040

	// The number of threads used by the HTTP server.
	be_http_num_workers: int | *48

	// The reservation time for the files produced by small-scale loadings.
	load_data_reserve_hours: int | *4

	// The number of threads used for Stream Load.
	number_tablet_writer_threads: int | *16

	// The RPC timeout for Stream Load.
	streaming_load_rpc_max_alive_time_sec: int | *1200

	// The minimum number of threads used for query.
	fragment_pool_thread_num_min: int | *64

	// The maximum number of threads used for query.
	fragment_pool_thread_num_max: int | *4096

	// The upper limit of the query number that can be processed on each BE node.
	fragment_pool_queue_size: int | *2048

	// A boolean value to control whether to enable the token check. TRUE indicates enabling the token check, and FALSE indicates disabling it.
	enable_token_check: bool | *true

	// A boolean value to control whether to enable the pre-fetch of the query. TRUE indicates enabling pre-fetch, and FALSE indicates disabling it.
	enable_prefetch: bool | *true

	// The maximum size limit of memory resources that can be taken up by all load processes on a BE node.
	load_process_max_memory_limit_bytes: int | *107374182400

	// The maximum percentage limit of memory resources that can be taken up by all load processes on a BE node.
	load_process_max_memory_limit_percent: int | *30

	// A boolean value to control whether to enable the synchronization of the tablet metadata. TRUE indicates enabling synchronization, and FALSE indicates disabling it.
	sync_tablet_meta: bool | *false

	// The thread pool size for Routine Load on each BE. Since v3.1.0, this parameter is deprecated. The thread pool size for Routine Load on each BE is now controlled by the FE dynamic parameter max_routine_load_task_num_per_be.
	routine_load_thread_pool_size: int | *10

	// The maximum body size of a bRPC.
	brpc_max_body_size: int | *2147483648

	// The tablet map shard size. The value must be a power of two.
	tablet_map_shard_size: int | *32

	// A boolean value to control whether to enable the new storage format of the BITMAP type, which can improve the performance of bitmap_union. TRUE indicates enabling the new storage format, and FALSE indicates disabling it.
	enable_bitmap_union_disk_format_with_set: bool | *false

	// BE process memory upper limit. You can set it as a percentage ("80%") or a physical limit ("100GB").
	mem_limit: string | *"90%"

	// Number of threads that are used for flushing MemTable in each store.
	flush_thread_num_per_store: int | *2

	// Whether to enable Data Cache. TRUE indicates Data Cache is enabled, and FALSE indicates Data Cache is disabled.
	datacache_enable: bool | *false

	// The paths of disks. We recommend that the number of paths you configure for this parameter is the same as the number of disks on your BE machine. Multiple paths need to be separated with semicolons (;).
	datacache_disk_path: string | *null

	// The storage path of block metadata. You can customize the storage path. We recommend that you store the metadata under the $STARROCKS_HOME path.
	datacache_meta_path: string | *null

	// The maximum amount of data that can be cached in memory. You can set it as a percentage (for example, `10%`) or a physical limit (for example, `10G`, `21474836480`). The default value is `10%`. We recommend that you set the value of this parameter to at least 10 GB.
	datacache_mem_size: string | *"10%"

	// The maximum amount of data that can be cached on a single disk. You can set it as a percentage (for example, `80%`) or a physical limit (for example, `2T`, `500G`). For example, if you configure two disk paths for the `datacache_disk_path` parameter and set the value of the `datacache_disk_size` parameter as `21474836480` (20 GB), a maximum of 40 GB data can be cached on these two disks. The default value is `0`, which indicates that only memory is used to cache data. Unit: bytes.
	datacache_disk_size: int | *0

	// The JDBC connection pool size. On each BE node, queries that access the external table with the same jdbc_url share the same connection pool.
	jdbc_connection_pool_size: int | *8

	// The minimum number of idle connections in the JDBC connection pool.
	jdbc_minimum_idle_connections: int | *1

	// The length of time after which an idle connection in the JDBC connection pool expires. If the connection idle time in the JDBC connection pool exceeds this value, the connection pool closes idle connections beyond the number specified in the configuration item jdbc_minimum_idle_connections.
	jdbc_connection_idle_timeout_ms: int | *600000

	// The size of the query cache in the BE. Unit: bytes. The default size is 512 MB. The size cannot be less than 4 MB. If the memory capacity of the BE is insufficient to provision your expected query cache size, you can increase the memory capacity of the BE.
	query_cache_capacity: int | *536870912

	// Whether to enable the Event-based Compaction Framework. TRUE indicates Event-based Compaction Framework is enabled, and FALSE indicates it is disabled. Enabling Event-based Compaction Framework can greatly reduce the overhead of compaction in scenarios where there are many tablets or a single tablet has a large amount of data.
	enable_event_based_compaction_framework: bool | *true

	// Whether to enable the Size-tiered Compaction strategy. TRUE indicates the Size-tiered Compaction strategy is enabled, and FALSE indicates it is disabled.
	enable_size_tiered_compaction_strategy: bool | *true

	// The maximum concurrency of RPC requests in a shared-data cluster. Incoming requests will be rejected when this threshold is reached. When this item is set to 0, no limit is imposed on the concurrency.
	lake_service_max_concurrency: int | *0
}

configuration: #BEParameter & {
}
