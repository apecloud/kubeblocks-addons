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

	ca_cert_file_paths: string | *"/etc/pki/tls/certs/ca-bundle.crt;/etc/ssl/certs/ca-certificates.crt;/etc/ssl/ca-bundle.pem"


	// STATIC parameters

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

}

configuration: #BEParameter & {
}
