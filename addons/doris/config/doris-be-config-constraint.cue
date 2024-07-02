#DorisbeParameter: {
    // Declare a selection policy for servers that have a lot of ip. Note that at most one ip should match this list. This is a list in semicolon-separated format, using CIDR notation, such as 10.10.10.0/24. If no ip address matches this rule, a random IP address is selected. default ''
    priority_networks: string
    // set current date for java_opts
    CUR_DATE: string
    // log path
    PPROF_TMPDIR: string
    // java_opts
    JAVA_OPTS: string
    // java_opts_jdk_9
    JAVA_OPTS_FOR_JDK_9: string
    // JEMALLOC CONF
    JEMALLOC_CONF: string
    // JEMALLOC PROF PRFIX default ""
    JEMALLOC_PROF_PRFIX: string
    // system log level
    sys_log_level: string
    // Port number of the thrift server on BE, used to receive requests from FE default 9060
    be_port: int
    // Service port of the http server on BE default 8040
    webserver_port: int
    // The heartbeat service port (thrift) on the BE is used to receive heartbeats from the FE default 9050
    heartbeat_service_port: int
    // The port of the brpc on the BE, used for communication between the BE default 9060
    brpc_port: int
    // Whether https is supported. If yes, configure ssl_certificate_path and ssl_private_key_path in be.conf default false
    enable_https: bool
    // Whether https is supported. If yes, configure ssl_certificate_path in be.conf
    ssl_certificate_path: string
    // Whether https is supported. If yes, configure ssl_private_key_path in be.conf
    ssl_private_key_path: string
    // cdfm self-defined parameter default false
    enable_auth: bool
    //  RPC port for communication between the Master copy and Slave copy in the single copy data import function. default 9070
    single_replica_load_brpc_port: int
    // In the single copy data import function, the Slave copy downloads data files from the Master copy through HTTP. default 8050
    single_replica_load_download_port: int
    // BE data storage directory, multi-directory with English status semicolon; Separate. You can distinguish the storage medium, HDD or SSD, by the path. default ${DORIS_HOME}/storage
    storage_root_path: string
    // Number of threads executing the heartbeat service on the BE. The default value is 1. You are not recommended to change the value default 1
    heartbeat_service_thread_count: int
    // ignore_broken_disk=true If the path does not exist or files cannot be read or written in the path (bad disk), the path is ignored. If other paths are available, the startup is not interrupted.default false
    ignore_broken_disk: bool
    // Limit the maximum percentage of server memory used by the BE process. default auto
    mem_limit: string
    // The id of the cluster to which the BE belongs is specified.default -1
    cluster_id: int
    // Dynamic configuration Modifies the directory
    custom_config_dir: string
    // The interval for cleaning the recycle bin is 72 hours. If the disk space is insufficient, the file retention period in the trash does not comply with this parameter default 259200
    trash_file_expire_time_sec: int
    // The timeout time for connecting to ES over http,default 5000(ms)
    es_http_timeout_ms: int
    // es scroll Keeplive hold time, default 5(m)
    es_scroll_keepalive: int
    // Timeout period for establishing a connection with an external table. default 5(s)
    external_table_connect_timeout_sec: int
    // Interval between configuration file reports;default 5(s)
    status_report_interval: int
    // This configuration is used to modify the brpc parameter max_body_size.
    brpc_max_body_size: int
    // This configuration is used to modify the brpc parameter socket_max_unwritten_bytes.
    brpc_socket_max_unwritten_bytes: int
    // This parameter is used to control whether the Tuple/Block data length is greater than 1.8 GB. The protoBuf request is serialized and embedded into the controller attachment along with the Tuple/Block data and sent via http brpc.default true
    transfer_large_data_by_brpc: bool
    // This configuration is primarily used to modify the number of bthreads in the brpc. The default value for this configuration is set to -1, which means that the number of bthreads will be set to the number of cpu cores on the machine. default -1
    brpc_num_threads: int
    // Default timeout of thrift default 10000(ms)
    thrift_rpc_timeout_ms: int
    // This parameter is used to set the retry interval for the thrift client of be to prevent avalanches from occurring on the thrift server of fe default 1000(ms)
    thrift_client_retry_interval_ms: int
    // Default connection timeout of thrift client default 180 (3m)
    thrift_connect_timeout_seconds: int
    // Configure the service model used by the Thrift service of FE. optionals: 1.THREADED 2.THREAD_POOL
    thrift_server_type_of_fe: string
    // The txn rpc submission timed out default 60000(ms)
    txn_commit_rpc_timeout_ms: int
    // txn map lock Fragment size. The value is 2^n default 128
    txn_map_shard_size: int
    // txn lock fragment size, the value is 2^n, default 1024
    txn_shard_size: int
    // Interval for clearing an expired Rowset default 30(s)
    unused_rowset_monitor_interval: int
    // Maximum number of client caches per host, default 10
    max_client_cache_size_per_host: int
    // String Soft limit of the maximum length, in bytes default 1048576
    string_type_length_soft_limit_bytes: int
    // When using the odbc facade, if one of the columns in the odbc source table is of type HLL, CHAR, or VARCHAR, and the column value is longer than this value, the value is increaseddefault 65535
    big_column_size_buffer: int
    // When using the odbc facade, if the odbc source table has a column type other than HLL, CHAR, or VARCHAR, and the column value length exceeds this value, increase the value default 100
    small_column_size_buffer: int
    // Soft limit of the maximum length of the SONB type, in bytes default 1048576
    jsonb_type_length_soft_limit_bytes: int
    // Maximum number of query requests that can be processed on a single node default 4096
    fragment_pool_queue_size: int
    // Query the number of threads. By default, a minimum of 64 threads can be started. default 64
    fragment_pool_thread_num_min: int
    // A maximum of 512 threads can be dynamically created for subsequent query requests. default 2048
    fragment_pool_thread_num_max: int
    // When performing HashJoin, BE will adopt dynamic partition clipping to push the join condition to OlapScanner. default 90
    doris_max_pushdown_conjuncts_return_rate: int
    // This command is used to limit the maximum number of scan keys that can be split by the scan node in a query request. default 48
    doris_max_scan_key_num: int
    // The BE splits the same ScanRange into multiple scanranges when scanning data.default 524288
    doris_scan_range_row_count: int
    // The length of the cache queue of RowBatch between TransferThread and OlapScanner. default 1024
    doris_scanner_queue_size: int
    // The maximum number of rows of data returned per scan thread in a single execution default 16384
    doris_scanner_row_num: int
    // The maximum number of bytes of data returned per scan thread in a single execution default 10485760
    doris_scanner_row_bytes: int
    // Scanner Queue length of the thread pool. default 102400
    doris_scanner_thread_pool_queue_size: int
    // Scanner Thread pool Number of threads. default 48
    doris_scanner_thread_pool_thread_num: int
    // Remote scanner Maximum number of threads in a thread pool. default 512
    doris_max_remote_scanner_thread_pool_thread_num: int
    // Whether to prefetch HashBuket when using PartitionedHashTable for aggregation and join computation default true
    enable_prefetch: bool
    // Specifies whether to use the square probe to resolve Hash conflicts when Hash conflicts occur when PartitionedHashTable is used. default true
    enable_quadratic_probing: bool
    // ExchangeNode Indicates the Buffer queue size (unit: byte). default 10485760
    exchg_node_buffer_size_bytes: int
    // Used to limit the maximum number of criteria that can be pushed down to the storage engine for a single column in a query request. default 1024
    max_pushdown_conditions_per_column: int
    // Maximum parallelism of OlapTableSink to send batch data, default 5
    max_send_batch_parallelism_per_job: int
    // The maximum amount of data read by each OlapScanner default 1024
    doris_scan_range_max_mb: int
    // Shut down an automatic compaction task default false
    disable_auto_compaction: bool
    // Whether to enable column compaction default true
    enable_vertical_compaction: bool
    // The number of columns that compacts a group when a column compaction occurs default 5
    vertical_compaction_num_columns_per_group: int
    // The maximum amount of memory that a row_source_buffer can use when compaction occurs in columns, in MB.default 200
    vertical_compaction_max_row_source_memory_mb: int
    // The maximum number of segment files that a column compaction produces, in bytes default 268435456
    vertical_compaction_max_segment_size: int
    // Enables compaction of ordered data default true
    enable_ordered_data_compaction: bool
    // compaction: The minimum segment size, in bytes, that compacts a ordered data compaction.default 10485760
    ordered_data_compaction_min_segment_size: int
    // Base Compaction Maximum number of threads in a thread pool.default 4
    max_base_compaction_threads: int
    // The minimum interval between compaction operations default 10(ms)
    generate_compaction_tasks_interval_ms: int
    // One of the BaseCompaction triggers is a limit on the Cumulative file number to be reached default 5
    base_compaction_min_rowset_num: int
    // One of the BaseCompaction triggers is that the Cumulative file size is proportional to the Base file size.default 0.3(30%)
    base_compaction_min_data_ratio: float
    // The maximum number of "permits" that any compaction task can hold to limit the amount of memory that any compaction can consume.default 10000
    total_permits_for_compaction_score: int
    // The cumulative compaction results in a total disk size of the rowset that exceeds this configuration size, and the rowset is used by the base compaction. The unit is m bytes. default 1024
    compaction_promotion_size_mbytes: int
    // When the total disk size of the cumulative compaction output rowset exceeds the configured proportion of the base version rowset, the rowset is used by the base compaction.default 0.05(5%)
    compaction_promotion_ratio: float
    // If the total disk size of the Cumulative compaction output rowset is less than the configured size, the rowset will not be subjected to any base compaction and the cumulative compaction process will continue. The unit is m bytes.default 64
    compaction_promotion_min_size_mbytes: int
    //  cumulative compaction merges by level policy only when the total disk size of the rowset to be merged is greater than the cumulative compaction. If it is less than this configuration, the merge is performed directly. The unit is m bytes.default 64
    compaction_min_size_mbytes: int
    // Identifies the storage format selected by BE by default. The configurable parameters are "ALPHA" and "BETA". default BETA
    default_rowset_type: string
    // cumulative compaction policy: Create a minimum increment to the number of files default 5
    cumulative_compaction_min_deltas: int
    // cumulative compaction policy: Create a maxmum increment to the number of files default 1000
    cumulative_compaction_max_deltas: int
    // Print the threshold of a base compaction trace, in seconds default 10
    base_compaction_trace_threshold: int
    // Print the threshold of the cumulative compaction trace, in seconds default 2
    cumulative_compaction_trace_threshold: int
    // The number of compaction tasks that can be executed concurrently per disk (HDD).default 4
    compaction_task_num_per_disk: int
    // The number of compaction tasks that can be executed concurrently per high-speed disk (SSD).default 8
    compaction_task_num_per_fast_disk: int
    // How many successive rounds of cumulative compaction does the producer of a compaction task produce after each cumulative compaction task? default 9
    cumulative_compaction_rounds_for_each_base_compaction_round: int
    // Configure the merge policies for the cumulative compaction phase. Two merge policies are implemented, num_based and size_based default size_based
    cumulative_compaction_policy: string
    // Cumulative Compaction Maximum number of threads in the thread pool. default 10
    max_cumu_compaction_threads: int
    // Create a segment compaction when importing to reduce the number of segments and avoid a -238 write error default true
    enable_segcompaction: bool
    // When the number of segments exceeds this threshold, a segment compaction is triggered or When the number of rows in a segment exceeds this size, it is compact when the segment compacts  default 10
    segcompaction_batch_size: int
    // When the number of rows in a segment exceeds this size, it is compact when the segment compacts or The number of rows of a single original segment allowed when a segment compaction task occurs. Any segment that compacts will be skipped. default 1048576
    segcompaction_candidate_max_rows: int
    // The size of a single raw segment allowed in a segment compaction task (in bytes). If a segment compacts, it will be skipped. default 104857600
    segcompaction_candidate_max_bytes: int
    // The total number of rows of the original segment that a single segment compaction task allows. default 1572864
    segcompaction_task_max_rows: int
    // The total size of the original segment (in bytes) allowed when a single segment compaction task occurs. default 157286400
    segcompaction_task_max_bytes: int
    // segment compaction thread pool size. default 5
    segcompaction_num_threads: int
    // Close trace logs that create compactions If set to true, cumulative_compaction_trace_threshold and base_compaction_trace_threshold have no effect.default true
    disable_compaction_trace_log: bool
    // Select the interval between rowsets to merge, in seconds default 86400
    pick_rowset_to_compact_interval_sec: int
    // Single Replica Compaction Maximum number of threads in the thread pool. default 10
    max_single_replica_compaction_threads: int
    // Minimum interval for updating peer replica infos default 60(s)
    update_replica_infos_interval_seconds: int
    // Whether to enable stream load operation records default false
    enable_stream_load_record: bool
    // Used for mini load. The mini load data file will be deleted after this time default 4 (hours)
    load_data_reserve_hours: int
    // Number of import threads for processing high-priority tasks default 3
    push_worker_count_high_priority: int
    // Import the number of threads used to process NORMAL priority tasks default 3
    push_worker_count_normal_priority: int
    // Whether to enable the single copy data import function default true
    enable_single_replica_load: bool
    // The load error log will be deleted after this time default 48 (hours)
    load_error_log_reserve_hours: int
    // Maximum percentage of memory occupied by all import threads on a single node default 50 (%)
    load_process_max_memory_limit_percent: int
    // soft limit indicates the upper limit of the memory imported from a single node. default 50 (%)
    load_process_soft_mem_limit_percent: int
    // The thread pool size of the routine load task. default 10
    routine_load_thread_pool_size: int
    // RPC timeout period for communication between the Master copy and Slave copy in the single copy data import function. default 60
    slave_replica_writer_rpc_timeout_sec: int
    // Used to limit the number of segments in the newly generated rowset during import. default 200
    max_segment_num_per_rowset: int
    // The number of flush threads allocated per storage path for high-level import tasks. default 1
    high_priority_flush_thread_num_per_store: int
    // Number of data consumer caches used by routine load. default 10
    routine_load_consumer_pool_size: int
    // First-class multi-table uses this configuration to indicate how many data to save before planning. default 200
    multi_table_batch_plan_threshold: int
    // In the single copy data import function, the Slave copy downloads data files from the Master copy through HTTP. default 64
    single_replica_load_download_num_workers: int
    // When the timeout time of an import task is less than this threshold, Doris will consider it to be a high-performing task. default 120
    load_task_high_priority_threshold_second: int
    // Minimum timeout time of each rpc in the load job. default 20
    min_load_rpc_timeout_ms: int
    // If the dependent kafka version is below 0.10.0.0, the value should be set to false. default true
    kafka_api_version_request: bool
    // If the dependent kafka version is below 0.10.0.0, when the kafka_api_version_request value is false, the fallback version kafka_broker_version_fallback value will be used. Valid values are: 0.9.0.x, 0.8.x.y. default 0.10.0.0
    kafka_broker_version_fallback: string
    // The maximum number of consumers in a data consumer group for routine load. default 3
    max_consumer_num_per_group: int
    // Used to limit the maximum amount of data allowed in a Stream load import in csv format. default 10240(M)
    streaming_load_max_mb: int
    // Used to limit the maximum amount of data allowed in a single Stream load import of data format json. Unit MB. default 100
    streaming_load_json_max_mb: int
    // Number of threads that execute data deletion tasks default 3
    delete_worker_count: int
    // The number of threads used to clean up transactions default 1
    clear_transaction_task_worker_count: int
    // Number of threads used to perform clone tasks default 3
    clone_worker_count: int
    // The number of threads executing the thrift server service on the BE indicates the number of threads that can be used to execute FE requests. default 64
    be_service_threads:int
    // Number of download threads default 1
    download_worker_count: int
    // Delete the number of threads for the tablet default 3
    drop_tablet_worker_count: int
    // The number of threads per store used to refresh the memory table default 2
    flush_thread_num_per_store: int
    // Controls the number of threads per kernel running work. default 3
    num_threads_per_core: int
    // The maximum number of threads per disk is also the maximum queue depth per disk default 0
    num_threads_per_disk: int
    // Number of threads for the slave copy to synchronize data from the Master copy on each BE node, used for the single copy data import function. default 64
    number_slave_replica_download_threads: int
    // Number of threads in valid version default 8
    publish_version_worker_count: int
    // Maximum number of threads for uploading files default 1
    upload_worker_count: int
    // Default number of webserver worker threads default 48
    webserver_num_workers: int
    // SendBatch Number of threads in the thread pool. default 64
    send_batch_thread_pool_thread_num: int
    // SendBatch Queue length of the thread pool. default 102400
    send_batch_thread_pool_queue_size: int
    // Number of threads for creating snapshots default 5
    make_snapshot_worker_count: int
    // Number of threads that release snapshots default 5
    release_snapshot_worker_count: int
    // Whether to disable the memory cache pool default false
    disable_mem_pools: bool
    // Clean up pages that may be saved by the buffer pool default 50(%)
    buffer_pool_clean_pages_limit: string
    //  The maximum allocated memory in the buffer pool   default 20(%)
    buffer_pool_limit: string
    // The reserved bytes limit of Chunk Allocator, usually set as a percentage of mem_limit. default 20(%)
    chunk_reserved_bytes_limit: string
    // Whether to use linux memory for large pages default false
    madvise_huge_pages: bool
    // max_memory_cache_batch_count batch_size row is cached default 20
    max_memory_sink_batch_count: int
    // Maximum collation memory default 16
    memory_max_alignment: int
    // Whether to allocate memory using mmap default false
    mmap_buffers: bool
    // memtable memory statistics refresh period (milliseconds) default 100(ms)
    memtable_mem_tracker_refresh_interval_ms: int
    // The size of the buffer used to receive data when the cache is downloaded. default 10485760
    download_cache_buffer_size: int
    // If the number of rows in a page is less than this value, zonemap is not created to reduce data bloat default 20
    zone_map_row_num_threshold: int
    // If the number of rows in a page is less than this value, zonemap is not created to reduce data bloat. Hook TCmalloc new/delete, currently counting thread local memtrackers in Hook. default true
    enable_tcmalloc_hook: bool
    // Control the recovery of tcmalloc. If the configuration is performance, doris will release the memory in the tcmalloc cache when the memory usage exceeds 90% of mem_limit. If the configuration is compact, the memory usage exceeds 50% of mem_limit. doris frees the memory in the tcmalloc cache. default performance
    memory_mode: string
    // System/proc/meminfo/MemAvailable low water level, the largest unit of byte, the default 1.6 G, default 1717986918
    max_sys_mem_available_low_water_mark_bytes: int
    // The maximum memory that a single schema change task can occupy default 2147483648 (2GB)
    memory_limitation_per_thread_for_schema_change_bytes: int
    // TCMalloc Hook consume/release MemTracker minimum length,default 1048576
    mem_tracker_consume_min_size_bytes: int
    // File handle cache clearing interval, used to clear long-unused file handles. It is also the interval for clearing the Segment Cache. default 1800(s)
    cache_clean_interval: int
    // Minimum read buffer size default 1024
    min_buffer_size: int
    // The size of the buffer before brushing default 104857600
    write_buffer_size: int
    // Cache size used to read files on hdfs or object storage. default 16(MB)
    remote_storage_read_buffer_mb: int
    // The type of the cache file. whole_file_cache: downloads the entire segment file; sub_file_cache: slices the segment file into multiple files. If this parameter is set to ", files are not cached. Set this parameter when you need to cache files default ""
    file_cache_type: string
    // Retention time of the cache file, in seconds default 604800 (a week)
    file_cache_alive_time_sec: int
    // The cache occupies the disk size. Once this setting is exceeded, the cache that has not been accessed for the longest time will be deleted. If it is 0, the size is not limited. default 0
    file_cache_max_size_per_disk: int
    // Cache file Maximum file size when sub_file_cache is used, default 104857600 (100MB)
    max_sub_cache_file_size: int
    // DownloadCache Specifies the number of threads in the thread pool. default 48
    download_cache_thread_pool_thread_num: int
    // DownloadCache Specifies the number of threads in the thread pool. default 102400
    download_cache_thread_pool_queue_size: int
    // Cache file clearing interval, default 43200 (12 hours)
    generate_cache_cleaner_task_interval_sec: int
    // Whether to enable the thread to reclaim scan data default true
    path_gc_check: bool
    // Check interval for reclaiming scan data threads default 86400 (s)
    path_gc_check_interval_second: int
    // default 1000
    path_gc_check_step: int
    // default 10(ms)
    path_gc_check_step_interval_ms: int
    // default 86400
    path_scan_interval_second: int
    // This configuration is used for context gc thread scheduling cycles default 5 (min)
    scan_context_gc_interval_min: int
    // Configures how many rows of data to contain in a single RowBlock. default 1024
    default_num_rows_per_column_file_block: int
    // Whether to use page cache for index caching. This configuration takes effect only in BETA format default false
    disable_storage_page_cache: bool
    // Interval for checking disk status default 5 (s)
    disk_stat_monitor_interval: int
    // For each io buffer size, the maximum number of buffers that IoMgr will retain ranges from 1024B to 8MB buffers, with a maximum of about 2GB buffers. default 128
    max_free_io_buffers: int
    // Maximum interval for disk garbage cleanup  default 3600 (s)
    max_garbage_sweep_interval: int
    // The storage engine allows the percentage of damaged hard disks. If the percentage of damaged hard disks exceeds the threshold, the BE automatically exits. default 0
    max_percentage_of_error_disk: int
    // The read size is the read size sent to the os. default 8388608
    read_size: int
    // Minimum interval for disk garbage cleanup default 180(s)
    min_garbage_sweep_interval: int
    // pprof profile save directory default ${DORIS_HOME}/log
    pprof_profile_dir: string
    // The directory where SmallFileMgr downloaded files are stored default {DORIS_HOME}/lib/small_file/
    small_file_dir: string
    // udf function directory default ${DORIS_HOME}/lib/udf
    user_function_dir: string
    // The minimum storage space that should be left in the data directory, default 1073741824
    storage_flood_stage_left_capacity_bytes: int
    // The storage_flood_stage_usage_percent and storage_flood_stage_left_capacity_bytes configurations limit the maximum disk capacity usage of the data directory. default 90(%)
    storage_flood_stage_usage_percent: float
    // Number of threads to clone default 1
    storage_medium_migrate_count: int
    // Cache stores page size default 20(%)
    storage_page_cache_limit: string
    // Fragment size of StoragePageCache, the value is 2^n (n=0,1,2,...) . default 16
    storage_page_cache_shard_size: int
    // Percentage of index page cache in total page cache, the value is [0, 100]. default 10
    index_page_cache_percentage: int
    // Max number of segment cache (the key is rowset id) entries. -1 is for backward compatibility as fd_number * 2/5. Default value: -1
    segment_cache_capacity: int
    // Used to check incompatible old format strictly Default value: true
    storage_strict_check_incompatible_old_format: bool
    // Whether the storage engine opens sync and keeps it to the disk Default value: false
    sync_tablet_meta: bool
    // The maximum duration of unvalidated data retained by the storage engine Default value: 1800 (s)
    pending_data_expire_time_sec: int
    // t is used to decide whether to delete the outdated merged rowset if it cannot form a consistent version path. Default value: false
    ignore_rowset_stale_unconsistent_delete: bool
    // Description: Number of worker threads for BE to create a tablet Default value: 3
    create_tablet_worker_count: int
    // The number of worker threads to calculate the checksum of the tablet Default value: 1
    check_consistency_worker_count: int
    // Limit the number of versions of a single tablet. Default value: 500
    max_tablet_version_num: int
    // Number of tablet write threads Default value: 16
    number_tablet_writer_threads: int
    // tablet_map_lock fragment size, the value is 2^n, n=0,1,2,3,4, this is for better tablet management Default value: 4
    tablet_map_shard_size: int
    //  TabletMeta Checkpoint Interval of thread polling Default value: 600 (s)
    tablet_meta_checkpoint_min_interval_secs: int
    // The minimum number of Rowsets for storing TabletMeta Checkpoints Default value: 10
    tablet_meta_checkpoint_min_new_rowsets_num: int
    // Update interval of tablet state cache Default value:300 (s)
    tablet_stat_cache_update_interval_second: int
    // Description: It is used to control the expiration time of cleaning up the merged rowset version. Default value: 300
    tablet_rowset_stale_sweep_time_sec: int
    // Update interval of tablet state cache Default value: 60
    tablet_writer_open_rpc_timeout_sec: int
    // Used to ignore brpc error '[E1011]The server is overcrowded' when writing data. Default value: false
    tablet_writer_ignore_eovercrowded: bool
    // The lifetime of TabletsChannel. If the channel does not receive any data at this time, the channel will be deleted. Default value: 1200
    streaming_load_rpc_max_alive_time_sec: int
    //  The number of threads making schema changes Default value: 3
    alter_tablet_worker_count: int
    // The number of threads making index change Default value: 3
    alter_index_worker_count: int
    // It is used to decide whether to ignore errors and continue to start be in case of tablet loading failure Default value: false
    ignore_load_tablet_failure: bool
    // The interval time for the agent to report the disk status to FE Default value: 60 (s)
    report_disk_state_interval_seconds: int
    // Result buffer cancellation time Default value: 300 (s)
    result_buffer_cancelled_interval_time: int
    // Snapshot file cleaning interval. Default value:172800 (48 hours)
    snapshot_expire_time_sec: int
    // enable to use Snappy compression algorithm for data compression when serializing RowBatch Default value: true
    compress_rowbatches: bool
    // The maximum size of JVM heap memory used by BE, which is the -Xmx parameter of JVM Default value: 1024M
    jvm_max_heap_size: string
    //  Storage directory of BE log data Default value: ${DORIS_HOME}/log
    sys_log_dir: string
    // The size of the log split, one log file is split every 1G Default value: SIZE-MB-1024
    sys_log_roll_mode: string
    //  Number of log files kept Default value: 10
    sys_log_roll_num: int
    // Log display level, used to control the log output at the beginning of VLOG in the code Default value: 10
    sys_log_verbose_level: int
    // Log printing module, writing olap will only print the log under the olap module Default value: empty
    sys_log_verbose_modules: string
    // log level of AWS SDK,Default value: 3
    aws_log_level: int
    // The log flushing strategy is kept in memory by default Default value: empty
    log_buffer_level: string
    // The interval time for the agent to report the olap table to the FE Default value: 60 (s)
    report_tablet_interval_seconds: int
    // The interval time for the agent to report the task signature to FE Default value: 10 (s)
    report_task_interval_seconds: int
    // Update rate counter and sampling counter cycle Default value: 500 (ms)
    periodic_counter_update_period_ms: int
    // If set to true, the metric calculator will run to collect BE-related indicator information, if set to false, it will not run Default value: true
    enable_metric_calculator: bool
    //  User control to turn on and off system indicators. Default value: true
    enable_system_metrics: bool
    // Used for forward compatibility, will be removed later. Default value: true
    enable_token_check: bool
    // Max number of txns for every txn_partition_map in txn manager, this is a self protection to avoid too many txns saving in manager Default value: 2000
    max_runnings_transactions_per_txn_map: int
    // Maximum download speed limit Default value: 50000 (kb/s)
    max_download_speed_kbps: int
    // Download time limit Default value: 300 (s)
    download_low_speed_time: int
    // Minimum download speed Default value: 50 (KB/s)
    download_low_speed_limit_kbps: int
    // Description: Cgroups assigned to doris Default value: empty
    doris_cgroups: string
    // the increased frequency of priority for remaining tasks in BlockingPriorityQueue Default value: 512
    priority_queue_remaining_tasks_increased_frequency: int
    // Default dirs to put jdbc drivers. Default value: ${DORIS_HOME}/jdbc_drivers
    jdbc_drivers_dir: string
    // Whether enable simdjson to parse json while stream load Default value: true
    enable_simdjson_reader: bool
    // If true, when the process does not exceed the soft mem limit, the query memory will not be limited; Default value: true
    enable_query_memory_overcommit: bool
    // The storage directory for files queried by local table valued functions. Default value: ${DORIS_HOME}
    user_files_secure_path: string
    //  The batch size for sending data by brpc streaming client Default value: 262144
    brpc_streaming_client_batch_bytes: int
    // In cloud native deployment scenario, BE will be add to cluster and remove from cluster very frequently. User's query will fail if there is a fragment is running on the shuting down BE. Default value: 120
    grace_shutdown_wait_seconds: int
    // BE Whether to enable the use of java-jni.  Default value: true
    enable_java_support: bool
}
configuration: #DorisbeParameter & {
}