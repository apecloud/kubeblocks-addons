#BEParameter: {
	// DYNAMIC parameters

	// Threshold to logging agent task trace, in seconds.
	agent_task_trace_threshold_sec: int | *2

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

	// Thrift default timeout time
	thrift_rpc_timeout_ms: int | *60000

	// Used to set retry interval for thrift client in be to avoid avalanche disaster in fe thrift server, the unit is ms
	thrift_client_retry_interval_ms: int | *1000

	// The default thrift client connection timeout time, the unit is second
	thrift_connect_timeout_seconds: int | *3

	// The maximum size of a (received) message of the thrift server, in bytes. If the size of the message sent by the client exceeds this limit, the Thrift server will reject the request and close the connection. As a result, the client will encounter the error: "connection has been closed by peer." In this case, you can try increasing this parameter. The default value is 104857600(100MB).
	thrift_max_message_size: int | *104857600

	// Txn submit rpc timeout, the unit is ms
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

	// Number of max scan keys
	doris_max_scan_key_num: int | *48

	// When BE performs data scanning, it will split the same scanning range into multiple ScanRanges. This parameter represents the scan data range of each ScanRange. This parameter can limit the time that a single OlapScanner occupies the io thread.
	doris_scan_range_row_count: int | *1000000

	// The maximum number of data rows returned by each scanning thread in a single execution
	doris_scanner_row_num: int | *16384

	// Single read execute fragment row bytes. If there are too many columns in the table, you can adjust this config if you encounter a select * stuck
	doris_scanner_row_bytes: int | *10485760

	// The size of the Buffer queue of the ExchangeNode node, in bytes. After the amount of data sent from the Sender side is larger than the Buffer size of ExchangeNode, subsequent data sent will block until the Buffer frees up space for writing
	exchg_node_buffer_size_bytes: int | *20485760

	// The max number of push down values of a single column. if exceed, no conditions will be pushed down for that column.
	max_pushdown_conditions_per_column: int | *1024

	// The value set by the user for send_batch_parallelism is not allowed to exceed max_send_batch_parallelism_per_job, if exceed, the value of send_batch_parallelism would be max_send_batch_parallelism_per_job
	max_send_batch_parallelism_per_job: int & >= 1 | *5

	// The maximum amount of data read by each OlapScanner.
	doris_scan_range_max_mb: int | *1024

	// Whether disable automatic compaction task
	disable_auto_compaction: bool | *false

	// Whether enable vertical compaction
	enable_vertical_compaction: bool | *true

	// In vertical compaction, column number for every group
	vertical_compaction_num_columns_per_group: int | *5

	// In vertical compaction, max dest segment file size, The unit is m bytes.
	vertical_compaction_max_segment_size: int | *1073741824

	// Whether to enable ordered data compaction
	enable_ordered_data_compaction: bool | *true

	// In ordered data compaction, min segment size for input rowset, The unit is m bytes.
	ordered_data_compaction_min_segment_size: int | *10485760

	// The maximum of thread number in base compaction thread pool, -1 means one thread per disk.
	max_base_compaction_threads: int | *4

	// Sleep interval in ms after generated compaction tasks
	generate_compaction_tasks_interval_ms: int | *10

	// The limit of the number of Cumulative files to be reached. After reaching this limit, BaseCompaction will be triggered
	base_compaction_min_rowset_num: int | *5

	// One of the trigger conditions of BaseCompaction: Cumulative file size reaches the proportion of Base file
	base_compaction_min_data_ratio: float | *0.3

	// The upper limit of "permits" held by all compaction tasks. This config can be set to limit memory consumption for compaction.
	total_permits_for_compaction_score: int | *10000

	// The total disk size of the output rowset of cumulative compaction exceeds this configuration size, and the rowset will be used for base compaction. The unit is m bytes.
	compaction_promotion_size_mbytes: int | *1024

	// Output rowset of cumulative compaction total disk size exceed this config ratio of base rowset's total disk size, this rowset will be given to base compaction. The value must be between 0 and 1.
	compaction_promotion_ratio: float & >0 & < 1 | *0.05

	// The smallest size of rowset promotion. When the rowset is less than this config, this rowset will be not given to base compaction. The unit is m byte.
	compaction_promotion_min_size_mbytes: int | *128

	// When the cumulative compaction is merged, the selected rowsets to be merged have a larger disk size than this configuration, then they are divided and merged according to the level policy. When it is smaller than this configuration, merge directly. The unit is m bytes.
	compaction_min_size_mbytes: int | *64

	// Cumulative compaction strategy: the minimum number of incremental files
	cumulative_compaction_min_deltas: int | *5

	// Cumulative compaction strategy: the maximum number of incremental files
	cumulative_compaction_max_deltas: int | *1000

	// Threshold to logging base compaction's trace information, in seconds
	base_compaction_trace_threshold: int | *60
	
	// Threshold to logging cumulative compaction's trace information, in second
	cumulative_compaction_trace_threshold: int | *10
		
	// The number of compaction tasks which execute in parallel for a disk(HDD)
	compaction_task_num_per_disk: int & >=2 | *4
	
	// The number of compaction tasks which execute in parallel for a fast disk(SSD)
	compaction_task_num_per_fast_disk: int & >=2 | *8
	
	// How many rounds of cumulative compaction for each round of base compaction when compaction tasks generation.
	cumulative_compaction_rounds_for_each_base_compaction_round: int | *9
	
	// The maximum of thread number in cumulative compaction thread pool, -1 means one thread per disk
	max_cumu_compaction_threads: int | *-1
	
	// Global segcompaction thread pool size
	segcompaction_num_threads: int | *5
	
	// Disable the trace log of compaction
	disable_compaction_trace_log: bool | *true
	
	// Select the time interval in seconds for rowset to be compacted.
	pick_rowset_to_compact_interval_sec: int | *86400
	
	// The maximum of thread number in single replica compaction thread pool. -1 means one thread per disk.
	max_single_replica_compaction_threads: int | *-1

	// Minimal interval (s) to update peer replica infos
	update_replica_infos_interval_seconds: int | *60
	
	// Whether to enable stream load record function, the default is false. 
	enable_stream_load_record: bool | *false
	
	// The load error log will be deleted after this time
	load_error_log_reserve_hours: int | *48

	// Error log size limit, default 200MB
	load_error_log_limit_bytes: int | *209715200
	
	// This configuration is mainly used to modify timeout of brpc between master replica and slave replica, used for single replica load.
	slave_replica_writer_rpc_timeout_sec: int | *60
	
	// Used to limit the number of segments in the newly generated rowset when importing. If the threshold is exceeded, the import will fail with error -238. Too many segments will cause compaction to take up a lot of memory and cause OOM errors.
	max_segment_num_per_rowset: int | *1000
	
	// The number of caches for the data consumer used by the routine load.
	routine_load_consumer_pool_size: int | *1024
		
	// When the timeout of an import task is less than this threshold, Doris will consider it to be a high priority task. High priority tasks use a separate pool of flush threads.
	load_task_high_priority_threshold_second: int | *120
	
	// The minimum timeout for each rpc in the load job.
	min_load_rpc_timeout_ms: int | *20000
	
	// The maximum number of consumers in a data consumer group, used for routine load
	max_consumer_num_per_group: int | *3
	
	// Used to limit the maximum amount of csv data allowed in one Stream load.
	streaming_load_max_mb: int | *10240
	
	// It is used to limit the maximum amount of json data allowed in one Stream load. The unit is MB.
	streaming_load_json_max_mb: int | *100
	
	// While loading data, there's a polling thread keep sending data to corresponding BE from Coordinator's sink node. This thread will check whether there's data to send every olap_table_sink_send_interval_microseconds microseconds.
	olap_table_sink_send_interval_microseconds: int | *1000

	// If we load data to a table which enabled auto partition. the interval of olap_table_sink_send_interval_microseconds is too slow. In that case the real interval will multiply this factor.
	olap_table_sink_send_interval_auto_partition_factor: int | *0.001
		
	// The maximum external scan cache batch count, which means that the cache max_memory_cache_batch_count * batch_size row, the default is 20, and the default value of batch_size is 1024, which means that 20 * 1024 rows will be cached in memory.
	max_memory_sink_batch_count: int | *20
		
	// Interval in milliseconds between memtable flush mgr refresh iterations.
	memtable_mem_tracker_refresh_interval_ms: int | *5
	
	// If the number of rows in a page is less than this value, no zonemap will be created to reduce data expansion
	zone_map_row_num_threshold: int | *20
		
	// Maximum memory allowed for a single schema change task.
	memory_limitation_per_thread_for_schema_change_bytes: int | *2147483648
	

	// The minimum length of TCMalloc Hook when consume/release MemTracker. Consume size smaller than this value will continue to accumulate to avoid frequent calls to consume/release of MemTracker. Decreasing this value will increase the frequency of consume/release. Increasing this value will cause MemTracker statistics to be inaccurate. Theoretically, the statistical value of a MemTracker differs from the true value = ( mem_tracker_consume_min_size_bytes * the number of BE threads where the MemTracker is located).
	mem_tracker_consume_min_size_bytes: int | *1048576
		
	// The size of the buffer before flashing to disk.
	write_buffer_size: int | *5242880
	
	// The cache size used when reading files on hdfs or object storage.
	remote_storage_read_buffer_mb: int | *16
	
	// Recycle scan data thread check interval
	path_gc_check_interval_second: int | *86400
	
	path_gc_check_step: int | *1000
	
	path_gc_check_step_interval_ms: int | *10
	
	// This configuration is used for the context gc thread scheduling cycle. The unit is minutes.
	scan_context_gc_interval_min: int | *5
	
	// Configure how many rows of data are contained in a single RowBlock
	default_num_rows_per_column_file_block: int | *1024
		
	// Disable to use page cache for index caching, this configuration only takes effect in BETA storage format, usually it is recommended to false
	disable_storage_page_cache: bool | *false

	// Disk status check interval	
	disk_stat_monitor_interval: int | *5

	// The storage engine allows the percentage of damaged hard disks to exist. After the damaged hard disk exceeds the changed ratio, BE will automatically exit	
	max_percentage_of_error_disk: int | *100

	// The read size is the size of the reads sent to os.	
	read_size: int | *8388608
		
	// The min bytes that should be left of a data dir. Default is 1GB.
	storage_flood_stage_left_capacity_bytes: int | *1073741824

	// The percent of max used capacity of a data dir. Default is 90%.
	storage_flood_stage_usage_percent: int | *90

	// Whether the storage engine opens sync and keeps it to the disk
	sync_tablet_meta: bool | *false

	// The maximum duration of unvalidated data retained by the storage engine
	pending_data_expire_time_sec: int | *1800

	// Limit the number of versions of a single tablet. It is used to prevent a large number of version accumulation problems caused by too frequent import or untimely compaction. When the limit is exceeded, the import task will be rejected.
	max_tablet_version_num: int | *2000
		
	// The time interval for the TabletMeta Checkpoint thread to perform polling.
	tablet_meta_checkpoint_min_interval_secs: int | *600
	// The minimum number of Rowsets for storing TabletMeta Checkpoints	
	tablet_meta_checkpoint_min_new_rowsets_num: int | *10
		
	// It is used to control the expiration time of cleaning up the merged rowset version. When the current time now() minus the max created rowset‘s create time in a version path is greater than tablet_rowset_stale_sweep_time_sec, the current path is cleaned up and these merged rowsets are deleted, the unit is second.
	tablet_rowset_stale_sweep_time_sec: int | *300

	// Used to ignore brpc error '[E1011]The server is overcrowded' when writing data.
	tablet_writer_ignore_eovercrowded: bool | *true

	// The lifetime of TabletsChannel. If the channel does not receive any data at this time, the channel will be deleted.
	streaming_load_rpc_max_alive_time_sec: int | *1200

	// The interval time for the agent to report the disk status to FE
	report_disk_state_interval_seconds: int | *60
		
	// Result buffer cancellation time
	result_buffer_cancelled_interval_time: int | *300
	
	// Snapshot file cleaning interval.
	snapshot_expire_time_sec: int | *172800

	// System log level.
	sys_log_level: string & "INFO" | "WARNING" | "ERROR" | "FATAL" | *"INFO"
		
	// The interval time for the agent to report the olap table to the FE
	report_tablet_interval_seconds: int | *60
		
	// The interval time for the agent to report the task signature to FE
	report_task_interval_seconds: int | *10

	// Used for forward compatibility, will be removed later.
	enable_token_check: bool | *true
	
	// Max number of txns for every txn_partition_map in txn manager, this is a self protection to avoid too many txns saving in manage.
	max_runnings_transactions_per_txn_map: int | *2000

	// Maximum download speed limit, unit is kbps.
	max_download_speed_kbps: int | *50000

	// Download time limit, unit is second.
	download_low_speed_time: int | *300
		
	// Minimum download speed, unit is kbps.
	download_low_speed_limit_kbps: int | *50

	// The increased frequency of priority for remaining tasks in BlockingPriorityQueue
	priority_queue_remaining_tasks_increased_frequency: int | *512

	// Whether enable simdjson to parse json while stream load
	enable_simdjson_reader: bool | *true

	// If true, when the process does not exceed the soft mem limit, the query memory will not be limited; when the process memory exceeds the soft mem limit, the query with the largest ratio between the currently used memory and the exec_mem_limit will be canceled. If false, cancel query when the memory used exceeds exec_mem_limit.
	enable_query_memory_overcommit: bool | *true
	
	// The storage directory for files queried by local table valued functions.
	user_files_secure_path: string | *"/opt/apache-doris/be"
	
	// The batch size for sending data by brpc streaming client
	brpc_streaming_client_batch_bytes: int | *262144

	// In cloud native deployment scenario, BE will be add to cluster and remove from cluster very frequently. User's query will fail if there is a fragment is running on the shuting down BE. Users could use stop_be.sh --grace, then BE will wait all running queries to stop to avoiding running query failure, but if the waiting time exceed the limit, then be will exit directly. During this period, FE will not send any queries to BE and waiting for all running queries to stop.
	grace_shutdown_wait_seconds: int | *120

	// number of threads that fetch auto-inc ranges from FE
	auto_inc_fetch_thread_num: int | *3

	// the ratio of _low_level_water_level_mark/_batch_size in AutoIncIDBuffer
	auto_inc_low_water_level_mark_size_ratio: int | *3

	ca_cert_file_paths: string | *"/etc/pki/tls/certs/ca-bundle.crt;/etc/ssl/certs/ca-certificates.crt;/etc/ssl/ca-bundle.pem"

	// the ratio of _prefetch_size/_batch_size in AutoIncIDBuffer
	auto_inc_prefetch_size_ratio: int | *10

	// The maximum size of a single file in a compaction that contains duplicate keys, in MB.
	base_compaction_dup_key_max_file_size_mbytes: int | *1024

	// The maximum score of a compaction that contains duplicate keys.
	base_compaction_max_compaction_score: int | *20

	// The path to store broken storage files.
	broken_storage_path: string | *""

	// The timeout time for buffered reader to read data, unit is ms.
	buffered_reader_read_timeout_ms: int | *600000

	// The interval time for the agent to prune stale tablets.
	cache_periodic_prune_stale_sweep_sec: int | *300

	// The interval time for the agent to prune stale tablets.
	cache_prune_interval_sec: int | *300

	// Whether to check segment when build rowset meta
	check_segment_when_build_rowset_meta: bool | *false

	// The time interval to clean expired stream load records
	trash_file_expire_time_sec: int | *1800

	// The interval time for the agent to compact cold data
	cold_data_compaction_interval_sec: int | *1800

	// The threshold of the ratio of the number of unique keys to the total number of keys in a column dictionary. If the ratio is less than this value, the column dictionary will not be compressed.
	column_dictionary_key_ratio_threshold: int | *0

	// The threshold of the size of a column dictionary. If the size of a column dictionary is less than this value, the column dictionary will not be compressed.
	column_dictionary_key_size_threshold: int | *0

	// The interval time for the agent to prune stale objects in common object LRU cache.
	common_obj_lru_cache_stale_sweep_time_sec: int | *900

	// The batch size for compaction
	compaction_batch_size: int | *-1

	// The maximum number of invisible versions to keep in a compaction.
	compaction_keep_invisible_version_max_count: int | *500

	// The minimum number of invisible versions to keep in a compaction.
	compaction_keep_invisible_version_min_count: int | *50

	// The timeout time for compaction to keep invisible versions, unit is sec.
	compaction_keep_invisible_version_timeout_sec: int | *1800

	// The maximum memory bytes limit for compaction.
	compaction_memory_bytes_limit: int | *1073741824

	// When output rowset of cumulative compaction total version count (end_version - start_version) exceed this config count, the rowset will be moved to base compaction. This config will work for unique key merge-on-write table only, to reduce version count related cost on delete bitmap more effectively.
	compaction_promotion_version_count: int | *1000

	// The interval time for the agent to confirm unused remote files.
	confirm_unused_remote_files_interval_sec: int | *60

	// The threshold of the memory bytes to crash when allocating large memory.
	crash_in_alloc_large_memory_bytes: int | *-1

	// The factor of the maximum number of deltas to compact in a cumulative compaction.
	cumulative_compaction_max_deltas_factor: int | *10

	// The interval time for the agent to prune stale data pages in data page cache.
	data_page_cache_stale_sweep_time_sec: int | *300

	// Whether to debug inverted index compaction
	debug_inverted_index_compaction: bool | *false
		
	// The interval time for the agent to prune stale bitmaps in aggregation cache.
	delete_bitmap_agg_cache_stale_sweep_time_sec: int | *1800

	// Whether to disable memory garbage collection.
	disable_memory_gc: bool | *false

	// Whether to disable segment cache
	disable_segment_cache: bool | *false

	// Whether to disable row cache feature in storage
	disable_storage_row_cache: bool | *true

	// the timeout of a work thread to wait the blocking priority queue to get a task
	doris_blocking_priority_queue_wait_timeout_ms: int | *500

	// The path to the cgroup cpu directory
	doris_cgroup_cpu_path: string | *""

	// max bytes number for single scan block, used in segmentv2
	doris_scan_block_max_mb: int | *67108864

	// size of scanner queue between scanner thread and compute thread
	doris_scanner_queue_size: int | *1024

	// the threshold of double resize
	double_resize_threshold: int | *23

	// DWARF location info mode
	dwarf_location_info_mode: string | *"FAST"

	// Whether to enable write background when using brpc stream
	enable_brpc_stream_write_background: bool | *true

	// Whether to enable column type check
	enable_column_type_check: bool | *true

	// whether check compaction checksum
	enable_compaction_checksum: bool | *false

	// whether enable compaction priority scheduling
	enable_compaction_priority_scheduling: bool | *true

	// Default 300s, if its value <= 0, then log is disabled
	enable_debug_log_timeout_secs: int | *0

	// Whether to apply delete pred in cumu compaction
	enable_delete_when_cumu_compaction: bool | *false

	// Whether to purge dirty pages in jemalloc
	enable_je_purge_dirty_pages: bool | *true

	// Whether to enable memory orphan check
	enable_memory_orphan_check: bool | *true

	// Whether to enable merge-on-write correctness check
	enable_merge_on_write_correctness_check: bool | *true

	// Whether to enable missing rows correctness check
	enable_missing_rows_correctness_check: bool | *false

	// If set to false, the parquet reader will not use page index to filter data. This is only for debug purpose, in case sometimes the page index filter wrong data.
	enable_parquet_page_index: bool | *false

	// Whether to enable pipeline task leakage detect
	enable_pipeline_task_leakage_detect: bool | *false

	// Whether to enable query like bloom filter
	enable_query_like_bloom_filter: bool | *true

	
	enable_rowid_conversion_correctness_check: bool | *false
	enable_shrink_memory: bool | *false
	enable_use_cgroup_memory_info: bool | *true
	enable_vertical_segment_writer: bool | *true
	enable_workload_group_memory_gc: bool | *true
	estimated_mem_per_column_reader: int | *1024
	exchange_sink_ignore_eovercrowded: bool | *true
	exchg_buffer_queue_capacity_factor: int | *64
	fetch_remote_schema_rpc_timeout_ms: int | *60000
	fetch_rpc_timeout_seconds: int | *30
	file_cache_max_evict_num_per_round: int | *5000
	file_cache_max_file_reader_cache_size: int | *1000000
	file_cache_wait_sec_after_fail: int | *0
	finished_migration_tasks_size: int | *10000
	garbage_sweep_batch_size: int | *100
	generate_cooldown_task_interval_sec: int | *20
	get_stack_trace_tool: string | *"libunwind"
	group_commit_queue_mem_limit: int | *67108864
	hash_table_double_grow_degree: int | *31
	high_disk_avail_level_diff_usages: float | *0.15
	hive_sink_max_file_size: int | *1073741824
	iceberg_sink_max_file_size: int | *1073741824
	ignore_not_found_file_in_external_table: bool | *true
	ignore_rowset_stale_unconsistent_delete: bool | *false
	ignore_schema_change_check: bool | *false
	in_memory_file_size: int | *1048576
	index_cache_entry_stay_time_after_lookup_s: int | *1800
	index_page_cache_stale_sweep_time_sec: int | *600
	inverted_index_cache_stale_sweep_time_sec: int | *600
	inverted_index_compaction_enable: bool | *false
	inverted_index_max_buffered_docs: int | *-1
	inverted_index_ram_buffer_size: float | *512
	inverted_index_ram_dir_enable: bool | *true
	jdbc_connection_pool_cache_clear_time_sec: int | *28800
	je_dirty_pages_mem_limit_percent: string | *"5%"
	jeprofile_dir: string | *"${DORIS_HOME}/log"
	kerberos_ccache_path: string | *""
	kerberos_krb5_conf_path: string | *"/etc/krb5.conf"
	local_exchange_buffer_mem_limit: int | *134217728
	lookup_connection_cache_bytes_limit: int | *4294967296
	low_priority_compaction_score_threshold: int | *200
	low_priority_compaction_task_num_per_disk: int | *2
	max_amplified_read_ratio: float | *0.8
	max_fill_rate: int | *2
	max_fragment_start_wait_time_seconds: int | *30
	max_s3_client_retry: int | *10
	max_tablet_io_errors: int | *-1
	memory_gc_sleep_time_ms: int | *500
	memory_limitation_per_thread_for_storage_migration_bytes: int | *100000000
	memory_maintenance_sleep_time_ms: int | *100
	memtable_flush_running_count_limit: int | *2
	memtable_hard_limit_active_percent: int | *50
	memtable_insert_memory_ratio: float | *1.4
	memtable_soft_limit_active_percent: int | *50
	merged_hdfs_min_io_size: int | *8192
	merged_oss_min_io_size: int | *1048576
	migration_remaining_size_threshold_mb: int | *10
	migration_task_timeout_secs: int | *300
	min_bytes_in_scanner_queue: int | *67108864
	mmap_threshold: int | *134217728
	mow_publish_max_discontinuous_version_num: int | *20
	multi_get_max_threads: int | *10
	nodechannel_pending_queue_max_bytes: int | *67108864
	orc_natural_read_size_mb: int | *8
	parquet_column_max_buffer_mb: int | *8
	parquet_header_max_size_mb: int | *1
	parquet_rowgroup_max_buffer_mb: int | *128
	pipeline_status_report_interval: int | *10
	pipeline_task_leakage_detect_period_secs: int | *60
	pk_index_page_cache_stale_sweep_time_sec: int | *600
	point_query_row_cache_stale_sweep_time_sec: int | *300
	pre_serialize_keys_limit_bytes: int | *16777216
	process_full_gc_size: string | *"10%"
	process_minor_gc_size: string | *"5%"
	public_access_ip: string | *""
	query_statistics_reserve_timeout_ms: int | *30000
	remove_unused_remote_files_interval_sec: int | *21600
	report_query_statistics_interval_ms: int | *3000
	report_random_wait: bool | *true
	rf_predicate_check_row_num: int | *204800
	s3_read_base_wait_time_ms: int | *100
	s3_read_max_wait_time_ms: int | *800
	s3_write_buffer_size: int | *5242880
	s3_writer_buffer_allocation_timeout: int | *300
	scan_thread_nice_value: int | *0
	schema_cache_capacity: int | *1024
	schema_cache_sweep_time_sec: int | *100
	segment_compression_threshold_kb: int | *256
	skip_loading_stale_rowset_meta: bool | *false
	spill_gc_interval_ms: int | *2000
	spill_gc_work_time_ms: int | *2000
	stacktrace_in_alloc_large_memory_bytes: int | *2147483648
	storage_refresh_storage_policy_task_interval_seconds: int | *5
	stream_load_record_batch_size: int | *50
	table_sink_non_partition_write_scaling_data_processed_threshold: int | *
	table_sink_partition_write_max_partition_nums_per_writer: int | *128
	table_sink_partition_write_min_data_processed_rebalance_threshold: int | *
	table_sink_partition_write_min_partition_data_processed_rebalance_threshold: int | *
	tablet_lookup_cache_stale_sweep_time_sec: int | *30
	tablet_meta_serialize_size_limit: int | *1610612736
	tablet_path_check_batch_size: int | *1000
	tablet_rowset_stale_sweep_threshold_size: int | *100
	tablet_schema_cache_capacity: int | *102400
	tablet_schema_cache_recycle_interval: int | *3600
	tablet_version_graph_orphan_vertex_ratio: float | *0.1
	thread_wait_gc_max_milliseconds: int | *1000
	thrift_client_open_num_tries: int | *1
	variant_enable_flatten_nested: bool | *false
	variant_max_merged_tablet_schema_size: int | *2048
	variant_ratio_of_defaults_as_sparse_column: float | *1
	variant_threshold_rows_to_estimate_sparse_column: int | *2048
	variant_throw_exeception_on_invalid_json: bool | *false
	wg_weighted_memory_ratio_refresh_interval_ms: int | *50
	workload_group_scan_task_wait_timeout_ms: int | *10000
	write_buffer_size_for_agg: int | *419430400



	// STATIC parameters
	// Whether to enable set in bitmap value
	enable_set_in_bitmap_value: bool | *false

	// Whether to enable skip tablet compaction
	enable_skip_tablet_compaction: bool | *true

	// Whether to enable snapshot action
	enable_snapshot_action: bool | *false

	// Whether to enable time lut
	enable_time_lut: bool | *true

	// Whether to enable workload group for scan
	enable_workload_group_for_scan: bool | *false

	// Whether to enable write index searcher cache
	enable_write_index_searcher_cache: bool | *true

	// Whether to exit on exception
	exit_on_exception: bool | *false

	// The expiration time of FE cache in seconds
	fe_expire_duration_seconds: int | *60

	// The maximum size of file segment in file cache
	file_cache_max_file_segment_size: int | *4194304

	// The minimum size of file segment in file cache
	file_cache_min_file_segment_size: int | *1048576
		
	// The path to the file cache directory
	file_cache_path: string | *""

	// The protocol for function service
	function_service_protocol: string | *"h2:grpc"

	// The interval time for the agent to generate tablet meta checkpoint tasks
	generate_tablet_meta_checkpoint_tasks_interval_secs: int | *600

	// The number of threads for group commit insert
	group_commit_insert_threads: int | *10

	// The maximum number of rows for max filter ratio in group commit
	group_commit_memory_rows_for_max_filter_ratio: int | *10000

	// The number of threads for group commit relay wal
	group_commit_relay_wal_threads: int | *10

	// The maximum retry interval time for group commit replay wal in seconds
	group_commit_replay_wal_retry_interval_max_seconds: int | *1800

	// The retry interval time for group commit replay wal in seconds
	group_commit_replay_wal_retry_interval_seconds: int | *5

	// The maximum number of retry times for group commit replay wal
	group_commit_replay_wal_retry_num: int | *10

	// Whether to wait for group commit replay wal finish
	group_commit_wait_replay_wal_finish: bool | *false

	// The maximum disk limit for group commit wal
	group_commit_wal_max_disk_limit: string | *"10%"

	// Whether to hide webserver config page
	hide_webserver_config_page: bool | *false

	// Whether to ignore always true predicate for segment
	ignore_always_true_predicate_for_segment: bool | *true

	// The number of rowsets to ignore invalid partition id
	ignore_invalid_partition_id_rowset_num: int | *0

	// The number of threads for ingest binlog work pool
	ingest_binlog_work_pool_size: int | *-1

	// The path to the inverted index dictionary directory
	inverted_index_dict_path: string | *"${DORIS_HOME}/dict"

	// The percentage of file descriptor limit for inverted index
	inverted_index_fd_number_limit_percent: int | *40

	// The limit of query cache memory size for inverted index
	inverted_index_query_cache_limit: string | *"10%"

	// The number of shards for inverted index query cache
	inverted_index_query_cache_shards: int | *256

	// The size of read buffer for inverted index
	inverted_index_read_buffer_size: int | *4096

	// The limit of searcher cache memory size for inverted index
	inverted_index_searcher_cache_limit: string | *"10%"

	// Whether to enable kafka debug
	kafka_debug: string | *"disable"

	// The percentage of memory limit for load process safe memory permit
	load_process_safe_mem_permit_percent: int | *5

	// The maximum retry interval time for load stream eagain wait in seconds
	load_stream_eagain_wait_seconds: int | *600

	// The maximum number of tasks for load stream flush token
	load_stream_flush_token_max_tasks: int | *15

	// The maximum buffer size for load stream
	load_stream_max_buf_size: int | *20971520

	// The maximum wait time for load stream flush token in milliseconds
	load_stream_max_wait_flush_token_time_ms: int | *600000

	// The number of messages in each batch for load stream
	load_stream_messages_in_batch: int | *128


	// The maximum depth of bkd tree
	max_depth_in_bkd_tree: int | *32

	// The maximum depth of expression tree
	max_depth_of_expr_tree: int | *600

	// The maximum number of external file meta cache
	max_external_file_meta_cache_num: int | *1000

	// The maximum number of hdfs file handle cache
	max_hdfs_file_handle_cache_num: int | *1000

	// The maximum time for hdfs file handle cache in seconds
	max_hdfs_file_handle_cache_time_sec: int | *3600

	// The maximum number of meta checkpoint threads
	max_meta_checkpoint_threads: int | *-1

	// The maximum number of tablet migration threads
	max_tablet_migration_threads: int | *1

	// The reserved memory bytes for memtable limiter
	memtable_limiter_reserved_memory_bytes: int | *838860800

	// The timeout time for migration lock in milliseconds
	migration_lock_timeout_ms: int | *1000

	// The minimum number of file descriptors
	min_file_descriptor_number: int | *60000

	// The minimum row group size for parquet reader
	min_row_group_size: int | *134217728

	// The minimum number of tablet migration threads
	min_tablet_migration_threads: int | *1

	// The number of broadcast buffers
	num_broadcast_buffer: int | *32

	// Number of cores Doris will used, this will effect only when it's greater than 0. Otherwise, Doris will use all cores returned from "/proc/cpuinfo".
	num_cores: int | *0

	// Control the number of disks on the machine.  If 0, this comes from the system settings.
	num_disks: int | *0

	// The timeout time for open load stream in milliseconds
	open_load_stream_timeout_ms: int | *60000

	// The maximum buffer size for parquet reader
	parquet_reader_max_buffer_size: int | *50

	// The size of partition disk index lru cache
	partition_disk_index_lru_size: int | *10000

	// The threshold for topn partition
	partition_topn_partition_threshold: int | *1024

	// The number of pipeline executor threads
	pipeline_executor_size: int | *0

	// The limit of page cache memory size for primary key storage
	pk_storage_page_cache_limit: string | *"10%"

	// The size of primary key data page
	primary_key_data_page_size: int | *32768

	// The timeout time for publish version task in seconds
	publish_version_task_timeout_s: int | *8

	// The elasticity size of query cache memory size in MB
	query_cache_elasticity_size_mb: int | *128

	// The maximum number of partitions for query cache
	query_cache_max_partition_count: int | *1024

	// The maximum size of query cache memory size in MB
	query_cache_max_size_mb: int | *256

	// The maximum number of rowsets in each batch for remote split source
	remote_split_source_batch_size: int | *10240

	// The maximum number of write buffers for rocksdb
	rocksdb_max_write_buffer_number: int | *5

	// The load balancer for rpc
	rpc_load_balancer: string | *"rr"

	// The number of threads for s3 transfer executor pool
	s3_transfer_executor_pool_size: int | *2

	// The percentage of file descriptor limit for segment cache
	segment_cache_fd_percentage: int | *40

	// The percentage of memory limit for segment cache
	segment_cache_memory_percentage: int | *2

	// Whether to share delta writers
	share_delta_writers: bool | *true

	// The queue size for spill io thread pool
	spill_io_thread_pool_queue_size: int | *102400

	// The number of threads for spill io thread pool
	spill_io_thread_pool_thread_num: int | *-1

	// The limit of storage size for spill io thread pool
	spill_storage_limit: string | *"20%"

	// The root path for spill storage
	spill_storage_root_path: string | *""

	// The path for ssl certificate
	ssl_certificate_path: string | *""

	// The path for ssl private key
	ssl_private_key_path: string | *""

	// The timeout time for stream load record expire in seconds
	stream_load_record_expire_time_secs: int | *28800

	// The buffer size for stream tvf
	stream_tvf_buffer_size: int | *1048576

	// The roll mode for system log, TIME-DAY, TIME-HOUR, SIZE-MB-nnn
	sys_log_roll_mode: string | *"SIZE-MB-1024"

	// The verbose flags for system log
	sys_log_verbose_flags_v: int | *-1

	// The interval time for tablet path check in seconds
	tablet_path_check_interval_seconds: int | *-1

	// The maximum number of publish transaction threads
	tablet_publish_txn_max_thread: int | *32

	// Whether to enable stale sweep by size for tablet rowset
	tablet_rowset_stale_sweep_by_size: bool | *false

	// The path for temporary files
	tmp_file_dir: string | *"tmp"

	// Whether to wait for internal group commit finish
	wait_internal_group_commit_finish: bool | *false

	// The number of flush thread per store
	wg_flush_thread_num_per_store: int | *6

	// Whether to enable set in bitmap value
	enable_set_in_bitmap_value: bool | *false

	// Whether to enable low cardinality optimize
	enable_low_cardinality_optimize: bool | *true


	// Whether to enable low cardinality cache code
	enable_low_cardinality_cache_code: bool | *true
	
	// Whether to enable jvm monitor
	enable_jvm_monitor: bool | *false
	
	// Whether to check timestamp of inverted index cache
	enable_inverted_index_cache_check_timestamp: bool | *true

	// Whether to enable fuzzy mode
	enable_fuzzy_mode: bool | *false

	// This config controls whether the s3 file writer would flush cache asynchronously
	enable_flush_file_cache_async: bool | *true

	// Whether to enable file logger
	enable_file_logger: bool | *true

	// Whether to enable file cache query limit feature
	enable_file_cache_query_limit: bool | *false

	// Whether to enable file cache feature
	enable_file_cache: bool | *false

	// Whether to enable binlog feature
	enable_feature_binlog: bool | *false

	// Whether to enable debug points
	enable_debug_points: bool | *false

	// Whether to enable base compaction idle scheduler
	enable_base_compaction_idle_sched: bool | *true

	// Whether to check authorization
	enable_all_http_auth: bool | *false

	// Download binlog rate limit, unit is KB/s, 0 means no limit
	download_binlog_rate_limit_kbs: int | *0

	// min thread pool size for scanner thread pool
	doris_scanner_min_thread_pool_thread_num: int | *8

	// number of s3 scanner thread pool size
	doris_remote_scanner_thread_pool_thread_num: int | *48
		
	// number of s3 scanner thread pool queue size
	doris_remote_scanner_thread_pool_queue_size: int | *102400

	// Whether to enable scanner thread pool per disk, if true, each disk will have a separate thread pool for scanner
	doris_enable_scanner_thread_pool_per_disk: bool | *true

	// Whether to disable pk page cache feature in storage
	disable_pk_storage_page_cache: bool | *false

	// The default delete bitmap cache is set to 100MB. We will take the larger of 0.5% of the total memory and 100MB as the delete bitmap cache size.
	delete_bitmap_dynamic_agg_cache_limit: string | *"0.5%"

	// Global bitmap cache capacity for aggregation cache, size in bytes
	delete_bitmap_agg_cache_capacity: int | *104857600

	// The number of threads to compact cold data
	cooldown_thread_num: int | *5

	// The number of threads to compact cold data
	cold_data_compaction_thread_num: int | *2

	// Whether to clear file cache when tablet is deleted
	clear_file_cache: bool | *false

	// the count of thread to calc delete bitmap
	calc_delete_bitmap_max_thread: int | *32

	// The number of threads in the light work pool.
	brpc_light_work_pool_threads: int | *-1

	// The maximum number of requests that can be queued in the light work pool.
	brpc_light_work_pool_max_queue_size: int | *-1

	// the time of brpc server keep idle connection, setting this value too small may cause rpc between backends to fail, the default value is set to -1, which means never close idle connection.
	brpc_idle_timeout_sec: int | *-1

	// The number of threads in the heavy work pool.
	brpc_heavy_work_pool_threads: int | *-1

	// The maximum number of requests that can be queued in the heavy work pool.
	brpc_heavy_work_pool_max_queue_size: int | *-1

	// The port number of the Thrift server on the BE, which is used to receive requests from the FE.
	be_port: int | *9060

	// The port of brpc on the BE, which is used for communication between the BEs.
	brpc_port: int | *8060

	// The service port of the HTTP server on the BE.
	webserver_port: int | *8040

	// The heartbeat service port (Thrift) on the BE, which is used to receive heartbeats from the FE.
	heartbeat_service_port: int | *9050

	// The port of the Arrow Flight SQL server on the FE, which is used for communication between the Arrow Flight Client and the BE
	arrow_flight_sql_port: int | *-1

	// memory mode, performance or compact
	memory_mode: string & "performance" | "compact" | *"moderate"

	// Limit the percentage of the server's maximum memory used by the BE process. It is used to prevent BE memory from occupying too much memory of the machine. This parameter must be greater than 0. When the percentage is greater than 100%, the value will default to 100%.
	mem_limit: string | *"90%"
	
	// Soft memory limit as a fraction of hard memory limit.
	soft_mem_limit_frac: float | *0.9
	
	// Configure the location of the be_custom.conf file
	custom_config_dir: string | *"/opt/apache-doris/be/conf"
	
	// Default dirs to put jdbc drivers.
	jdbc_drivers_dir: string | *"/opt/apache-doris/be/jdbc_drivers"
	
	// This configuration is mainly used to modify the number of bthreads for brpc. If the value is set to -1, which means the number of bthreads is #cpu-cores
	brpc_num_threads: int | *256

	// Declare a selection strategy for those servers with many IPs. Note that at most one ip should match this list. This is a semicolon-separated list in CIDR notation, such as 10.10.10.0/24. If there is no IP matching this rule, one will be randomly selected
	priority_networks: string | *""

	// Whether https is supported. If so, configure ssl_certificate_path and ssl_private_key_path in be.conf.
	enable_https: bool | *false
	
	// data root path, separate by ';'.you can specify the storage medium of each root path, HDD or SSD. you can add capacity limit at the end of each root path, separate by ','.If the user does not use a mix of SSD and HDD disks, they do not need to configure the configuration methods in Example 1 and Example 2 below, but only need to specify the storage directory; they also do not need to modify the default storage media configuration of FE.
	storage_root_path: string | *"/opt/apache-doris/be/storage"
	
	// The number of threads that execute the heartbeat service on BE. the default is 1, it is not recommended to modify
	heartbeat_service_thread_count: int | *1
	
	// When BE starts, check storage_root_path All paths under configuration.
	ignore_broken_disk: bool | *false
		
	//  es scroll keep-alive hold time
	es_scroll_keepalive: string | *"5m"
	
	// This configuration is mainly used to modify the parameter max_body_size of brpc
	brpc_max_body_size: int | *3147483648
		
	// This configuration is mainly used to modify the parameter socket_max_unwritten_bytes of brpc.
	brpc_socket_max_unwritten_bytes: int | *3147483648

	// his configuration indicates the service model used by FE's Thrift service. The type is string and is case-insensitive. This parameter needs to be consistent with the setting of fe's thrift_server_type parameter. Currently there are two values for this parameter, THREADED and THREAD_POOL
	thrift_server_type_of_fe: string | *"THREAD_POOL"
	
	// txn_map_lock fragment size, the value is 2^n, n=0,1,2,3,4. This is an enhancement to improve the performance of managing txn
	txn_map_shard_size: int | *1024

	// txn_lock shard size, the value is 2^n, n=0,1,2,3,4, this is an enhancement function that can improve the performance of submitting and publishing txn
	txn_shard_size: int | *1024

	// The maximum number of client caches per host. There are multiple client caches in BE, but currently we use the same cache size configuration. If necessary, use different configurations to set up different client-side caches
	max_client_cache_size_per_host: int | *10

	// The upper limit of query requests that can be processed on a single node
	fragment_pool_queue_size: int | *4096

	//  Query the number of threads. By default, the minimum number of threads is 64
	fragment_pool_thread_num_min: int | *64

	// Follow up query requests create threads dynamically, with a maximum of 512 threads created.
	fragment_pool_thread_num_max: int | *2048

	// The queue length of the Scanner thread pool. In Doris' scanning tasks, each Scanner will be submitted as a thread task to the thread pool waiting to be scheduled, and after the number of submitted tasks exceeds the length of the thread pool queue, subsequent submitted tasks will be blocked until there is a empty slot in the queue.
	doris_scanner_thread_pool_queue_size: int | *102400

	// The number of threads in the Scanner thread pool. In Doris' scanning tasks, each Scanner will be submitted as a thread task to the thread pool to be scheduled. This parameter determines the size of the Scanner thread pool. The default value is -1, which means the number of threads in the Scanner thread pool is equal to max(48, 2 * num_of_cpu_cores).
	doris_scanner_thread_pool_thread_num: int | *-1
	
	// Max thread number of Remote scanner thread pool. Remote scanner thread pool is used for scan task of all external data sources.
	doris_max_remote_scanner_thread_pool_thread_num: int | *-1

	// In vertical compaction, max memory usage for row_source_buffer
	vertical_compaction_max_row_source_memory_mb: int | *200

	// Config for default rowset type
	default_rowset_type: string & "ALPHA" | "BETA" | *"BETA"
	
	// Enable to use segment compaction during loading to avoid -238 error
	enable_segcompaction: bool | *true

	// Segment compaction is triggered when the number of segments exceeds this threshold. This configuration also limits the maximum number of raw segments in a single segment compaction task.
	segcompaction_batch_size: int | *10

	// Max row count allowed in a single source segment, bigger segments will be skipped.
	segcompaction_candidate_max_rows: int | *1048576

	// Max file size allowed in a single source segment, bigger segments will be skipped.
	segcompaction_candidate_max_bytes: int | *104857600

	// Max total row count allowed in a single segcompaction task.
	segcompaction_task_max_rows: int | *1572864

	// Max total file size allowed in a single segcompaction task.
	segcompaction_task_max_bytes: int | *157286400

	// Used for mini Load. mini load data file will be removed after this time.
	load_data_reserve_hours: int | *4

	// The count of thread to high priority batch load
	push_worker_count_high_priority: int | *3
	
	// The count of thread to batch load
	push_worker_count_normal_priority: int | *3

	// Whether to enable the single-copy data import function.
	enable_single_replica_load: bool | *true

	// The percentage of the upper memory limit occupied by all imported threads on a single node, the default is 50%
	load_process_max_memory_limit_percent: int | *50

	// The soft limit refers to the proportion of the load memory limit of a single node. For example, the load memory limit for all load tasks is 20GB, and the soft limit defaults to 50% of this value, that is, 10GB. When the load memory usage exceeds the soft limit, the job with the largest memory consumption will be selected to be flushed to release the memory space, the default is 80%
	load_process_soft_mem_limit_percent: int | *80
	
	// The max size of thread pool for routine load task. this should be larger than FE config 'max_routine_load_task_num_per_be' (default 5)
	max_routine_load_thread_pool_size: int | *1024
	// number of thread for flushing memtable per store, for high priority load task
	high_priority_flush_thread_num_per_store: int | *6

	// Used in single-stream-multi-table load. When receive a batch of messages from kafka, if the size of batch is more than this threshold, we will request plans for all related tables.
	multi_table_batch_plan_threshold: int | *200
	
	// Used in single-stream-multi-table load. When receiving a batch of messages from Kafka,
	multi_table_max_wait_tables: int | *5

	// Number of download workers for single replica load
	single_replica_load_download_num_workers: int | *64

	// If the dependent Kafka version is lower than 0.10.0.0, this value should be set to false.
	kafka_api_version_request: string | *"true"

	// If the dependent Kafka version is lower than 0.10.0.0, the value set by the fallback version kafka_broker_version_fallback will be used if the value of kafka_api_version_request is set to false, and the valid values are: 0.9.0.x, 0.8.x.y.
	kafka_broker_version_fallback: string | *"0.10.0"

	// The count of thread to delete
	delete_worker_count: int | *3

	// The count of thread to clear transaction task
	clear_transaction_task_worker_count: int | *1

	// The count of thread to clone
	clone_worker_count: int | *3

	// The count of thread to serve backend execution requests
	be_service_threads: int | *64
	
	// The count of thread to download data
	download_worker_count: int | *1
	
	// The count of thread to drop tablet
	drop_tablet_worker_count: int | *3

	// The count of thread for flushing memtable per store
	flush_thread_num_per_store: int | *6

	// The maximum number of the threads per disk is also the max queue depth per disk.
	num_threads_per_disk: int | *0

	// The count of thread to publish version
	publish_version_worker_count: int | *8

	// The count of thread to upload
	upload_worker_count: int | *1

	// Number of webserver workers
	webserver_num_workers: int | *48

	// Number of send batch thread pool size
	send_batch_thread_pool_thread_num: int | *64

	// Number of send batch thread pool queue size
	send_batch_thread_pool_queue_size: int | *102400

	// The count of thread to make snapshot
	make_snapshot_worker_count: int | *5

	// The count of thread to release snapshot
	release_snapshot_worker_count: int | *5

	// The memory limit for row cache, default is 20% of total memory
	row_cache_mem_limit: string | *"20%"

	// The maximum low water mark of the system /proc/meminfo/MemAvailable, Unit byte, default 1.6G, actual low water mark=min(1.6G, MemTotal * 10%), avoid wasting too much memory on machines with large memory larger than 16G. Turn up max. On machines with more than 16G memory, more memory buffers will be reserved for Full GC. Turn down max. will use as much memory as possible.
	max_sys_mem_available_low_water_mark_bytes: int | *6871947673

	// Minimum read buffer size in bytes
	min_buffer_size: int | *1024

	// Whether to enable the recycle scan data thread check
	path_gc_check: bool | *true

	// The maximum interval for disk garbage cleaning, unit is second
	max_garbage_sweep_interval: int | *3600

	// The minimum interval between disk garbage cleaning, unit is second
	min_garbage_sweep_interval: int | *180

	// pprof profile save directory
	pprof_profile_dir: string | *"/opt/apache-doris/be/log"

	// Dir to save files downloaded by SmallFileMgr
	small_file_dir: string | *"/opt/apache-doris/be/lib/small_file/"

	// udf function directory
	user_function_dir: string | *"/opt/apache-doris/be/lib/udf"

	// the count of thread to clone
	storage_medium_migrate_count: int | *1

	// Cache for storage page size
	storage_page_cache_limit: string | *"20%"

	// Shard size for page cache, the value must be power of two. It's recommended to set it to a value close to the number of BE cores in order to reduce lock contentions.
	storage_page_cache_shard_size: int | *256

	// Index page cache as a percentage of total storage page cache, value range is [0, 100]
	index_page_cache_percentage: int & >=0 & <=100 | *10

	// Max number of segment cache, default -1 for backward compatibility fd_number*2/5
	segment_cache_capacity: int | *-1
	
	// Used to check incompatible old format strictly
	storage_strict_check_incompatible_old_format: bool | *true

	// The count of thread to create table
	create_tablet_worker_count: int | *3

	// The count of thread to check consistency
	check_consistency_worker_count: int | *1
	
	// tablet_map_lock shard size, the value is 2^n, n=0,1,2,3,4.. this is a an enhancement for better performance to manage tablet
	tablet_map_shard_size: int | *256
	
	// Update interval of tablet state cache
	tablet_writer_open_rpc_timeout_sec: int | *60
	
	// The count of thread to alter table
	alter_tablet_worker_count: int | *3
		
	// The count of thread to alter index
	alter_index_worker_count: int | *3

	// Whether to continue to start be when load tablet from header failed.
	ignore_load_tablet_failure: bool | *false

	// Storage directory of BE log data
	sys_log_dir: string | *"/opt/apache-doris/be/log"

	// Number of log files kept
	sys_log_roll_num: int | *10

	// Log display level, used to control the log output at the beginning of VLOG in the code
	sys_log_verbose_level: int | *10

	// Log printing module, writing olap will only print the log under the olap module
	sys_log_verbose_modules: string | *""

	// aws sdk log level: Off = 0,Fatal = 1,Error = 2, Warn = 3, Info = 4,Debug = 5,Trace = 6. Default is Off = 0.
	aws_log_level: int | *0
	
	// log buffer level
	log_buffer_level: string | *""

	// If set to true, the metric calculator will run to collect BE-related indicator information, if set to false, it will not run
	enable_metric_calculator: bool | *true

	//  User control to turn on and off system indicators.
	enable_system_metrics: bool | *true

	// BE Whether to enable the use of java-jni. When enabled, mutual calls between c++ and java are allowed. Currently supports hudi, java-udf, jdbc, max-compute, paimon, preload, avro
	enable_java_support: bool | *true
	
	// The WAL directory of group commit.
	group_commit_wal_path: string | *""

	// The JAVA_OPTS startup configuration for the BE node
	JAVA_OPTS: string | *""

	// thread will sleep async_file_cache_init_sleep_interval_ms per scan async_file_cache_init_file_num_interval file num to limit IO
	async_file_cache_init_file_num_interval: int | *1000

	// thread will sleep async_file_cache_init_sleep_interval_ms per scan async_file_cache_init_file_num_interval file num to limit IO
	async_file_cache_init_sleep_interval_ms: int | *20

	// The version of bitmap serialize.
	bitmap_serialize_version: int | *1
}

configuration: #BEParameter & {
}
