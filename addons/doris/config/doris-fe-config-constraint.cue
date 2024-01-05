#DorisParameter: {
    // If using a third-party deployment manager to deploy Doris optionals：1.disable: No deployment manager is available 2.k8s：Kubernetes 3.ambari：Ambari 4.local: local file (for testing or Boxer2 BCC version)
    enable_deploy_manager: string
    // This configuration is used for the k8s deployment environment. When enable_fqdn_mode is true, changing the ip of the rebuild pod for be is allowed.
    enable_fqdn_mode: bool
    // Declare a selection policy for servers that have a lot of ip. Note that at most one ip should match this list. This is a list in semicolon-separated format, using CIDR notation, such as 10.10.10.0/24. If no ip address matches this rule, a random IP address is selected. default ''
    priority_networks: string
    // Dynamic configuration Modifies the directory
    custom_config_dir: string
    // This configuration is used to control whether the system drops the BE after it has been Decommission successfully.
    drop_backend_after_decommission: bool
    // set current date for java_opts
    CUR_DATE: string
    // log dir
    LOG_DIR: string
    // java_opts
    JAVA_OPTS: string
    // java_opts_jdk_9
    JAVA_OPTS_FOR_JDK_9: string
    // system log level
    sys_log_level: string
    // system log mode
    sys_log_mode: string
    // http port
    http_port: int
    // rpc port
    rpc_port: int
    // query port
    query_port: int
    // edit log port
    edit_log_port: int
    // The Doris metadata will be saved here
    meta_dir: string
    // Set the tryLock timeout for metadata lock
    catalog_try_lock_timeout_ms: int
    // If this parameter is set to true, FE will start in BDBJE debugging mode. You can view related information on the Web page System->bdbje.
    enable_bdbje_debug_mode: bool
    // Set the maximum acceptable clock deviation between the non-active FE host and the active FE host
    max_bdbje_clock_delta_ms: int
    // If true, FE will reset the bdbje replication group (i.e. remove all optional node information) and should start as Master
    metadata_failure_recovery: bool
    // The maximum number of TXNS that bdbje can roll back when trying to rejoin a group
    txn_rollback_limit?: int & >=1 & <=65535 | *100
    // Metadata is synchronously written to multiple fe FeEs. This parameter controls the timeout period for Master FE to wait for Follower FE to send an ack
    bdbje_replica_ack_timeout_second: int
    // The number of threads that process grpc events in grpc threadmgr
    grpc_threadmgr_threads_nums: int
    // lock timeout for the bdbje operation If there are many LocktimeOutExceptions in the FE WARN log, you can try to increase this value
    bdbje_lock_timeout_second: int
    // The bdbje heartbeat between the master and the fe times out default 30s
    bdbje_heartbeat_timeout_second: int
    // Duplicate ack policy of bdbje default SIMPLE_MAJORITY optionals:ALL, NONE, SIMPLE_MAJORITY
    replica_ack_policy: string
    // fe FE synchronization policy of bdbje default SYNC optionals:SYNC, NO_SYNC, WRITE_NO_SYNC
    replica_sync_policy: string
    // Master FE bdbje synchronization policy
    master_sync_policy: string
    // Used to limit the maximum disk space that bdbje can keep for files. default 1073741824
    bdbje_reserved_disk_bytes: int
    // If true, the non-primary FE will ignore the metadata delay gap between the primary FE and itself, even if the metadata delay gap exceeds meta_delay_toleration_second. The non-active FE still provides read services
    ignore_meta_check: bool
    // If the metadata delay interval exceeds meta_delay_toleration_second, the non-primary FE will stop providing service default 300s
    meta_delay_toleration_second: int
    // Master FE will save image every edit_log_roll_num meta journals. default 50000
    edit_log_roll_num: int
    // If set to true, the checkpoint thread will create checkpoints regardless of jvm memory usage percentage
    force_do_metadata_checkpoint: bool
    // If the percentage of jvm memory usage (heap or old memory pool) exceeds this threshold, the checkpoint thread will not work to avoid OOM.default 60(60%)
    metadata_checkpoint_memory_threshold: int
    // This parameter is used to set the maximum number of metadata with the same name in the recycle bin. If the number exceeds the maximum, the earliest metadata will be completely deleted and cannot be recovered. 0 indicates that the object with the same name is not reserved. < 0 indicates no restriction default 3
    max_same_name_catalog_trash_num: int
    // If the nodes (FE or BE) have the same cluster id, they are considered to belong to the same Doris cluster. The Cluster id is usually a random integer generated when the primary FE is first started. You can also specify one default -1
    cluster_id: int
    // Store the block queue size for heartbeat tasks in heartbeat_mgr.default 1024
    heartbeat_mgr_blocking_queue_size: int
    // Number of threads processing heartbeat events in heartbeat mgr. default 8
    heartbeat_mgr_threads_num: int
    // The multi-cluster feature will be deprecated in version 0.12, and setting this configuration to true will disable all actions related to the cluster feature default true
    disable_cluster_feature: bool
    // If using the k8s deployment manager locally, set it to true and prepare the certificate file default false
    with_k8s_certs: bool
    // This will be removed later for forward compatibility. Check the token when downloading the image file. default true
    enable_token_check: bool
    // Whether to enable the multi-label function of a single BE default false
    enable_multi_tags: bool
    // Doris FE queries the connection port through Arrow Flight SQL default -1
    arrow_flight_sql_port: int
    // FE https port: All current FE https ports must be the same default 8050
    https_port: int
    // FE https Indicates the https flag bit. false indicates that http is supported. true indicates that both http and https are supported and http requests are automatically redirected to HTTPS. If enable_https is true, You need to configure ssl certificate information in fe.conf default false
    enable_https: bool
    // If set to true, doris establishes an SSL-based encrypted channel with the mysql service. default true
    enable_ssl: bool
    // Maximum number of connections per FE default 1024
    qe_max_connection: int
    // Doris will check whether the compiled and running Java versions are compatible, and if not, will throw an exception message that the Java version does not match, and terminate the startup default true
    check_java_version: bool
    // This configuration indicates the service model used by the Thrift service of FE. The type is string and case - insensitive. optionals: 1.SIMPLE 2.THREADED 3.THREAD_POOL
    thrift_server_type: string
    // Maximum number of working threads of Thrift Server default 4096
    thrift_server_max_worker_threads: int
    // Thrift server backlog_num when you expand the backlog_num, you should ensure that its value is greater than the Linux/proc/sys/net/core/somaxconn configuration default 1024
    thrift_backlog_num: int
    //Connection timeout and socket timeout configuration of the thrift server default 0
    thrift_client_timeout_ms: int
    // Whether to send the query plan structure in a compressed format. default true
    use_compact_thrift_rpc: bool
    // Used to set the initial stream window size of the GRPC client channel and also to set the maximum message size. This value may need to be increased when the result set is large default 1G
    grpc_max_message_size_bytes: string
    // The maximum number of threads to process a task in mysql. default 4096
    max_mysql_service_task_threads_num: int
    // Number of threads handling I/O events in mysql. default 4
    mysql_service_io_threads_num: int
    // Mysql nio server backlog_num when you zoom in the backlog_num, you should also enlarge the Linux/proc/sys/net/core/somaxconn the values in the file default 1024
    mysql_nio_backlog_num: int
    // Default timeout for Broker rpc default 10000(10s)
    broker_timeout_ms: int
    // Timeout duration of rpc request sent by FE to BackendService of BE, in milliseconds.Default value: 60000
    backend_rpc_timeout_ms: int
    // Default: 3600 (1 hour)
    max_backend_down_time_second: int
    // Disables the BE blacklist function. After this function is disabled, the BE will not BE added to the blacklist if the query request to the BE fails. Default false
    disable_backend_black_list: bool
    // Maximum allowable number of heartbeat failures of a BE node. If the number of consecutive heartbeat failures exceeds this value, the BE status is set to dead default 1
    max_backend_heartbeat_failure_tolerance_count: int
    // This configuration is used to try to skip proxies when accessing bos or other cloud storage through proxies Default false
    enable_access_file_without_broker: bool
    // This configuration determines whether to resend a proxy task when the creation time of the proxy task is set. ReportHandler can resend a proxy task if and only if the current time minus the creation time is greater than agent_task_task_resend_wait_time_ms.default 5000
    agent_task_resend_wait_time_ms: int
    // The maximum number of threads in the agent task thread pool that process the agent task. default 4096
    max_agent_task_threads_num: int
    // Timeout period of asynchronous remote fragment execution. default 30000 (ms)
    remote_fragment_exec_timeout_ms: int
    // Cluster token for internal authentication. default ''
    auth_token: string
    // HTTP Server V2 is implemented by SpringBoot and uses a front-end separation architecture. Users will not be able to use the new front-end UI interface until httpv2 is enabled Default: true by default since the official 0.14.0 release, false by default before
    enable_http_server_v2: bool
    // Default: true by default since the official 0.14.0 release, false by default before the base path is the URL prefix of all API paths. Some deployment environments need to configure additional base paths to match resources. This Api returns the path configured in Config.http_api_extra_base_path. The default value is blank, indicating that the value is not set.
    http_api_extra_base_path: string
    // default 2
    jetty_server_acceptors: int
    // default 4
    jetty_server_selectors: int
    // workers thread pools are not configured by default. Set them as required default 0
    jetty_server_workers: int
    // This is the maximum number of bytes that can be uploaded by the put or post method. The default value is 100MB (100*1024*1024)
    jetty_server_max_http_post_size: int
    // http header size Indicates the configuration parameter Default value: 1048576 (1M)
    jetty_server_max_http_header_size: int
    // When the user attribute max_query_instances is less than or equal to 0, this configuration is used to limit the number of query instances that a single user can use at a time. If this parameter is less than or equal to 0, it indicates no limit.default -1
    default_max_query_instances: int
    // Query retry times default 1
    max_query_retry_time: int
    // It is used to limit the maximum number of partitions that can be created when creating a dynamic partition table to avoid creating too many partitions at a time. The number is determined by "Start" and "end" in the dynamic partition parameters. default 500
    max_dynamic_partition_num: int
    //  Whether to enable dynamic partition scheduling default true
    dynamic_partition_enable: bool
    // Check the frequency of dynamic partitioning deafult 600(s) 10min
    dynamic_partition_check_interval_seconds: int
    // This parameter limits the maximum number of partitions that can be created when a partition table is created in batches to prevent too many partitions from being created at a time.default 4096
    max_multi_partition_num: int
    // Use this parameter to set the prefix of the partition name of multi partition. This parameter takes effect only for multi partition, not for dynamic partitions. The default prefix is p_.
    multi_partition_name_prefix: string
    // Time to update the global partition information in memory default 300(s)
    partition_in_memory_update_interval_secs: int
    // Whether to enable concurrent update default false
    enable_concurrent_update: bool
    // 0: The table name is case sensitive and stored as specified. 1: The table name is stored in lowercase and case insensitive. 2: Table names are stored as specified, but are compared in lower case. default 0
    lower_case_table_names: int
    // Used to control the maximum table name length default 64
    table_name_length_limit: int
    // If set to true, the SQL query result set is cached.default true
    cache_enable_sql_mode: bool
    // If set to true, FE will fetch data from the BE cache, and this option is suitable for real-time updates of some partitions. default true
    cache_enable_partition_mode: bool
    // Sets the maximum number of rows that can be cached default 3000
    cache_result_max_row_count: int
    // Sets the maximum size of data that can be cached, in Bytes default 31457280
    cache_result_max_data_size: int
    // The minimum interval at which results are cached from the previous version. This parameter distinguishes between offline updates and real-time updates default 900
    cache_last_version_interval_second: int
    // Whether to add a delete flag column when creating a unique table default false
    enable_batch_delete_by_default: bool
    // Used to limit the number of Predicate elements in a delete statement default 1024
    max_allowed_in_element_num_of_delete: int
    // Controls the Rollup job concurrency limit default 1
    max_running_rollup_job_num_per_table: int
    // This will limit the maximum recursion depth of the hash distribution trimmer.  default 100
    max_distribution_pruner_recursion_depth: int
    // If set to true, Planner will try to select a copy of the tablet on the same host as the previous one default false
    enable_local_replica_selection: bool
    // When the enable_local_replica_selection parameter is used, the non-local replica service is used to query data when the local replica is unavailable.default false
    enable_local_replica_selection_fallback: bool
    // Limit the expr tree depth. Exceeding this limit may result in excessively long analysis times when a db read lock is held.default 3000
    expr_depth_limit: int
    // Limit the number of expr children in the expr tree. Exceeding this limit may result in excessively long analysis times when a database read lock is held. default 10000
    expr_children_limit: int
    // Used to define the serialization format for passing blocks between fragments. optionals: max_be_exec_version min_be_exec_version
    be_exec_version: string
    // This parameter is used to set the maximum number of profiles to save the query. default 100
    max_query_profile_num: int
    // The minimum interval between two release operations default 10(ms)
    publish_version_interval_ms: int
    // The maximum waiting time for all published versions of a transaction to complete default 30(s)
    publish_version_timeout_second: int
    // colocate join PlanFragment instance 的 memory_limit = exec_mem_limit / min (query_colocate_join_memory_limit_penalty_factor, instance_num) default 1
    query_colocate_join_memory_limit_penalty_factor: int
    // For tables of the AGG model only, when the variable is true, the rewriting is based on whether c1 is a bitmap or hll. count distinct (c1) default true
    rewrite_count_distinct_to_bitmap_hll: bool
    // Whether to enable vectorization import default true
    enable_vectorized_load: bool
    // Whether to enable a new file scan node default true
    enable_new_load_scan_node: bool
    // The maximum percentage of data that can be filtered (for reasons such as data irregularities). The default value is 0, indicating strict mode, as long as one piece of data is filtered out, the entire import fails default 0
    default_max_filter_ratio: int
    // This configuration is mainly used to control the number of concurrent imports of the same DB. default 1000
    max_running_txn_num_per_db: int
    // If set to true, insert stmt handling errors will still return a label to the user. Users can use this tag to check the status of the import job. The default value is false, indicating that the insert operation encountered an error, and the exception is directly thrown to the user client without the import label. default false
    using_old_load_usage_pattern: bool
    // If this is set to true, all pending import jobs will fail when the start txn api is called; When the commit txn api is called, all ready import jobs fail; All submitted import jobs will await publication default false
    disable_load_job: bool
    // The maximum wait time for inserting all data before committing a transaction This is the timeout seconds of the command "commit" default 30(s)
    commit_timeout_second: int
    // The value can be PENDING, ETL, LOADING, or QUORUM_FINISHED. default 1000
    max_unfinished_load_job: int
    // This configuration is used to set the interval at which the value of the amount of data used by the database is updated default 300(s)
    db_used_data_quota_update_interval_secs: int
    // Whether to disable stream load display and clear stream load records from memory. default false
    disable_show_stream_load: bool
    // The default maximum number of recent stream load records that can be stored in memory default 5000
    max_stream_load_record_size: int
    // Gets the stream load record interval default 120
    fetch_stream_load_record_interval_second: int
    // The maximum number of bytes that a broker scanner program can process in a broker load job default 500*1024*1024*1024L (500G)
    max_bytes_per_broker_scanner: int
    // The default concurrency for broker load imports on a single node. default 1
    default_load_parallelism: int
    // broker scanner maximum number of concurrent requests.default 10
    max_broker_concurrency: int
    // The minimum number of bytes that a single broker scanner will read. Default value: 67108864L (64M)
    min_bytes_per_broker_scanner: int
    //  Automatically restore the period of Routine load default 5(s)
    period_of_auto_resume_min: int
    // As long as one BE fails, Routine Load cannot be automatically restored  default 0
    max_tolerable_backend_down_num: int
    // Maximum number of concurrent Routine Load tasks for each BE. default 5
    max_routine_load_task_num_per_be: int
    //  Maximum number of concurrent tasks in a Routine Load job default 5
    max_routine_load_task_concurrent_num: int
    // Maximum number of Routine Load jobs, including NEED_SCHEDULED, RUNNING, and PAUSE default 100
    max_routine_load_job_num: int
    // The default number of waiting jobs loaded by the routine load V2 version is an ideal number. default 100
    desired_max_waiting_jobs: int
    // hadoop cluster load is not recommended in the future. Set to true to disable this load mode. default false
    disable_hadoop_load: bool
    // Whether to temporarily enable spark load. The function is disabled by default This parameter was removed in version 1.2 and spark_load is enabled by default default false
    enable_spark_load: bool
    // Spark Load scheduler running interval. The default interval is 60 seconds default 60
    spark_load_checker_interval_second: int
    // Size of the loading load task execution program pool. default 10
    async_loading_load_task_pool_size: int
    //  pending load Task execution program pool size. default 10
    async_pending_load_task_pool_size: int
    // This configuration is only for compatibility with older versions, it has been replaced by async_loading_load_task_pool_size and will be removed later. default 10
    async_load_task_pool_size: int
    //  Whether to enable the single copy data import function. default false
    enable_single_replica_load: bool
    // Minimum timeout, applicable to all types of load default 1(s)
    min_load_timeout_second: int
    // Maximum timeout of stream load and mini load Default value: 259200 (3 days)
    max_stream_load_timeout_second: int
    // load Maximum timeout for all types of loads except stream load Default value: 259200 (3 days)
    max_load_timeout_second: int
    // Default stream load and mini load timeout times default 86400 * 3 (3 days)
    stream_load_default_timeout_second: int
    // Default stream load pre-commit timeout default 3600(s)
    stream_load_default_precommit_timeout_second: int
    // Default insert load timeout default 3600 (an hour)
    insert_load_default_timeout_second: int
    // The timeout period of mini load, which is not a stream load by default default 3600 (an hour)
    mini_load_default_timeout_second: int
    // Default timeout of Broker load default 14400 (four hours)
    broker_load_default_timeout_second: int
    // Default Spark import timeout period default 86400 (one day)
    spark_load_default_timeout_second: int
    // Hadoop import timeout default 86400*3 (tree day)
    hadoop_load_default_timeout_second: int
    // Load Maximum number of tasks. The default value is 0 default 0
    load_running_job_num_limit: int
    // Load Specifies the data size entered in the load job. The default value is 0 default 0
    load_input_size_limit_gb: int
    // NORMAL Priority Number of concurrent etl load jobs. default 10
    load_etl_thread_num_normal_priority: int
    // The number of concurrent etl load jobs with high priority. default 3
    load_etl_thread_num_high_priority: int
    // NORMAL Priority Number of concurrent suspended load jobs. default 10
    load_pending_thread_num_normal_priority: int
    // The number of concurrent high-priority suspended load jobs. default 3
    load_pending_thread_num_high_priority: int
    // Load scheduler run interval. The load job transfers its state from PENDING to LOADING to FINISHED. default 5(s)
    load_checker_interval_second: int
    // The maximum number of waiting seconds for a lagging node in the load default 300(s)
    load_straggler_wait_second: int
    // label_keep_max_second removes labels for completed or canceled load jobs, default 382483600 (tree day)
    label_keep_max_second: int
    // For some high frequency LOAD work, such as INSERT, STREAMING LOAD, ROUTINE_LOAD_TASK. If it expires, the completed job or task is deleted. default 43200 (12 hours)
    streaming_label_keep_max_second: int
    // The load label cleaner will run every label_clean_interval_second to clean up obsolete jobs. default 1*3600 (an hour)
    label_clean_interval_second: int
    // If the transaction is visible or aborted, the transaction will be cleared after transaction_clean_interval_second default 30
    transaction_clean_interval_second: int
    // The maximum interval between committing a transaction. default 10
    sync_commit_interval_second: int
    // Check the running status of data synchronization jobs default 10
    sync_checker_interval_second: int
    // The maximum number of threads in the data synchronization job thread pool. default 10
    max_sync_task_threads_num: int
    // The minimum number of events required to commit a transaction. default 10000
    min_sync_commit_size: int
    // The minimum data size required to commit a transaction.default 15*1024*1024 (15M)
    min_bytes_sync_commit: int
    // The maximum number of threads in the data synchronization job thread pool. default 10
    max_bytes_sync_commit: int
    // Whether to allow the outfile function to export results to the local disk default fales
    enable_outfile_to_local: bool
    // The number of tablets per export query plan default 5
    export_tablet_num_per_task: int
    // Default timeout period of the export job default 2*3600 (2 hours)
    export_task_default_timeout_second: int
    // Concurrency limit for running export jobs. The default value is 5,0 indicates no limit default 5
    export_running_job_num_limit: int
    // Export the run interval of the inspector default 5
    export_checker_interval_second: int
    // The maximum size of a system log and an audit log default 1024 (1G)
    log_roll_size_mb: int
    // This specifies the FE log directory. FE generates two log files fe.log and fe.warn.log default DorisFE.DORIS_HOME_DIR + "/log"
    sys_log_dir: string
    // The maximum FE log file to be saved in sys_log_roll_interval. The default value is 10, which indicates that there are a maximum of 10 log files in a day
    sys_log_roll_num?: int & >=1 & <=65535 | *10
    // Detailed module. VERBOSE level is implemented by log4j DEBUG level. default {}
    sys_log_verbose_modules: string
    // Optional:1.DAY: log The prefix is yyyyMMdd 2.HOUR: log The prefix is yyyyMMddHH default DAY
    sys_log_roll_interval: string
    // If the logs were last modified 7 days ago, delete them. default 7d format: 1. 7d 2. 10h 3. 60m 4. 120s
    sys_log_delete_age: string
    // Size of a log file: One log file is split every 1 GB default SIZE-MB-1024
    sys_log_roll_mode: string
    // Controls whether to compress fe logs, including fe.log and fe.warn.log. If enabled, the gzip algorithm is used for compression. default false
    sys_log_enable_compress: bool
    // Audit Log directory: This specifies the FE audit log directory. The audit log fe.audit.log contains all requests and related information, such as user, host, cost, and status. default DorisFE.DORIS_HOME_DIR + "/log"
    audit_log_dir: string
    // The maximum FE audit log file in audit_log_roll_interval is reserved. default 90
    audit_log_roll_num: int
    // slow queries include all queries that cost more than qe slow log ms default {"slow_query", "query", "load", "stream_load"}
    audit_log_modules: string
    // If the response time of a query exceeds this threshold, it will be recorded in the audit log as slow_query. default 5000 (5s)
    qe_slow_log_ms: int
    // Optional:1.DAY: log The prefix is yyyyMMdd 2.HOUR: log The prefix is yyyyMMddHH default DAY
    audit_log_roll_interval: int
    // If the audit logs were last modified 7 days ago, delete them. default 7d format: 1. 7d 2. 10h 3. 60m 4. 120s
    audit_log_delete_age: string
    // Controls whether to compress fe.audit.log. If enabled, the gzip algorithm is used for compression. default false
    audit_log_enable_compress: bool
    // Used to set the minimum number of replication for a single tablet. default 1
    min_replication_num_per_tablet: int
    // Used to set the maximum number of replication for a single tablet. default 32767
    max_replication_num_per_tablet: int
    // It is used to set the default database data quota size. Setting the quota size of a single database can be used: default 1125899906842624 (1PB)
    default_db_data_quota_bytes: int
    // This parameter is used to set the default Replica number quota size in the database. You can set the number of replicas in a single database as follows: default 1073741824
    default_db_replica_quota_size: int
    // You can set this configuration to true. The corrupted tablet is replaced with an empty tablet to ensure that the query can be executed default false
    recover_with_empty_tablet: bool
    // Limit the minimum time of a clone task default 180 (3min)
    min_clone_task_timeout_sec: int
    // Limit the maximum time of a clone task default 180 (3min)
    max_clone_task_timeout_sec: int
    // ReportHandler will not check the tablet's storage media and will disable the storage cooling function default false
    disable_storage_medium_check: bool
    // This configuration is used to control whether FE performs Decommission of the status of Tablets. default 5000
    decommission_tablet_check_threshold: int
    // Valid only when PartitionRebalancer is used default 10
    partition_rebalance_max_moves_num_per_selection: int
    // Valid only when PartitionRebalancer is used. If changed, the cache movement will be cleared default 600 (s)
    partition_rebalance_move_expire_after_access: int
    // rebalancer (case insensitive) : BeLoad, Partition. If type resolution fails, BeLoad is used by default  default BeLoad
    tablet_rebalancer_type: string
    // If the number of balance tablets in the TabletScheduler exceeds max_balancing_tablets, the balance check is not performed default 100
    max_balancing_tablets: int
    // If the number of balance tablets in TabletScheduler exceeds max_balancing_tablets, If the number of tablets scheduled by TabletScheduler exceeds max_scheduling_tablets, the balance check is skipped. default 2000
    max_scheduling_tablets: int
    // If set to true, the TabletScheduler will not do the balance default false
    disable_balance: bool
    // If set to true, TabletScheduler does not balance between disks on a single BE  default true
    disable_disk_balance: bool
    // Threshold of the balance percentage of the cluster. default 0.1 (10%)
    balance_load_score_threshold: float
    // Percentage of high watermark usage of the disk capacity. default 0.75 (75%)
    capacity_used_percent_high_water: float
    // Balance threshold for the number of BE copies. default 0.2
    clone_distribution_balance_threshold: float
    // Data size balance threshold in BE. default 0.2
    clone_capacity_balance_threshold: float
    // This configuration can be set to true to disable automatic colocate table repositioning and balancing. default false
    disable_colocate_balance: bool
    // Number of default slots for each path in balance default 1
    balance_slot_num_per_path: int
    // If set to true, the replica repair and balancing logic is turned off. default false
    disable_tablet_scheduler: bool
    // If this parameter is set to true, the system deletes redundant copies immediately in the copy scheduling logic. This may cause some import jobs that are writing to the corresponding copy to fail, but it will speed up the balancing and repair of the copy. default false
    enable_force_drop_redundant_replica: bool
    // Redistributing a Colocation Group can involve a lot of tablet migration. default 1800
    colocate_group_relocate_delay_second: int
    // Whether multiple copies of the same tablet are allowed on the same host. default false
    allow_replica_on_same_host: bool
    // If set to true, every slow copy that compacts automatically detects any compaction and migrates to another machine if the version count of the slowest copy exceeds the min_version_count_indicate_replica_compaction_too_slow value default false
    repair_slow_replica: bool
    // The versioning threshold used to determine if compaction occurs too slowly default 200
    min_version_count_indicate_replica_compaction_too_slow: int
    // If set to true, a copy that compactions slowly skips when a searchable copy is selected default true
    skip_compaction_slower_replica: bool
    // The effective ratio threshold of the difference between the version count of the slowest copy and that of the fastest copy. default 0.5
    valid_version_count_delta_ratio_between_replicas: float
    // Data size threshold, which is used to determine whether the number of copies is too large default 2 * 1024 * 1024 * 1024 (2G)
    min_bytes_indicate_replica_too_large: int
    // The number of default slots per path in the tablet scheduler default 2
    schedule_slot_num_per_path: int
    // The delay time factor before deciding to fix the tablet. default 60 (s)
    tablet_repair_delay_factor_second: int
    // tablet Status Update Interval All FEs will get tablet statistics from all bes at every interval default 300 (5min)
    tablet_stat_update_interval_second: int
    // If the disk capacity reaches storage_flood_stage_usage_percent, the load and restore jobs are rejected default 95 (95%)
    storage_flood_stage_usage_percent: float
    // If the disk capacity reaches storage_flood_stage_left_capacity_bytes, the load and restore jobs are rejected default 1*1024*1024*1024 (1GB)
    storage_flood_stage_left_capacity_bytes: int
    // storage_high_watermark_usage_percent Specifies the percentage of the maximum capacity used by storage paths on the BE end. default 85 (85%)
    storage_high_watermark_usage_percent: float
    // storage_min_left_capacity_bytes Specifies the minimum remaining capacity of the BE storage path. default 2*1024*1024*1024 (2GB)
    storage_min_left_capacity_bytes: int
    // After deleting the database (table/partition), you can RECOVER it using RECOVER stmt. This specifies the maximum data retention time. default 86400L (one day)
    catalog_trash_expire_second: int
    // When you create a table (or partition), you can specify its storage medium (HDD or SSD). default HDD
    default_storage_medium: string
    // Whether to enable the Storage Policy function. This function allows you to separate hot and cold data. default false
    enable_storage_policy: bool
    // Default timeout for a single consistency check task. Set it long enough to fit your tablet size. default 600 (10min)
    check_consistency_default_timeout_second: int
    // Consistency check start time default 23
    consistency_check_start_time: int
    // Consistency check end time default 23
    consistency_check_end_time: int
    // The minimum number of seconds of delay between copies failed, and an attempt was made to recover it using cloning. default 0
    replica_delay_recovery_second: int
    // Maximum timeout of ALTER TABLE request. Set it long enough to fit your table data size default 86400 * 30 (1 mouth)
    alter_table_timeout_second: int
    // OlapTable Specifies the maximum number of copies allowed when schema change is performed. If the number of copies is too large, an FE OOM will occur. default 100000
    max_replica_count_when_schema_change: int
    // Maximum retention time for certain jobs. Things like schema changes and Rollup jobs. default 7 * 24 * 3600 (7days)
    history_job_keep_max_second: int
    // In order not to wait too long before creating a table (index), set a maximum timeout default 1*3600 (an hour)
    max_create_table_timeout_second: int
    // multi catalog Number of concurrent file scanning threads default 128
    file_scan_node_split_num: int
    // multi catalog Scan size of concurrent files default 256*1024*1024
    file_scan_node_split_size: int
    // Whether to enable the ODBC table. The ODBC table is disabled by default. You need to manually enable it when using the ODBC table. default false
    enable_odbc_table: bool
    // Starting with version 1.2, we no longer support the creation of hudi and iceberg looks. Use the multi catalog function instead. default true
    disable_iceberg_hudi_table: bool
    // fe creates the iceberg table every iceberg_table_creation_interval_second default 10(s)
    iceberg_table_creation_interval_second: int
    // If set to true, the iceberg table and the Doris table must have the same column definitions. default true
    iceberg_table_creation_strict_mode: bool
    // The default maximum number of recent iceberg library table creation records that can be stored in memory default 2000
    max_iceberg_table_creation_record_size: int
    // Maximum number of caches for the hive partition. default 100000
    max_hive_partition_cache_num: int
    // Default timeout period of hive metastore default 10
    hive_metastore_client_timeout_second: int
    // The maximum number of threads for the meta cache load thread pool for external external tables. default 10
    max_external_cache_loader_thread_pool_size: int
    // Maximum number of file caches used for external external tables. default 100000
    max_external_file_cache_num: int
    // The maximum number of schema caches used for external external tables. default 10000
    max_external_schema_cache_num: int
    // Sets how long the data in the cache is invalid after the last access. The unit is minute. It applies to External Schema Cache and Hive Partition Cache. default 1440
    external_cache_expire_time_minutes_after_access: int
    // FE calls the es api every es_state_sync_interval_secs to get the es index fragment information default 10
    es_state_sync_interval_second: int
    // default /lib/hadoop-client/hadoop/bin/hadoop
    dpp_hadoop_client_path: string
    // default 100*1024*1024L (100M)
    dpp_bytes_per_reduce: int
    // default palo-dpp
    dpp_default_cluster: string
    // default { hadoop_configs : 'mapred.job.priority=NORMAL;mapred.job.map.capacity=50;mapred.job.reduce.capacity=50;mapred.hce.replace.streaming=false;abaci.long.stored.job=true;dce.shuffle.enable=false;dfs.client.authserver.force_stop=true;dfs.client.auth.method=0' }
    dpp_default_config_str: string
    // default { palo-dpp : { hadoop_palo_path : '/dir', hadoop_configs : 'fs.default.name=hdfs://host:port;mapred.job.tracker=host:port;hadoop.job.ugi=user,password' } }
    dpp_config_str: string
    // Default Yarn configuration file directory Each time you run the Yarn command, you need to check whether the config file exists in this path. If it does not exist, create it. default DorisFE.DORIS_HOME_DIR + "/lib/yarn-config"
    yarn_config_dir: string
    // Default Yarn client path default DorisFE.DORIS_HOME_DIR + "/lib/yarn-client/hadoop/bin/yarn"
    yarn_client_path: string
    // Specifies the Spark initiator log directory default sys_log_dir + "/spark_launcher_log"
    spark_launcher_log_dir: string
    // Default Spark dependency path default ""
    spark_resource_path: string
    // Default Spark home path default DorisFE.DORIS_HOME_DIR + "/lib/spark2x"
    spark_home_default_dir: string
    // The default version of Spark default 1.2-SNAPSHOT
    spark_dpp_version: string
    // temp dir is used to save the intermediate results of certain processes, such as backup and restore processes. When these procedures are complete, the files in this directory are cleared. default DorisFE.DORIS_HOME_DIR + "/temp_dir"
    tmp_dir: string
    // Plug-in installation directory default DORIS_HOME + "/plugins
    plugin_dir: string
    // Whether the plug-in is enabled. The plug-in is enabled by default default true
    plugin_enable: bool
    // The directory where the small file is saved default DORIS_HOME_DIR + “/small_files”
    small_file_dir: string
    // SmallFileMgr Indicates the maximum size of a single file default 1048576 (1M)
    max_small_file_size_bytes: int
    // SmallFileMgr Indicates the maximum number of files stored in SmallFilemgr default 100
    max_small_file_number: int
    // If set to true, the metrics collector runs as a daemon timer, collecting metrics at regular intervals default true
    enable_metric_calculator: bool
    // This threshold is to avoid piling up too many reporting tasks in FE, which may cause problems such as OOM exceptions. default 100
    report_queue_size: int
    // Default timeout period of a backup job default 86400*1000(one day)
    backup_job_default_timeout_ms: int
    // This configuration controls the number of backup/restore tasks that can be logged per DB default 10
    max_backup_restore_job_num_per_db: int
    // Whether to enable the quantile state data type default false
    enable_quantile_state_type: bool
    // If set to true, FE automatically converts Date/Datetime to DateV2/DatetimeV2(0). default false
    enable_date_conversion: bool
    // If set to true, FE will automatically convert DecimalV2 to DecimalV3. default false
    enable_decimal_conversion: bool
    // default x@8
    proxy_auth_magic_prefix: string
    // default false
    proxy_auth_enable: bool
    // Whether to push the filtering conditions with functions to MYSQL when querying external tables of ODBC and JDBC default true
    enable_func_pushdown: bool
    // Used to store default jdbc drivers default ${DORIS_HOME}/jdbc_drivers;
    jdbc_drivers_dir: string
    // The maximum number of failed tablet information saved by the broker load job default 3
    max_error_tablet_of_broker_load: int
    // Used to set the default database transaction quota size. The default value set to -1 means that max_running_txn_num_per_db is used instead of default_db_max_running_txn_num. default -1
    default_db_max_running_txn_num: int
    // If set to true, queries on external tables are preferentially assigned to compute nodes. The maximum number of compute nodes is controlled by min_backend_num_for_external_table. If set to false, queries on external tables will be assigned to any node. default false
    prefer_compute_node_for_external_table: bool
    // This parameter is valid only when prefer_compute_node_for_external_table is true. If the number of compute nodes is less than this value, a query against the external table will try to use some mixed nodes so that the total number of nodes reaches this value. If the number of compute nodes is greater than this value, queries from the external table will only be assigned to compute nodes.default 3
    min_backend_num_for_external_table: int
    // When set to false, querying tables in information_schema no longer returns information about tables in the external catalog.default false
    infodb_support_ext_catalog: bool
    // Limits the maximum packet length that can be received by the thrift port on fe nodes to prevent OOM from being caused by oversized or incorrect packets default 20000000
    fe_thrift_max_pkg_bytes: int

    //dynmaic
    // Maximum wait time for creating a single copy.default 1(s)
    tablet_create_timeout_second?: int & >=1 & <=65535 | *2
    // Maximum wait time for deleting a single copy.default 2
    tablet_delete_timeout_second?: int & >=1 & <=65535 | *2
}

configuration: #DorisParameter & {
}
