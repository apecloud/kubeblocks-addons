#FEParameter: {
	// DYNAMIC parameters

	// Abort transaction time after lost heartbeat. The default value is 300s, which means transactions of be will be aborted after lost heartbeat 300s.
	abort_txn_after_lost_heartbeat_time_second: int | *300

	// This config will decide whether to resend agent task when create_time for agent_task is set, only when current_time - create_time > agent_task_resend_wait_time_ms can ReportHandler do resend agent task
	agent_task_resend_wait_time_ms: int | *5000

	// Maximal timeout of ALTER TABLE request. Set long enough to fit your table data size. Default value is 2592000s(1 month).
	alter_table_timeout_second: int | *2592000

	// audit_event_log_queue_size = qps * query_audit_log_timeout_ms
	audit_event_log_queue_size: int | *250000

	// This parameter controls the time interval for automatic collection jobs to check the health of table statistics and trigger automatic collection
	auto_check_statistics_in_minutes: int | *5

	// Max number of buckets for auto bucket
	autobucket_max_buckets: int | *128

	// Minimal number of buckets for auto bucket
	autobucket_min_buckets: int | *1

	// Sets a fixed disk usage factor in the BE load fraction. The BE load score is a combination of disk usage and replica count. The valid value range is [0, 1]. When it is out of this range, other methods are used to automatically calculate this coefficient.
	backend_load_capacity_coeficient: float | *-1.0

	// Default timeout of Backup Job
	backup_job_default_timeout_ms: int | *86400000

	// The max number of upload tasks assigned to each be during the backup process, the default value is 3
	backup_upload_task_num_per_be: int | *3

	// Balance order, a temporary config, may delete later.
	balance_be_then_disk: bool | *true

	// The threshold of cluster balance score, if a backend's load score is 10% lower than average score, this backend will be marked as LOW load, if load score is 10% higher than average score, HIGH load will be marked.
	balance_load_score_threshold: float | *0.1

	// 1 slot for reduce unnecessary balance task, provided a more accurate estimate of capacity
	balance_slot_num_per_path: int | *1

	// Max data version of backends serialize block.
	be_exec_version: int | *5

	// If set to TRUE, FE will: 1. divide BE into high load and low load(no mid load) to force triggering tablet scheduling;2. ignore whether the cluster can be more balanced during tablet scheduling. It's used to test the reliability in single replica case when tablet scheduling are frequent. Default is false.
	be_rebalancer_fuzzy_test: bool | *false

	// When be rebalancer idle, then disk balance will occurs.
	be_rebalancer_idle_seconds: int | *0

	// The maximum waiting time for BE nodes to report statistical information to FE nodes.
	be_report_query_statistics_timeout_ms: int | *60000

	// After a backend is marked as unavailable, it will be added to blacklist. Default is 120s.
	blacklist_duration_second: int | *120

	// Default timeout for broker load job, in seconds.
	broker_load_default_timeout_second: int | *14400

	// If set to true, fe will get data from be cache. This option is suitable for real-time updating of partial partitions.
	cache_enable_partition_mode: bool | *true

	// If set to true, fe will enable sql result cache. This option is suitable for offline data update scenarios.
	cache_enable_sql_mode: bool | *true

	// Minimum interval between last version when caching results, This parameter distinguishes between offline and real-time updates.
	cache_last_version_interval_second: int | *30

  // Maximum data size of rows that can be cached in SQL/Partition Cache, is 3000 by default.
	cache_result_max_data_size: int | *3000

	// Maximum number of rows that can be cached in SQL/Partition Cache, is 3000 by default.
	cache_result_max_row_count: int | *3000

	// The high water of disk capacity used percent. This is used for calculating load score of a backend.
	capacity_used_percent_high_water: float | *0.75

	// After dropping database(table/partition), you can recover it by using RECOVER stmt. And this specifies the maximal data retention time. After time, the data will be deleted permanently.
	catalog_trash_expire_second: int | *86400

	// The tryLock timeout configuration of catalog locr. Normally it does not need to change, unless you need to test something.
	catalog_try_lock_timeout_ms: int | *5000

	// Default sample percentage. The value from 0 ~ 100. The 100 means no sampling and fetch all data.
	cbo_default_sample_percentage: int & >=0 & <=100 | *100

	// The max unfinished statistics job number
	cbo_max_statistics_job_num: int | *20

	// Default timeout of a single consistency check task. Set long enough to fit your tablet size. Default value is 600s.
	check_consistency_default_timeout_second: int | *600

	// The threshold for the read ratio of cold data.
  	cloud_cold_read_percent: int | *10

	// The number of replicas for each data block in cloud storage.
	cloud_replica_num: int | *3

	// The relocation of a colocation group may involve a large number of tablets moving within the cluster. Therefore, doris should use a more conservative strategy to avoid relocation of colocation groups as much as possible. Reloaction usually occurs after a BE node goes offline or goes down. This parameter is used to delay the determination of BE node unavailability. The default is 30 minutes, i.e.,if a BE node recovers within 30 minutes, relocation of the colocation group will not be triggered.
	colocate_group_relocate_delay_second: int | *1800

	// Maximal waiting time for all data inserted before one transaction to be committed, in seconds. This parameter is only used for transactional insert operation.
	commit_timeout_second: int | *30

	// End time of consistency check. Used with `consistency_check_start_time` to decide the start and end time of consistency check. If set to the same value, consistency check will not be scheduled.
	consistency_check_end_time: string | *"23"

	// Start time of consistency check. Used with `consistency_check_end_time` to decide the start and end time of consistency check. If set to the same value, consistency check will not be scheduled.
	consistency_check_start_time: string | *"23"

	// When creating tablet of a partition, always start from the first BE. This method may cause BE imbalance.
	create_tablet_round_robin_from_start: bool | *false

	// When tablet size of decommissioned backend is lower than this threshold, SystemHandler will start to check if all tablets of this backend are in recycled status, this backend will be dropped immediately if the check result is true. For performance based considerations, better not set a very high value for this.
	decommission_tablet_check_threshold: int | *5000

	// Decommission a tablet need to wait all the previous txns finished. If wait timeout, decommission will fail. Need to increase this wait time if the txn take a long time.
	decommission_tablet_wait_time_seconds: int | *3600

	// Used to set default db data quota bytes. Default is 1PB
	default_db_data_quota_bytes: int | *1125899906842624

 	// Used to set default db transaction quota num.
	default_db_max_running_txn_num: int | *-1

	// Used to set default db replica quota num.
	default_db_replica_quota_size: int | *1073741824

	// The default parallelism of the load execution plan on a single node when the broker load is submitted
	default_load_parallelism: int | *8

	// Maximum percentage of data that can be filtered (due to reasons such as data is irregularly). Default is 0
	default_max_filter_ratio: float | *0

	// Control the default max num of the instance for a user.
	default_max_query_instances: int | *-1

	// Maximal timeout for delete job, in seconds.
	delete_job_max_timeout_second: int | *300

	// Maximal number of waiting jobs for Broker Load. This is a desired number. In some situation, such as switch the master, the current number is maybe more than this value.
	desired_max_waiting_jobs: int | *100

	// The maximum difference in the number of tablets of each BE in partition rebalance mode. If it is less than this value, it will be diagnosed as balanced.
	diagnose_balance_max_tablet_num_diff: int | *50

	// The maximum ratio of the number of tablets in each BE in partition rebalance mode. If it is less than this value, it will be diagnosed as balanced.
	diagnose_balance_max_tablet_num_ratio: float | *1.1

	// Set to true to disable backend black list, so that even if doris failed to send task to a backend, that backend won't be added to black list. This should only be set when running tests, such as regression test. Highly recommended NOT disable it in product environment.
	disable_backend_black_list: bool | *false

	// If set to true, TabletScheduler will not do balance.
	disable_balance: bool | *false

	// This configs can set to true to disable the automatic colocate tables's relocate and balance. If 'disable_colocate_balance' is set to true, ColocateTableBalancer will not relocate and balance colocate tables.
	disable_colocate_balance: bool | *false

	// Whether to allow colocate balance between all groups
	disable_colocate_balance_between_groups: bool | *false

 	// To prevent different types (V1, V2, V3) of behavioral inconsistencies, doris may delete the DecimalV2 and DateV1 types in the future. At this stage, doris use ‘disable_decimalv2’ and ‘disable_datev1’ to determine whether these two types take effect.
	disable_datev1: bool | *true

 	// To prevent different types (V1, V2, V3) of behavioral inconsistencies, doris may delete the DecimalV2 and DateV1 types in the future. At this stage, doris use ‘disable_decimalv2’ and ‘disable_datev1’ to determine whether these two types take effect.
	disable_decimalv2: bool | *true

	// If set to true, TabletScheduler will not do disk balance
	disable_disk_balance: bool | *false

	// Load using hadoop cluster will be deprecated in future. Set to true to disable this kind of load.
	disable_hadoop_load: bool | *false

	// If set to true, all pending load job will failed when call begin txn api; all prepare load job will failed when call commit txn api; all committed load job will waiting to be published.
	disable_load_job: bool | *false

	// Whether to disable LocalDeployManager drop node.
	disable_local_deploy_manager_drop_node: bool | *true

	// Whether to disable show stream load and clear stream load records in memory.
	disable_show_stream_load: bool | *false

	// When disable_storage_medium_check is true, ReportHandler would not check tablet's storage medium and disable storage cool down function.
	disable_storage_medium_check: bool | *false

	// If set to true, the tablet scheduler will not work, so that all tablet repair/balance task will not work.
	disable_tablet_scheduler: bool | *false

	// Whether to disable creating catalog with WITH RESOURCE statement.
	disallow_create_catalog_with_resource: bool | *true

	// This variable indicates the number of digits by which to increase the scale of the result of division operations performed with the `/` operator. The default value is 4, and it is currently only used for the DECIMALV3 type.
	div_precision_increment: int | *4

	// If set to true, the backend will be automatically dropped after finishing decommission. If set to false, the backend will not be dropped and remaining in DECOMMISSION state.
	drop_backend_after_decommission: bool | *true

	// The maximum number of retries allowed after an RPC request fails.
	drop_rpc_retry_num: int | *200

	// Decide how often to check dynamic partition.
	dynamic_partition_check_interval_seconds: int | *600

	// If set to true, dynamic partition feature will open.
	dynamic_partition_enable: bool | *true

	// The log roll size of BDBJE. When the number of log entries exceeds this value, the log will be rolled.
	edit_log_roll_num: int | *5000

	// This config is used to try skip broker when access bos or other cloud storage via broker.
	enable_access_file_without_broker: bool | *false

	// Used for regression test
	enable_alter_queue_prop_sync: bool | *false

	// Support complex data type ARRAY.
	enable_array_type: bool | *false

	// Whether to add a delete sign column when create unique table.
	enable_batch_delete_by_default: bool | *true

	// Whether to enable multi redundancy for cloud cloud storage.
	enable_cloud_multi_replica: bool | *false

 	// Whether to collect internal query performance analysis data
	enable_collect_internal_query_profile: bool | *false

	// Whether to enable the "affinity adjustment" strategy for replicas during the control cooldown period
	enable_cooldown_replica_affinity: bool | *true

	// Whether to create the bitmap index in the form of an inverted index
	enable_create_bitmap_index_as_inverted_index: bool | *true

	// Enable external hive bucket table.
	enable_create_hive_bucket_table: bool | *false

	// If set to TRUE, FE will convert date/datetime to datev2/datetimev2(0) automatically.
	enable_date_conversion: bool | *true

	// If set to TRUE, FE will convert DecimalV2 to DecimalV3 automatically.
	enable_decimal_conversion: bool | *true

	// If set to false, TabletScheduler will not do disk balance for replica num = 1.
	enable_disk_balance_for_single_replica: bool | *false

  	// When doing clone or repair tablet task, there may be replica is REDUNDANT state, which should be dropped later. But there are be loading task on these replicas, so the default strategy is to wait until the loading task finished before dropping them. But the default strategy may takes very long time to handle these redundant replicas. So doris can set this config to true to not wait any loading task. Set this config to true may cause loading task failed, but will speed up the process of tablet balance and repair.
	enable_force_drop_redundant_replica: bool | *false

	// Whether to add a version column when create unique table
	enable_hidden_version_column_by_default: bool | *true

	// If set to true, Planner will try to select replica of tablet on same host as this Frontend.
  	enable_local_replica_selection: bool | *false

	// Used with enable_local_replica_selection. If the local replicas is not available, fallback to the nonlocal replicas.
	enable_local_replica_selection_fallback: bool | *false

	// Enable the 'delete predicate' for DELETE statements. If enabled, it will enhance the performance of DELETE statements, but partial column updates after a DELETE may result in erroneous data. If disabled, it will reduce the performance of DELETE statements to ensure accuracy.
	enable_mow_light_delete: bool | *false

	// Whether to allow the creation of odbc, mysql, broker type external tables
	enable_odbc_mysql_broker_table: bool | *false

	// Whether to enable the pipelined data loading
	enable_pipeline_load: bool | *true

	// Whether to collect performance analysis data when analyzing.
	enable_profile_when_analyze: bool | *false

	// Enable quantile_state type column. Default value is false.
	enable_quantile_state_type: bool | *true

	// This configuration is used to enable the statistics of query information, which will record the access status of databases, tables, and columns, and can be used to guide the optimization of table structures
	enable_query_hit_stats: bool | *false

	// If set to true, doris will try to parse the ddl of a hive view and try to execute the query otherwise it will throw an AnalysisException.
	enable_query_hive_views: bool | *true

	// Whether to enable the query queue.
	enable_query_queue: bool | *true

	// Whether to enable the round-robin tablet creation strategy.
	enable_round_robin_create_tablet: bool | *true

	// There's a case, all backend has a high disk, by default, it will not run urgent disk balance. If set this value to true, urgent disk balance will always run, the backends will exchange tablets among themselves.
	enable_urgent_balance_no_low_backend: bool | *true
	
	// Whether to enable the CPU hard limit.
	enable_cpu_hard_limit: bool | *false

	// Whether to enable the MTMV feature.
	enable_mtmv: bool | *false
	
	// Whether to enable the Nereids optimizer. If enabled, the load statement of the new optimizer can be used to import data. If this function fails, the old load statement will be degraded.
	enable_nereids_load: bool | *false

	// Whether to enable the single replica load. If enabled, the load statement of the new optimizer can be used to import data. If this function fails, the old load statement will be degraded.
	enable_single_replica_load: bool | *false
	
	// Whether to enable the workload group. If enabled, the user can create a workload group and assign the query to the group.
	enable_workload_group: bool | *true
	
	// Shuffle won't be enabled for DUPLICATE KEY tables if its tablet num is lower than this number
	min_tablets_for_dup_table_shuffle: int | *64

	// This config is used to control the number of sql cache managed by NereidsSqlCacheManager. Default set to 100.
	sql_cache_manage_num: int | *100

	// Expire sql cache in frontend time. Default set to 300 seconds.
	expire_sql_cache_in_fe_second: int | *300

	// Limit on the number of expr children of an expr tree. Exceed this limit may cause long analysis time while holding database read lock. Do not set this if you know what you are doing.
	expr_children_limit: int | *10000

	// Limit on the depth of an expr tree. Exceed this limit may cause long analysis time while holding db read lock. Do not set this if you know what you are doing.
	expr_depth_limit: int | *3000

	// The interval of FE fetch stream load record from BE. Default set to 120 seconds.
	fetch_stream_load_record_interval_second: int | *120
	
	// Whether to fix the tablet partition id to 0. Default set to false.
	fix_tablet_partition_id_eq_0: bool | *false
	
	// If set to true, the checkpoint thread will make the checkpoint regardless of the jvm memory used percent.
	force_do_metadata_checkpoint: bool | *false

	// Used to force set the replica allocation of the internal table. If the config is not empty, the replication_num and replication_allocation specified by the user when creating the table or partitions will be ignored, and the value set by this parameter will be used. This config effect the operations including create tables, create partitions and create dynamic partitions. This config is recommended to be used only in the test environment.
	force_olap_table_replication_allocation: string | *""

	// Used to force the number of replicas of the internal table. If the config is not 0, the replication_num specified by the user when creating the table or partitions will be ignored, and the value set by this parameter will be used. 
	force_olap_table_replication_num: int | *0

	// Github workflow test type, for setting some session variables only for certain test type.
	fuzzy_test_type: string | *""

	// In the scenario of memory backpressure, the time interval for obtaining BE memory usage at regular intervals. Default set to 10000 milliseconds.
	get_be_resource_usage_interval_ms: int | *10000

	// Default timeout for hadoop load job. Default set to 3 days.
	hadoop_load_default_timeout_second: int | *259200

	// For ALTER, EXPORT jobs, remove the finished job if expired. Default set to 7 day.
	history_job_keep_max_second: int | *604800

	// Default hive file format for creating table
	hive_default_file_format: string | *"orc"

	// The default connection timeout for hive metastore. Default set to 10 seconds.
	hive_metastore_client_timeout_second: int | *10

	// Sample size for hive row count estimation.
	hive_stats_partition_sample_size: int | *30

	// Maximum number of events to poll in each RPC.
	hms_events_batch_size_per_rpc: int | *500

	// whether to ignore table that not support type when backup, and not report exception.
	ignore_backup_not_support_table_type: bool | *false

	// Whether to ignore metadata delay. If the metadata delay of the master FE exceeds this threshold, non - master FEs will still provide read services when the config is set to true. Default set to false.
	ignore_meta_check: bool | *false

	// Default timeout for insert load job, in seconds. Default set to 4
	insert_load_default_timeout_second: int | *14400

	// Default storage format of inverted index, the default value is V1.
	inverted_index_storage_format: string | *"V1"

	// Whether to retain the associated MTMV tasks when deleting a Job.
	keep_scheduler_mtmv_task_when_job_deleted: bool | *false

	// Labels of finished or cancelled load jobs will be removed after this time. The removed labels can be reused. Default set to 3 days.
	label_keep_max_second: int | *259200

	// The threshold of load labels' number. After this number is exceeded, the labels of the completed import jobs or tasks will be deleted and the deleted labels can be reused. When the value is -1, it indicates no threshold. Default set to 100000.
	label_num_threshold: int | *2000
		
	// The timeout for LDAP cache, in days. Default set to 30 days.
	ldap_cache_timeout_day: int | *30

	// The timeout for LDAP user cache, in seconds. Default set to 12 hours.
	ldap_user_cache_timeout_s: int | *43200

	// When execute admin set replica status = 'drop', the replica will marked as user drop. Doris will try to drop this replica within time not exceeds manual_drop_replica_valid_second. Default set to 24 hours.
	manual_drop_replica_valid_second: int | *86400

	// Used to limit element num of InPredicate in delete statement. Default set to 1024.
	max_allowed_in_element_num_of_delete: int | *1024
	
	// For auto-partitioned tables to prevent users from accidentally creating a large number of partitions, the number of partitions allowed per OLAP table is `max_auto_partition_num`. Default set to 2000.
	max_auto_partition_num: int | *2000

	// Maximum backend heartbeat failure tolerance count, default set to 1.
	max_backend_heartbeat_failure_tolerance_count: int | *1

	// Control the max num of backup/restore job per db.
	max_backup_restore_job_num_per_db: int | *10

	// Control the max num of tablets per backup job involved, to avoid OOM
	max_backup_tablets_per_job: int | *300000

	// if the number of balancing tablets in TabletScheduler exceed max_balancing_tablets, no more balance check. Default set to 100.
	max_balancing_tablets: int | *100

	// Maximal concurrency of broker scanners 
	max_broker_concurrency: int | *10

	// Max bytes a broker scanner can process in one broker load job. Default set to 500GB.
	max_bytes_per_broker_scanner: int | *536870912000

	// Max bytes that a sync job will commit. When receiving bytes larger than it, SyncJob will commit all data immediately. You should set it larger than canal memory and `min_bytes_sync_commit`. Default set to 64MB.
	max_bytes_sync_commit: int | *67108864

	// The max timeout of a statistics task
	max_cbo_statistics_task_timeout_sec: int | *300

	// max_clone_task_timeout_sec is to limit the max timeout of a clone task. Default set to 2 hours.
	max_clone_task_timeout_sec: int | *7200

	// Maximal waiting time for creating a table, in seconds.
	max_create_table_timeout_second: int | *3600

	// This will limit the max recursion depth of hash distribution pruner.
	max_distribution_pruner_recursion_depth: int | *100

	// Used to limit the maximum number of partitions that can be created when creating a dynamic partition table to avoid creating too many partitions at one time.
	max_dynamic_partition_num: int | *500

	// Maximum number of error tablets showed in broker load.
	max_error_tablet_of_broker_load: int | *3

	// The max timeout of get kafka meta. Default set to 60 seconds.
	max_get_kafka_meta_timeout_second: int | *60
	
	// Maximal timeout for load job, in seconds. Default set to 3 days.
	max_load_timeout_second: int | *259200

	// Maximum lock hold time; logs a warning if exceeded. Default set to 10 seconds.
	max_lock_hold_threshold_seconds: int | *10

	// Used to limit the maximum number of partitions that can be created when creating multi partition to avoid creating too many partitions at one time.
	max_multi_partition_num: int | *4096

	// Max pending task num keep in pending poll, otherwise it reject the task submit.
	max_pending_mtmv_scheduler_task_num: int | *100

	// The number of point query retries in executor. A query may retry if we encounter RPC exception and no result has been sent to user.
	max_point_query_retry_time: int | *2
	
	// Max query profile num. Default set to 100.
	max_query_profile_num: int | *100
	
	// The number of query retries. Default set to 3.
	max_query_retry_time: int | *3

	// The maximum number of replicas allowed when an OlapTable performs a schema change.
	max_replica_count_when_schema_change: int | *100000
	
	// Used to set maximal number of replication per tablet. Default set to 32767.
	max_replication_num_per_tablet: int | *32767

	// The max routine load job num, including NEED_SCHEDULED, RUNNING, PAUSE. Default set to 100.
	max_routine_load_job_num: int | *100

	// The max concurrent routine load task num of a single routine load job.
	max_routine_load_task_concurrent_num: int | *256

	// The max concurrent routine load task num per BE. Default set to 1024.
	max_routine_load_task_num_per_be: int | *1024

	// Max running task num at the same time, otherwise the submitted task will still be keep in pending poll. Default set to 100.
	max_running_mtmv_scheduler_task_num: int | *100

	// Control rollup job concurrent limit.
	max_running_rollup_job_num_per_table: int | *1

	// Maximum concurrent running txn num including prepare, commit txns under a single db. Txn manager will reject coming txns.
	max_running_txn_num_per_db: int | *1000

	// Max num of same name meta informatntion in catalog recycle bin. Default is 3. 0 means do not keep any meta obj with same name. < 0 means no limit.
	max_same_name_catalog_trash_num: int | *3

	// Maximal number of tablets that can be scheduled at the same time. If the number of scheduled tablets in TabletScheduler exceed max_scheduling_tablets, skip checking.
	max_scheduling_tablets: int | *2000

	// The max number of files store in SmallFileMgr. Default set to 100.
	max_small_file_number: int | *100

	// The max size of a single file store in SmallFileMgr. Default set to 1MB
	max_small_file_size_bytes: int | *1048576

	// Default max number of recent stream load record that can be stored in memory.
	max_stream_load_record_size: int | *5000

	// Maximal timeout for stream load job, in seconds. Default set to 3 days.
	max_stream_load_timeout_second: int | *259200

	// It can't auto-resume routine load job as long as one of the backends is down
	max_tolerable_backend_down_num: int | *0
	
	// Max number of load jobs, include PENDING、ETL、LOADING、QUORUM_FINISHED. If exceed this number, load job is not allowed to be submitted.
	max_unfinished_load_job: int | *1000

	// The maximum number of partitions allowed by Export job. Default set to 2000.
	maximum_number_of_export_partitions: int | *2000

	// The maximum parallelism allowed by Export job. Default set to 50.
	maximum_parallelism_of_export_job: int | *50

	// The maximum number of tablets allowed by an OutfileStatement in an ExportExecutorTask. Default set to 10.
	maximum_tablets_of_outfile_in_export: int | *10

	// A connection will expire after a random time during [base, 2*base), so that the FE has a chance to connect to a new RS. Set zero to disable it.
	meta_service_connection_age_base_minutes: int | *5

	// The maximum number of connections allowed in the connection pool. Default set to 20.
	meta_service_connection_pool_size: int | *20

	// Whether to enable pooling for meta service connections. Default set to true.
	meta_service_connection_pooled: bool | *true

	// The number of times to retry a RPC call to meta service.
	meta_service_rpc_retry_times: int | *200

	// If the jvm memory used percent(heap or old mem pool) exceed this threshold, checkpoint thread will not work to avoid OOM.
	metadata_checkpoint_memory_threshold: int | *70

	// Only take effect when prefer_compute_node_for_external_table is true. If the compute node number is less than this value, query on external table will try to get some mix de to assign, to let the total number of node reach this value. If the compute node number is larger than this value, query on external table will assign to compute de only.
	min_backend_num_for_external_table: int | *-1
	
	// The data size threshold used to judge whether replica is too large. Default set to 2GB.
	min_bytes_indicate_replica_too_large: int | *2147483648
	
	// Minimal bytes that a single broker scanner will read. When splitting file in broker load, if the size of split file is less than this value, it will not be split.
	min_bytes_per_broker_scanner: int | *67108864

	// Min bytes that a sync job will commit. When receiving bytes less than it, SyncJob will continue to wait for the next batch of data until the time exceeds `sync_commit_interval_second`.
	min_bytes_sync_commit: int | *15728640

	// Limit the min timeout of a clone task. Default set to 3 min.
	min_clone_task_timeout_sec: int | *180

	// Minimal waiting time for creating a table, in seconds. Default set to 30 seconds.
	min_create_table_timeout_second: int | *30

	// Minimal number of write successful replicas for load job.
	min_load_replica_num: int | *-1
	
	// Minimal timeout for load job, in seconds.
	min_load_timeout_second: int | *1

	// Used to set minimal number of replication per tablet. Default set to 1.
	min_replication_num_per_tablet: int | *1

	// Min events that a sync job will commit. When receiving events less than it, SyncJob will continue to wait for the next batch of data until the time exceeds `sync_commit_interval_second`. Default set to 10000.
	min_sync_commit_size: int | *10000

	// The version count threshold used to judge whether replica compaction is too slow. Default set to 200.
	min_version_count_indicate_replica_compaction_too_slow: int | *200

	// Use this parameter to set the partition name prefix for multi partition. Only multi partition takes effect, not dynamic partitions. The default prefix is "p_".
	multi_partition_name_prefix: string | *"p_"

	// To ensure compatibility with the MySQL ecosystem, Doris includes a built-in database called mysql. If this database conflicts with a user's own database, please modify this field to replace the name of the Doris built-in MySQL database with a different name.
	mysqldb_replace_name: string | *"mysql"

	// Valid only if use PartitionRebalancer.
	partition_rebalance_max_moves_num_per_selection: int | *10

	// Valid only if use PartitionRebalancer. If this changed, cached moves will be cleared.
	partition_rebalance_move_expire_after_access: int | *600

	// A period for auto resume routine load. Default set to 10 min.
	period_of_auto_resume_min: int | *10

	// Whether to enable the plugin
	plugin_enable: bool | *true

	// If set to true, query on external table will prefer to assign to compute node. And the max number of compute node is controlled by min_backend_num_for_external_table. If set to false, query on external table will assign to any node. If there is no compute node in cluster, this config takes no effect.
	prefer_compute_node_for_external_table: bool | *false

	// Print log interval for publish transaction failed interval
	publish_fail_log_interval_second: int | *300

	// Interval for publish topic info interval
	publish_topic_info_interval_ms: int | *30000

	// Check the replicas which are doing schema change when publish transaction. Do not turn off this check under normal circumstances. It's only temporarily skip check if publish version and schema change have dead lock.
	publish_version_check_alter_replica: bool | *true

	// Maximal waiting time for all publish version tasks of one transaction to be finished, in seconds.
	publish_version_timeout_second: int | *30

	// Waiting time for one transaction changing to \"at least one replica success\", in seconds. If time exceeds this, and for each tablet it has at least one replica publish successful, then the load task will be successful.
	publish_wait_time_second: int | *300
	
	// Used to set session variables randomly to check more issues in github workflow.
	pull_request_id: int | *0

	// The threshold of slow query, in milliseconds.
	qe_slow_log_ms: int | *5000

	// Timeout for query audit log, in milliseconds. It should bigger than be config report_query_statistics_interval_ms
	query_audit_log_timeout_ms: int | *5000

	// Colocate join PlanFragment instance memory limit penalty factor.The memory_limit for colocote join PlanFragment instance = `exec_mem_limit / min (query_colocate_join_memory_limit_penalty_factor, instance_num)`
	query_colocate_join_memory_limit_penalty_factor: int | *1

	// When querying the information_schema.metadata_name_ids table, the time used to obtain all tables in one database.
	query_metadata_name_ids_timeout: int | *3

	// When be memory usage bigger than this value, query could queue, default value is -1, means this value not work. Decimal value range from 0 to 1.
	query_queue_by_be_used_memory: float | *-1

	// Interval for query queue update, in milliseconds.
	query_queue_update_interval_ms: int | *5000

	// In some cases, some tablets may have all replicas damaged or lost. At this time, the data has been lost, and the damaged tablets will cause the entire query to fail, and the remaining healthy tablets cannot be queried. In this case, you can set this configuration to true. The system will replace damaged tablets with empty tablets to ensure that the query can be executed. (but at this time the data has been lost, so the query results may be inaccurate)
	recover_with_empty_tablet: bool | *false

	// The timeout of executing async remote fragment.
	remote_fragment_exec_timeout_ms: int | *30000
	
	// Auto set the slowest compaction replica's status to bad. Default set to false.
	repair_slow_replica: bool | *false
	
	// This threshold is to avoid piling up too many report task in FE, which may cause OOM exception. In some large Doris cluster, eg: 100 Backends with ten million replicas, a tablet report may cost several seconds after some modification of metadata(drop partition, etc..).
	report_queue_size: int | *100

	// The max number of download tasks assigned to each be during the restore process, the default value is 3.
	restore_download_task_num_per_be: int | *3

	// The default batch size in tablet scheduler for a single schedule.
	schedule_batch_size: int | *50

	// The default slot number per path for hdd in tablet scheduler
	schedule_slot_num_per_hdd_path: int | *4

	// The default slot number per path for ssd in tablet scheduler
	schedule_slot_num_per_ssd_path: int | *8
		
	// Remove the completed mtmv job after this expired time. Unit second.
	scheduler_mtmv_job_expired: int | *86400

	// Remove the finished mtmv task after this expired time. Unit second.
	scheduler_mtmv_task_expired: int | *86400

	// When set to true, if a query is unable to select a healthy replica, the detailed information of all the replicas of the tablet, including the specific reason why they are unqueryable, will be printed out.	
	show_details_for_unaccessible_tablet: bool | *true

	// If set to TRUE, the compaction slower replica will be skipped when select get queryable replicas.
	skip_compaction_slower_replica: bool | *true

	// Spark dir for Spark Load
	spark_home_default_dir: string | *"/opt/apache-doris/fe/lib/spark2x"

	// Default timeout for spark load job, in seconds.
	spark_load_default_timeout_second: int | *86400

	// The maximum difference in the number of splits between nodes. If this number is exceeded, the splits will be redistributed.
	split_assigner_max_split_num_variance: int | *1

	// The consistent hash algorithm has the smallest number of candidates and will select the most idle node.
	split_assigner_min_consistent_hash_candidate_num: int | *2

	// The random algorithm has the smallest number of candidates and will select the most idle node.
	split_assigner_min_random_candidate_num: int | *2

	// Local node soft affinity optimization. Prefer local replication node
	split_assigner_optimized_local_scheduling: bool | *true

	// When file cache is enabled, the number of virtual nodes of each node in the consistent hash algorithm. The larger the value, the more uniform the distribution of the hash algorithm, but it will increase the memory overhead.
	split_assigner_virtual_node_number: int | *256

	// If capacity of disk reach the 'storage_flood_stage_usage_percent' and 'storage_flood_stage_left_capacity_bytes' the following operation will be rejected: 1. load job 2. restore job
	storage_flood_stage_left_capacity_bytes: int | *1073741824
	
	// If capacity of disk reach the 'storage_flood_stage_usage_percent' and 'storage_flood_stage_left_capacity_bytes' the following operation will be rejected: 1. load job 2. restore job
	storage_flood_stage_usage_percent: int | *95

	// 'storage_high_watermark_usage_percent' limit the max capacity usage percent of a Backend storage path. 'storage_min_left_capacity_bytes' limit the minimum left capacity of a Backend storage path. If both limitations are reached, this storage path can not be chose as tablet balance destination. But for tablet recovery, we may exceed these limit for keeping data integrity as much as possible.
	storage_high_watermark_usage_percent: int | *85

	// 'storage_high_watermark_usage_percent' limit the max capacity usage percent of a Backend storage path. 'storage_min_left_capacity_bytes' limit the minimum left capacity of a Backend storage path. If both limitations are reached, this storage path can not be chose as tablet balance destination. But for tablet recovery, we may exceed these limit for keeping data integrity as much as possible.
	storage_min_left_capacity_bytes: int | *2147483648

	// Whether to enable memtable on sink node by default in stream load
	stream_load_default_memtable_on_sink_node: bool | *false

	// Default pre-commit timeout for stream load job, in seconds
	stream_load_default_precommit_timeout_second: int | *3600

	// Default timeout for stream load job, in seconds.
	stream_load_default_timeout_second: int | *259200

	// For some high frequency load jobs such as INSERT, STREAMING LOAD, ROUTINE_LOAD_TASK, DELETE, Remove the finished job or task if expired. The removed job or task can be reused
	streaming_label_keep_max_second: int | *43200

	// The max duration of a tablet stream load job, in seconds.
	sts_duration: int | *3600

	// Maximal intervals between two sync job's commits 
	sync_commit_interval_second: int | *10

	// The timeout for FE Follower/Observer synchronizing an image file from the FE Master, can be adjusted by the user on the size of image file in the ${meta_dir}/image and the network environment between nodes. The default values is 300
	sync_image_timeout_second: int | *300

	// The max length of table name.
	table_name_length_limit: int | *64

	// Maximal waiting time for creating a single replica, in seconds. If you create a table with #m tablets and #n replicas for each tablet, the create table request will run at most.
	tablet_create_timeout_second: int | *2

	// The same meaning as `tablet_create_timeout_second`, but used when delete a tablet.
	tablet_delete_timeout_second: int | *2
	
	// Clone a tablet, further repair max times.
	tablet_further_repair_max_times: int | *5

	// Clone a tablet, further repair timeout.
	tablet_further_repair_timeout_second: int | *1200

	// If tablet loaded txn failed recently, it will get higher priority to repair.
	tablet_recent_load_failed_second: int | *1800

	// The factor of delay time before deciding to repair tablet. If priority is VERY_HIGH, repair it immediately. HIGH, delay tablet_repair_delay_factor_second * 1; NORMAL: delay tablet_repair_delay_factor_second * 2; LOW: delay tablet_repair_delay_factor_second * 3.
	tablet_repair_delay_factor_second: int | *60

	// Base time for higher tablet scheduler task, set this config value bigger if want the high priority effect last longer.
	tablet_schedule_high_priority_second: int | *1800

	// If disk usage > balance_load_score_threshold + urgent_disk_usage_extra_threshold, then this disk need schedule quickly, this value could less than 0.
	urgent_balance_disk_usage_extra_threshold: float | *0.05

	// The percentage of disk usage that will be considered as urgent balance.
	urgent_balance_pick_large_disk_usage_percentage: int & >0 & <100 | * 80

	// The threshold of tablet number that will be considered as urgent balance.
	urgent_balance_pick_large_tablet_num_threshold: float | *1000.0

	// When run urgent disk balance, shuffle the top large tablets with this percentage.
	urgent_balance_shuffle_large_tablet_percentage: int & >0 & <100 | * 1
	
	// If set to true, the thrift structure of query plan will be sent to BE in compact mode.
	use_compact_thrift_rpc: bool | *true

	// Set session variables randomly to check more issues in github workflow.
	use_fuzzy_session_variable: bool | *false

	// Whether to use mysql's bigint type to return Doris's largeint type
	use_mysql_bigint_for_largeint: bool | *false

	// The max diff of disk capacity used percent between BE. It is used for calculating load score of a backend.
	used_capacity_percent_max_diff: float | * 0.30

	// The valid ratio threshold of the difference between the version count of the slowest replica and the fastest replica. If repair_slow_replica is set to true, it is used to determine whether to repair the slowest replica
	valid_version_count_delta_ratio_between_replicas: float | * 0.5

	// Wait for the internal batch to be written before returning insert into and stream load use group commit by default.
	wait_internal_group_commit_finish: bool | *false

	// The max number of workload groups.
	workload_group_max_num: int | *15

	// The max number of actions in a policy.
	workload_max_action_num_in_policy: int | *5

	// The max number of conditions in a policy.
	workload_max_condition_num_in_policy: int | *5

	// The max number of policies.
	workload_max_policy_num: int | *25

	// The interval of checking the runtime status of a workload group, in milliseconds.
	workload_runtime_status_thread_interval_ms: int | *2000

	// The interval of scheduling a workload group, in milliseconds.
	workload_sched_policy_interval_ms: int | *1000

	// STATIC parameters
	// The path of the user-defined configuration file, used to store fe_custom.conf. The configuration in this file will override the configuration in fe.conf
	custom_config_dir: string | *"/opt/apache-doris/fe/conf"

	// The port of FE Arrow-Flight-SQL server
	arrow_flight_sql_port: int | *-1

	// The directory to save Doris meta data
	meta_dir: string | *"/opt/apache-doris/fe/doris-meta"

	// The path of the FE log file, used to store fe.log. This parameter is deprecated. Use the LOG_DIR environment variable instead.
	sys_log_dir: string | *"/opt/apache-doris/fe/log"

	// The level of FE log
	sys_log_level: string & ("INFO" | "WARN" | "ERROR" | "FATAL") | *"INFO"
	
	// The path of the FE audit log file, used to store fe.audit.log
	audit_log_dir: string | *"/opt/apache-doris/fe/log"
	
	// The port of FE MySQL server
	query_port: int | *9030

	// The port of FE thrift server
	rpc_port: int | *9020

	// The port of BDBJE
	edit_log_port: int | *9010

	// Fe http port, currently all FE's http port must be same
	http_port: int | *8030

	// Fe https port, currently all FE's https port must be same
	https_port: int | *8050

	// Set the specific domain name that allows cross-domain access. By default, any domain name is allowed cross-domain access
	access_control_allowed_origin_domain: string | *"*"
		
	// Specify the default authentication class of internal catalog
	access_controller_type: string | *"default"

	// For some test case, we may need to create a table with multi replicas. DO NOT use it for production env.
	allow_replica_on_same_host: bool | *false

	// Determine the persist number of automatic triggered analyze job execution status
	analyze_record_limit: int | *20000
	
	// The alive time of the user token in Arrow Flight Server, expire after write, unit minutes, the default value is 4320, which is 3 days
	arrow_flight_token_alive_time: int | *4320

	// The maximum number of user tokens cached in Arrow Flight Server, which are eliminated according to LRU rules after exceeding the limit, the default value is 512, the mandatory limit is less than qe_max_connection/2 to avoid `Reach limit of connections`, because arrow flight sql is a stateless protocol, the connection is usually not actively disconnected, bearer token is evict from the cache will unregister ConnectContext.
	arrow_flight_token_cache_size: int | *512
	
	// The loading load task executor pool size. This pool size limits the max running loading load tasks. Currently, it only limits the loading load task of broker load.
	async_loading_load_task_pool_size: int | *10
	
	// The pending load task executor pool size. This pool size limits the max running pending load tasks. Currently, it only limits the pending load task of broker load and spark load. It should be less than `max_running_txn_num_per_db`
	async_pending_load_task_pool_size: int | *10

	// The number of threads used to consume async tasks. @See TaskDisruptor if we have a lot of async tasks, we need more threads to consume them. Sure, it's depends on the cpu cores.
	async_task_consumer_thread_num: int | *64
	
	// The number of async tasks that can be queued. @See TaskDisruptor if consumer is slow, the queue will be full, and the producer will be blocked.
	async_task_queen_size: int | *1024

	// The maximum survival time of the FE audit log file. After exceeding this time, the log file will be deleted. Supported formats include: 7d, 10h, 60m, 120s
	audit_log_delete_age: string | *"30d"

	// enable compression for FE audit log file
	audit_log_enable_compress: bool | *false

	// The type of FE audit log file
	audit_log_modules: string | *'["slow_query", "query", "load", "stream_load"]'
	
	// The split cycle of the FE audit log file
	audit_log_roll_interval: string & ("DAY" | "HOUR") | *"DAY"
	
	// The maximum number of FE audit log files. After exceeding this number, the oldest log file will be deleted
	audit_log_roll_num: int | *90

	// No description found in fe_config.java
	audit_sys_accumulated_file_size: int | *4
	
	// Cluster token used for internal authentication.
	auth_token: string | *""
	
	// Specifies the authentication type
	authentication_type: string & ("ldap" | "default") | *"default"

	// The maximum number of simultaneously running analyze tasks.
	auto_analyze_simultaneously_running_task_num: int | *1
	
	// BackendServiceProxy pool size for pooling GRPC channels.
	backend_proxy_num: int | *48

	// Timeout for backend RPC requests, unit milliseconds
	backend_rpc_timeout_ms: int | *60000

	// Plugins' path for BACKUP and RESTORE operations. Currently deprecated.
	backup_plugin_path: string | *"/tools/trans_file_tool/trans_files.sh"
	
	// BDBJE file logging level
	bdbje_file_logging_level: string & ("INFO" | "OFF" | "SEVERE" | "WARNING" | "CONFIG" | "FINE" | "FINER" | "FINEST" | "ALL") | *"INFO"
	
	// Amount of free disk space required by BDBJE. If the free disk space is less than this value, BDBJE will not be able to write.
	bdbje_free_disk_bytes: int | *1073741824
		
	// The heartbeat timeout for bdbje. The default is 30 seconds, which is same as default value in bdbje. If the network is experiencing transient problems, of some unexpected long java GC annoying you, you can try to increase this value to decrease the chances of false timeouts
	bdbje_heartbeat_timeout_second: int | *30
	
	// The lock timeout of bdbje operation, in seconds. If there are many LockTimeoutException in FE WARN log, you can try to increase this value
	bdbje_lock_timeout_second: int | *5
	
	// The replica ack timeout of bdbje between master and follower, in seconds. If there are many ReplicaWriteException in FE WARN log, you can try to increase this value
	bdbje_replica_ack_timeout_second: int | *10
	
	// The desired upper limit on the number of bytes of reserved space to retain in a replicated JE Environment. This parameter is ignored in a non-replicated JE Environment.
	bdbje_reserved_disk_bytes: int | *1073741824
	
	// The timeout of RPC between FE and Broker, in milliseconds
	broker_timeout_ms: int | *10000
		
	// Whether to ignore the minimum erase latency when erasing catalog trash.
	catalog_trash_ignore_min_erase_latency: bool | *false
		
	// The number of threads used to consume CBO concurrency statistics tasks.
	cbo_concurrency_statistics_task_num: int | *10

	// If set to true, Doris will check if the compiled and running versions of Java are compatible
	check_java_version: bool | *true
	
	// Whether to check table lock leaky
	check_table_lock_leaky: bool | *false

	// the timeout threshold of checking wal_queue on be(ms)
	check_wal_queue_timeout_threshold: int | *180000

	// The interval time to check cloud cluster status(second)
	cloud_cluster_check_interval_second: int | *10

	// The maximum number of times to retry a failed RPC call to the cloud meta service.
	cloud_meta_service_rpc_failed_retry_times: int | *200

	// The cluster ID of the SQL Server cluster in the cloud.
	cloud_sql_server_cluster_id: string | *"RESERVED_CLUSTER_ID_FOR_SQL_SERVER"

	// The cluster name of the SQL Server cluster in the cloud.
	cloud_sql_server_cluster_name: string | *"RESERVED_CLUSTER_NAME_FOR_SQL_SERVER"
		
	// The unique ID of the cloud cluster.
	cloud_unique_id: string | *""

	// Cluster id used for internal authentication. Usually a random integer generated when master FE start at first time. You can also specify one.
	cluster_id: int | *-1

	// The CPU resource limit per analyze task.
	cpu_resource_limit_per_analyze_task: int | *1

	// The interval time to update the used data quota of the cloud cluster(second)
	db_used_data_quota_update_interval_secs: int | *300
	
	// Deadlock detection interval time, unit minute
	deadlock_detection_interval_minute: int | *5

	// The default timeout for getting the version from the cloud meta service(second)
	default_get_version_from_ms_timeout_second: int | *3

	// The interval time to schedule the default schema change task(millisecond)
	default_schema_change_scheduler_interval_millisecond: int | *500

	// When create a table(or partition), you can specify its storage medium(HDD or SSD).
	// If not specified, the default medium specified by this configuration will be used.
	default_storage_medium: string | *"HDD"
	
	// Whether to disable mini load, disabled by default
	disable_mini_load: bool | *true

	// The number of bytes to reduce in each DPP job.
	dpp_bytes_per_reduce: int | *104857600

	// The configuration string for DPP jobs.
	dpp_config_str: string | *"{palo-dpp : {hadoop_palo_path : '/dir',hadoop_configs : 'fs.default.name=hdfs://host:port;mapred.job.tracker=host:port;hadoop.job.ugi=user,password'}}"

	// The default cluster name for DPP jobs.
	dpp_default_cluster: string | *"palo-dpp"

	// The default configuration string for DPP jobs.
	dpp_default_config_str: string | *"{hadoop_configs : 'mapred.job.priority=NORMAL;mapred.job.map.capacity=50;mapred.job.reduce.capacity=50;mapred.hce.replace.streaming=false;abaci.long.stored.job=true;dce.shuffle.enable=false;dfs.client.authserver.force_stop=true;dfs.client.auth.method=0'}"
		
	// The path to the Hadoop client binary.
	dpp_hadoop_client_path: string | *"/lib/hadoop-client/hadoop/bin/hadoop"

	// The storage type of the metadata log. BDB: Logs are stored in BDBJE. LOCAL: logs are stored in a local file (for testing only)
	edit_log_type: string | *"bdb"

	// If set to true, FE will be started in BDBJE debug mode
	enable_bdbje_debug_mode: bool | *false

	// Whether to enable cloud snapshot version.
	enable_cloud_snapshot_version: bool | *true

	// Whether to enable concurrent update.
	enable_concurrent_update: bool | *false

	// Temporary config filed, will make all olap tables enable light schema change
	enable_convert_light_weight_schema_change: bool | *false
	
	// Whether to enable deadlock detection
	enable_deadlock_detection: bool | *false
	
	// is enable debug points, use in test.
	enable_debug_points: bool | *false
		
	// Whether to delete existing files when creating a table.
	enable_delete_existing_files: bool | *false

	// Whether to enable deploy manager.
	enable_deploy_manager: string | *"disable"
	
	// Whether to use file to record log. When starting FE with --console, all logs will be written to both standard output and file. Close this option will no longer use file to record log.
	enable_file_logger: bool | *true

	// Whether to enable the function of getting log files through http interface
	enable_get_log_file_api: bool | *false

	// If set to true, doris will automatically synchronize hms metadata to the cache in fe.
	enable_hms_events_incremental_sync: bool | *false
		
	// Whether to enable http server v2.
	enable_http_server_v2: bool | *true

	// Used to enable java_udf, default is true. if this configuration is false, creation and use of java_udf is disabled.
	enable_java_udf: bool | *true
	
	// If set to true, we will allow the interval unit to be set to second, when creating a recurring job.
	enable_job_schedule_second_for_test: bool | *false
	
	// If set to true, metric collector will be run as a daemon timer to collect metrics at fix interval
	enable_metric_calculator: bool | *true
	
	// Controls whether multiple tags are enabled for the system
	enable_multi_tags: bool | *false
	
	// Whether to allow the outfile function to export the results to the local disk.
	enable_outfile_to_local: bool | *false
	
	// Whether to enable proxy protocol
	enable_proxy_protocol: bool | *false
	
	// Storage policy feature control
	enable_storage_policy: bool | *true
	
	// Controls STS VPC access
	enable_sts_vpc: bool | *true
	
	// Controls token validation
	enable_token_check: bool | *true
	
	// Elasticsearch state sync interval in seconds
	es_state_sync_interval_second: int | *10
	
	// Whether to enable HTTP authentication for all endpoints
	enable_all_http_auth: bool | *false
	
	// Whether to enable binlog feature
	enable_feature_binlog: bool | *false
	
	// Whether to use FQDN mode for node identification
	enable_fqdn_mode: bool | *false
	
	// Whether to enable HTTPS for web UI and API endpoints
	enable_https: bool | *false
	
	// If set to true, doris will establish an encrypted channel based on the SSL protocol with mysql.
	enable_ssl: bool | *false

	// Set the maximum byte length of binlog message
	max_binlog_messsage_size: int | *1073741824 // 1GB

	// External cache expiration time in minutes after access
	external_cache_expire_time_minutes_after_access: int | *10

	// Maximum seconds to save finished jobs
	finish_job_max_saved_second: int | *259200 // 3 days

	// Threshold time in hours for cleaning up finished jobs
	finished_job_cleanup_threshold_time_hour: int | *24

	// Whether to forbid running ALTER jobs
	forbid_running_alter_job: bool | *false

	// Force SQLServer Jdbc Catalog encrypt to false
	force_sqlserver_jdbc_encrypt_false: bool | *false

	// Default value for group commit data bytes
	group_commit_data_bytes_default_value: int | *134217728 // 128MB

	// Default value for group commit interval in milliseconds
	group_commit_interval_ms_default_value: int | *10000 // 10 seconds

	// Seconds to keep gRPC connection alive
	grpc_keep_alive_second: int | *10

	// Maximum gRPC message size in bytes
	grpc_max_message_size_bytes: int | *2147483647 // 2GB

	// Number of threads in gRPC thread manager
	grpc_threadmgr_threads_nums: int | *4096

	// Heartbeat interval in seconds
	heartbeat_interval_second: int | *10

	// Queue size to store heartbeat task in heartbeat_mgr
	heartbeat_mgr_blocking_queue_size: int | *1024

	// Number of threads to handle heartbeat events
	heartbeat_mgr_threads_num: int | *8

	// Polling interval for HMS events in milliseconds
	hms_events_polling_interval_ms: int | *10000

	// Extra base path for HTTP API
	http_api_extra_base_path: string | *""

	// Maximum number of worker threads for HTTP load submitter
	http_load_submitter_max_worker_threads: int | *2

	// Maximum number of worker threads for HTTP SQL submitter
	http_sql_submitter_max_worker_threads: int | *2

	// Whether to ignore BDBJE log checksum read
	ignore_bdbje_log_checksum_read: bool | *false

	// Whether to ignore unknown metadata module
	ignore_unknown_metadata_module: bool | *false

	// Accumulated file size for info system
	info_sys_accumulated_file_size: int | *4

	// Initial password for root user
	initial_root_password: string | *""

	// Safe path for JDBC driver, default is "*" to allow all
	jdbc_driver_secure_path: string | *"*"

	// The path to save jdbc drivers
	jdbc_drivers_dir: string | *"/opt/apache-doris/fe/jdbc_drivers"

	// MySQL Jdbc Catalog mysql does not support pushdown functions
	jdbc_mysql_unsupported_pushdown_functions: string | *'["date_trunc", "money_format", "negative"]'

	// Number of acceptors for Jetty server
	jetty_server_acceptors: int | *2

	// Maximum HTTP header size for Jetty server
	jetty_server_max_http_header_size: int | *1048576

	// Maximum HTTP post size for Jetty server
	jetty_server_max_http_post_size: int | *104857600 // 100MB

	// Number of selectors for Jetty server
	jetty_server_selectors: int | *4

	// Number of workers for Jetty server
	jetty_server_workers: int | *0

	// Maximum threads in Jetty thread pool
	jetty_threadPool_maxThreads: int | *400

	// Minimum threads in Jetty thread pool
	jetty_threadPool_minThreads: int | *20

	// Queue size for job dispatch timer
	job_dispatch_timer_job_queue_size: int | *1024

	// Number of threads for job dispatch timer
	job_dispatch_timer_job_thread_num: int | *2

	// Number of threads for insert task consumer
	job_insert_task_consumer_thread_num: int | *10

	// Number of threads for MTMV task consumer
	job_mtmv_task_consumer_thread_num: int | *10
	
	// The alias of the key store certificate
	key_store_alias: string | *"doris_ssl_certificate"
	
	// The password of the key store
	key_store_password: string | *""
	
	// The path of the key store
	key_store_path: string | *"/opt/apache-doris/fe/conf/ssl/doris_ssl_certificate.keystore"
	
	// The type of the key store
	key_store_type: string | *"JKS"
	
	// The interval for cleaning labels in seconds
	label_clean_interval_second: int | *3600
	
	// The maximum length of label regex
	label_regex_length: int | *128
	
	// The admin name for LDAP authentication
	ldap_admin_name: string | *"cn=admin,dc=domain,dc=com"
	
	// Whether to enable LDAP authentication
	ldap_authentication_enabled: bool | *false
	
	// The base DN for LDAP group search
	ldap_group_basedn: string | *"ou=group,dc=domain,dc=com"
	
	// The LDAP server host
	ldap_host: string | *"127.0.0.1"
	
	// The maximum number of active connections in the LDAP connection pool
	ldap_pool_max_active: int | *8
	
	// The maximum number of idle connections in the LDAP connection pool
	ldap_pool_max_idle: int | *8
	
	// The maximum total number of connections in the LDAP connection pool
	ldap_pool_max_total: int | *-1
	
	// The maximum wait time in milliseconds for obtaining a connection from the LDAP pool
	ldap_pool_max_wait: int | *-1
	
	// The minimum number of idle connections in the LDAP connection pool
	ldap_pool_min_idle: int | *0
	
	// Whether to test connections when borrowing from the LDAP pool
	ldap_pool_test_on_borrow: bool | *false
	
	// Whether to test connections when returning to the LDAP pool
	ldap_pool_test_on_return: bool | *false
	
	// Whether to test idle connections in the LDAP pool
	ldap_pool_test_while_idle: bool | *false
	
	// The behavior when the LDAP connection pool is exhausted
	ldap_pool_when_exhausted: int | *1

	// The LDAP server port
	ldap_port: int | *389
	
	// The base DN for LDAP user search
	ldap_user_basedn: string | *"ou=people,dc=domain,dc=com"

	// The filter for LDAP user search
	ldap_user_filter: string | *"(&(uid={login}))"

	// The interval in seconds for checking load jobs
	load_checker_interval_second: int | *5

	// The runtime locale when executing commands
	locale: string | *"zh_CN.UTF-8"

	// The threshold in milliseconds for reporting lock acquisition time
	lock_reporting_threshold_ms: int | *500

	// The maximum size of log files in MB before rolling
	log_roll_size_mb: int | *1024

	// The strategy for log file rollover
	log_rollover_strategy: string | *"age"

	// Whether table names are stored in lowercase (0: case sensitive, 1: lowercase, 2: case insensitive)
	lower_case_table_names: int | *0

	// The synchronization policy for master operations (SYNC, NO_SYNC, WRITE_NO_SYNC)
	master_sync_policy: string | *"SYNC"

	// The maximum number of agent task threads
	max_agent_task_threads_num: int | *4096

	// The maximum allowed clock delta in milliseconds for BDB JE
	max_bdbje_clock_delta_ms: int | *5000
	
	// Maximum version number of BE execution
	max_be_exec_version: int | *5

	// Maximum size of thread pool for external cache loader
	max_external_cache_loader_thread_pool_size: int | *64

	// Maximum number of external file cache entries
	max_external_file_cache_num: int | *10000

	// Maximum number of external schema cache entries
	max_external_schema_cache_num: int | *10000

	// Maximum number of external table cache entries
	max_external_table_cache_num: int | *1000

	// Maximum number of external table row count cache entries
	max_external_table_row_count_cache_num: int | *100000

	// Maximum number of Hive list partitions (-1 means no limit)
	max_hive_list_partition_num: int | *-1

	// Maximum number of Hive partition cache entries
	max_hive_partition_cache_num: int | *10000
	
	// Maximum number of Hive partition table cache entries
	max_hive_partition_table_cache_num: int | *1000

	// Maximum number of meta object cache entries
	max_meta_object_cache_num: int | *1000

	// Maximum number of MySQL service task threads
	max_mysql_service_task_threads_num: int | *4096

	// Maximum number of persistence tasks
	max_persistence_task_count: int | *100

	// Maximum number of remote file system cache entries
	max_remote_file_system_cache_num: int | *100

	// Maximum number of synchronization task threads
	max_sync_task_threads_num: int | *10

	// Toleration time in seconds for meta delay (default: 300 seconds = 5 minutes)
	meta_delay_toleration_second: int | *300

	// Timeout in milliseconds for meta publish operations
	meta_publish_timeout_ms: int | *1000

	// MetaService endpoint in format "ip:port", e.g., "192.0.0.10:8866"
	meta_service_endpoint: string | *""

	// Minimum version number of BE execution
	min_be_exec_version: int | *0

	// Number of in-memory records for MySQL load
	mysql_load_in_memory_record: int | *20

	// Secure path for MySQL load server
	mysql_load_server_secure_path: string | *""

	// Thread pool size for MySQL load
	mysql_load_thread_pool: int | *4

	// Backlog number for MySQL NIO
	mysql_nio_backlog_num: int | *1024

	
	// Number of IO threads for MySQL service
	mysql_service_io_threads_num: int | *4

	// Path to the default CA certificate for MySQL SSL
	mysql_ssl_default_ca_certificate: string | *"/opt/apache-doris/fe/mysql_ssl_default_certificate/ca_certificate.p12"

	// Password for the default CA certificate
	mysql_ssl_default_ca_certificate_password: string | *"doris"

	// Path to the default server certificate for MySQL SSL
	mysql_ssl_default_server_certificate: string | *"/opt/apache-doris/fe/mysql_ssl_default_certificate/server_certificate.p12"

	// Password for the default server certificate
	mysql_ssl_default_server_certificate_password: string | *"doris"

	// Directory for storing Nereids trace logs
	nereids_trace_log_dir: string | *"/opt/apache-doris/fe/log/nereids_trace"

	// Interval in seconds for updating partition information
	partition_info_update_interval_secs: int | *60

	// Number of simultaneously running tasks for period analyze
	period_analyze_simultaneously_running_task_num: int | *1

	// Directory for Doris plugins
	plugin_dir: string | *"/opt/apache-doris/fe/plugins"

	// Timeout in milliseconds for point queries
	point_query_timeout_ms: int | *10000

	// Comma-separated list of CIDR network segments for priority networks
	priority_networks: string | *""

	// Enable proxy authentication
	proxy_auth_enable: bool | *false

	// Magic prefix for proxy authentication
	proxy_auth_magic_prefix: string | *"x@8"

	// Interval in milliseconds for publishing versions
	publish_version_interval_ms: int | *10

	
	// The maximum number of connections allowed for query engine
	qe_max_connection: int | *1024

	// The size of the Ranger cache
	ranger_cache_size: int | *10000

	// The policy for replica acknowledgment: ALL, NONE, SIMPLE_MAJORITY
	replica_ack_policy: string | *"SIMPLE_MAJORITY"

	// The policy for replica synchronization: SYNC, NO_SYNC, WRITE_NO_SYNC
	replica_sync_policy: string | *"SYNC"

	// Whether to skip authentication check for localhost connections
	skip_localhost_auth_check: bool | *true

	// The directory for storing small files
	small_file_dir: string | *"/opt/apache-doris/fe/small_files"

	// The version of Spark DPP (Data Processing Pipeline)
	spark_dpp_version: string | *"1.2-SNAPSHOT"

	// The directory for Spark launcher logs
	spark_launcher_log_dir: string | *"/opt/apache-doris/fe/log/spark_launcher_log"

	// The interval in seconds for checking Spark load tasks
	spark_load_checker_interval_second: int | *60

	// The path for Spark resources
	spark_resource_path: string | *""

	// Whether to force client authentication for SSL connections
	ssl_force_client_auth: bool | *false

	// The type of SSL trust store
	ssl_trust_store_type: string | *"PKCS12"

	// The number of statistics tasks that can run simultaneously
	statistics_simultaneously_running_task_num: int | *3

	// The memory limit in bytes for statistics SQL queries
	statistics_sql_mem_limit_in_bytes: int | *2147483648

	// The number of parallel execution instances for statistics SQL queries
	statistics_sql_parallel_exec_instance_num: int | *1

	// The size of the statistics cache
	stats_cache_size: int | *500000

	// The interval in seconds for synchronization checking
	sync_checker_interval_second: int | *5
	// The maximum survival time of the FE log file. After exceeding this time, the log file will be deleted. Supported formats include: 7d, 10h, 60m, 120s
	sys_log_delete_age: string | *"7d"

	// enable compression for FE log file
	sys_log_enable_compress: bool | *false
		
	// The output mode of FE log. 
	sys_log_mode: string & ("NORMAL" | "ASYNC" | "BRIEF") | *"NORMAL"
	
	// The split cycle of the FE log file
	sys_log_roll_interval: string & ("DAY" | "HOUR") | *"DAY"

	// The maximum number of FE log files. After exceeding this number, the oldest log file will be deleted
	sys_log_roll_num: int | *10

	// Verbose module. The VERBOSE level log is implemented by the DEBUG level of log4j. If set to `org.apache.doris.catalog`, the DEBUG log of the class under this package will be printed.
	sys_log_verbose_modules: string | *'[]'

	// The interval in milliseconds for tablet checking
	tablet_checker_interval_ms: int | *20000

	// The type of tablet rebalancer, default is "BeLoad"
	tablet_rebalancer_type: string | *"BeLoad"

	// The interval in milliseconds for tablet scheduling
	tablet_schedule_interval_ms: int | *1000

	// The interval in seconds for updating tablet statistics
	tablet_stat_update_interval_second: int | *60

	// The number of backlog connections for Thrift server
	thrift_backlog_num: int | *1024

	// The timeout in milliseconds for Thrift client
	thrift_client_timeout_ms: int | *0

	// The maximum frame size for Thrift communication
	thrift_max_frame_size: int | *16384000

	// The maximum message size for Thrift communication
	thrift_max_message_size: int | *104857600

	// The maximum number of worker threads for Thrift server
	thrift_server_max_worker_threads: int | *4096

	// The type of Thrift server, options: THREADED, THREAD_POOL
	thrift_server_type: string | *"THREAD_POOL"

	// The temporary directory for storing temporary files
	tmp_dir: string | *"/opt/apache-doris/fe/temp_dir"

	// The period in hours for token generation
	token_generate_period_hour: int | *12

	// The size of the token queue, one token will keep alive for {token_queue_size * token_generate_period_hour} hours
	token_queue_size: int | *6

	// The interval in seconds for cleaning transactions
	transaction_clean_interval_second: int | *30

	// The limit for transaction rollback operations
	txn_rollback_limit: int | *100

	// Whether to use the new tablet scheduler
	use_new_tablet_scheduler: bool | *true

	// The warning threshold for system accumulated file size in GB
	warn_sys_accumulated_file_size: int | *2

	// Whether to use Kubernetes certificates
	with_k8s_certs: bool | *false

	// The path to the YARN client
	yarn_client_path: string | *"/opt/apache-doris/fe/lib/yarn-client/hadoop/bin/yarn"

	// The directory for YARN configuration files
	yarn_config_dir: string | *"/opt/apache-doris/fe/lib/yarn-config"

	// The JAVA_OPTS startup configuration for the FE node. The default value of -Xmx is 80% of the container available memory.
	JAVA_OPTS: string | *""
}

configuration: #FEParameter & {
}
