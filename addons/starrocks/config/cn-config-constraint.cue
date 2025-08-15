#CNParameter: {
	// DYNAMIC parameters
	// The time interval at which to report the state of a task. A task can be creating a table, dropping a table, loading data, or changing a table schema.
	report_task_interval_seconds: int | *10

	// The time interval at which to report the storage volume state, which includes the size of data within the volume.
	report_disk_state_interval_seconds: int | *60

	// The time interval at which to report the most updated version of all tablets.
	report_tablet_interval_seconds: int | *60

	// The time interval at which to report the most updated version of all workgroups.
	report_workgroup_interval_seconds: int | *5

	// The maximum download speed of each HTTP request. This value affects the performance of data replica synchronization across BE nodes.
	max_download_speed_kbps: int | *50000

	// The download speed lower limit of each HTTP request. An HTTP request aborts when it constantly runs with a lower speed than this value within the time span specified in the configuration item `download_low_speed_time`.
	download_low_speed_limit_kbps: int | *50

	// The maximum time that an HTTP request can run with a download speed lower than the limit. An HTTP request aborts when it constantly runs with a lower speed than the value of `download_low_speed_limit_kbps` within the time span specified in this configuration item.
	download_low_speed_time: int | *300

	// The time interval at which a query reports its profile, which can be used for query statistics collection by FE.
	status_report_interval: int | *5

	// The number of threads which the storage engine used for concurrent storage volume scanning. All threads are managed in the thread pool.
	scanner_thread_pool_thread_num: int | *48

	// The time interval at which a thrift client retries.
	thrift_client_retry_interval_ms: int | *100

	// The number of scan tasks supported by the storage engine.
	scanner_thread_pool_queue_size: int | *102400

	// The maximum row count returned by each scan thread in a scan.
	scanner_row_num: int | *16384

	// The maximum number of scan keys segmented by each query.
	max_scan_key_num: int | *1024

	// The maximum number of conditions that allow pushdown in each column. If the number of conditions exceeds this limit, the predicates are not pushed down to the storage layer.
	max_pushdown_conditions_per_column: int | *1024

	// The maximum buffer size on the receiver end of an exchange node for each query. This configuration item is a soft limit. A backpressure is triggered when data is sent to the receiver end with an excessive speed.
	exchg_node_buffer_size_bytes: int | *10485760

	// The maximum memory size allowed for each schema change task.
	memory_limitation_per_thread_for_schema_change: int | *2000000000

	// The expiration time of Update Cache.
	update_cache_expire_sec: int | *360

	// The time interval at which to clean file descriptors that have not been used for a certain period of time.
	file_descriptor_cache_clean_interval: int | *3600

	// The time interval at which to monitor health status of disks.
	disk_stat_monitor_interval: int | *5

	// The time interval at which to clean the expired rowsets.
	unused_rowset_monitor_interval: int | *30

	// The maximum percentage of error that is tolerable in a storage volume before the corresponding BE node quits.
	max_percentage_of_error_disk: int | *0

	// The maximum number of rows that can be stored in each row block.
	default_num_rows_per_column_file_block: int | *1024

	// The expiration time of the pending data in the storage engine.
	pending_data_expire_time_sec: int | *1800

	// The expiration time of the incoming data. This configuration item is used in incremental clone.
	inc_rowset_expired_sec: int | *1800

	// The time interval at which to sweep the stale rowsets in tablets.
	tablet_rowset_stale_sweep_time_sec: int | *1800

	// The expiration time of snapshot files.
	snapshot_expire_time_sec: int | *172800

	// The time interval at which to clean trash files. The default value has been changed from 259,200 to 86,400 since v2.5.17, v3.0.9, and v3.1.6.
	trash_file_expire_time_sec: int | *86400

	// The time interval of thread polling for a Base Compaction.
	base_compaction_check_interval_seconds: int | *60

	// The minimum number of segments that trigger a Base Compaction.
	min_base_compaction_num_singleton_deltas: int | *5

	// The maximum number of segments that can be compacted in each Base Compaction.
	max_base_compaction_num_singleton_deltas: int | *100

	// The time interval since the last Base Compaction. This configuration item is one of the conditions that trigger a Base Compaction.
	base_compaction_interval_seconds_since_last_operation: int | *86400

	// The time interval of thread polling for a Cumulative Compaction.
	cumulative_compaction_check_interval_seconds: int | *1

	// The time interval at which to check the Update Compaction of the Primary Key table.
	update_compaction_check_interval_seconds: int | *60

	// The minimum time interval that a Tablet Compaction can be scheduled since the last compaction failure.
	min_compaction_failure_interval_sec: int | *120

	// The maximum concurrency of compactions (both Base Compaction and Cumulative Compaction). The value -1 indicates that no limit is imposed on the concurrency.
	max_compaction_concurrency: int | *-1

	// The time interval at which to collect the Counter statistics.
	periodic_counter_update_period_ms: int | *500

	// The time for which data loading logs are reserved.
	load_error_log_reserve_hours: int | *48

	// The maximum size of a file that can be streamed into StarRocks.
	streaming_load_max_mb: int | *10240

	// The maximum size of a JSON file that can be streamed into StarRocks.
	streaming_load_max_batch_size_mb: int | *100

	// The time interval at which ColumnPool GC is triggered. StarRocks executes GC periodically and returns the released memory to the operating system.
	memory_maintenance_sleep_time_s: int | *10

	// The buffer size of MemTable in the memory. This configuration item is the threshold to trigger a flush.
	write_buffer_size: int | *104857600

	// The time interval at which to update Tablet Stat Cache.
	tablet_stat_cache_update_interval_second: int | *300

	// The wait time before BufferControlBlock releases data.
	result_buffer_cancelled_interval_time: int | *300

	// The timeout for a thrift RPC.
	thrift_rpc_timeout_ms: int | *5000

	// The maximum number of consumers in a consumer group of Routine Load.
	max_consumer_num_per_group: int | *3

	// The maximum number of Scan Cache batches.
	max_memory_sink_batch_count: int | *20

	// The time interval at which to clean the Scan Context.
	scan_context_gc_interval_min: int | *5

	// The maximum number of files that can be scanned continuously each time.
	path_gc_check_step: int | *1000

	// The time interval between file scans.
	path_gc_check_step_interval_ms: int | *10

	// The time interval at which GC cleans expired data.
	path_scan_interval_second: int | *86400

	// If the storage usage (in percentage) of the BE storage directory exceeds this value and the remaining storage space is less than `storage_flood_stage_left_capacity_bytes`, Load and Restore jobs are rejected.
	storage_flood_stage_usage_percent: int | *95

	// If the remaining storage space of the BE storage directory is less than this value and the storage usage (in percentage) exceeds `storage_flood_stage_usage_percent`, Load and Restore jobs are rejected.
	storage_flood_stage_left_capacity_bytes: int | *107374182400

	// The minimum number of rowsets to create since the last TabletMeta Checkpoint.
	tablet_meta_checkpoint_min_new_rowsets_num: int | *10

	// The time interval of thread polling for a TabletMeta Checkpoint.
	tablet_meta_checkpoint_min_interval_secs: int | *600

	// The maximum number of transactions that can run concurrently in each partition.
	max_runnings_transactions_per_txn_map: int | *100

	// The maximum number of pending versions that are tolerable on a Primary Key tablet. Pending versions refer to versions that are committed but not applied yet.
	tablet_max_pending_versions: int | *1000

	// The maximum number of versions allowed on a tablet. If the number of versions exceeds this value, new write requests will fail.
	tablet_max_versions: int | *1000

	// The maximum number of HDFS file descriptors that can be opened.
	max_hdfs_file_handle: int | *1000

	// The length of time that the BE waits to exit after the disk hangs.
	be_exit_after_disk_write_hang_second: int | *60

	// The minimum time interval at which Cumulative Compaction retries upon failures.
	min_cumulative_compaction_failure_interval_sec: int | *30

	// The number of levels for the Size-tiered Compaction strategy. At most one rowset is reserved for each level. Therefore, under a stable condition, there are, at most, as many rowsets as the level number specified in this configuration item.
	size_tiered_level_num: int | *7

	// The multiple of data size between two contiguous levels in the Size-tiered Compaction strategy.
	size_tiered_level_multiple: int | *5

	// The data size of the minimum level in the Size-tiered Compaction strategy. Rowsets smaller than this value immediately trigger the data compaction.
	size_tiered_min_level_size: int | *131072

	// The PageCache size. It can be specified as size, for example, `20G`, `20,480M`, `20,971,520K`, or `21,474,836,480B`. It can also be specified as the ratio (percentage) to the memory size, for example, `20%`. It takes effect only when `disable_storage_page_cache` is set to `false`.
	storage_page_cache_limit: int | *20

	// The thread pool size allowed on each BE for interacting with Kafka. Currently, the FE responsible for processing Routine Load requests depends on BEs to interact with Kafka, and each BE in StarRocks has its own thread pool for interactions with Kafka. If a large number of Routine Load tasks are distributed to a BE, the BE's thread pool for interactions with Kafka may be too busy to process all tasks in a timely manner. In this situation, you can adjust the value of this parameter to suit your needs.
	internal_service_async_thread_num: int | *10

	// The maximum proportion of data that a compaction can merge for a Primary Key table in a shared-data cluster. We recommend shrinking this value if a single tablet becomes excessively large. This parameter is supported from v3.1.5 onwards.
	update_compaction_ratio_threshold: float | *0.5

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

	// An extra agent service port for CN (BE in v3.0) in a shared-data cluster.
	starlet_port: int | *9070

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
	sys_log_dir: string | *"/opt/starrocks/cn/log"

	// The directory used to store User-defined Functions (UDFs).
	user_function_dir: string | *"/opt/starrocks/cn/lib/udf"

	// The directory used to store the files downloaded by the file manager.
	small_file_dir: string | *"/opt/starrocks/cn/lib/small_file"

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
	storage_root_path: string | *"/opt/starrocks/cn/storage"

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

	// Whether to enable Data Cache in a shared-data cluster. true indicates enabling this feature and false indicates disabling it. The default value is set from false to true from v3.2.3 onwards.
	starlet_use_star_cache: bool | *false

  // how much disk space will star cache occupy for each path.
	starlet_star_cache_disk_size_bytes: int | *0

  // how much disk space will star cache occupy for each path as percentage.
	starlet_star_cache_disk_size_percent: int | *80
}

configuration: #CNParameter & {
}
