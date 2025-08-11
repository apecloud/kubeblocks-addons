#FEParameter: {
	// DYNAMIC parameters
	// The threshold used to determine whether a query is a slow query. If the response time of a query exceeds this threshold, it is recorded as a slow query in `fe.audit.log`.
	qe_slow_log_ms: int | *5000

	// The timeout duration to obtain the global lock.
	catalog_try_lock_timeout_ms: int | *5000

	// The maximum number of metadata log entries that can be written before a log file is created for these log entries. This parameter is used to control the size of log files. The new log file is written to the BDBJE database.
	edit_log_roll_num: int | *50000

	// Whether to ignore an unknown log ID. When an FE is rolled back, the BEs of the earlier version may be unable to recognize some log IDs. If the value is `TRUE`, the FE ignores unknown log IDs. If the value is `FALSE`, the FE exits.
	ignore_unknown_log_id: bool | *false

	// Whether FE ignores the metadata exception caused by materialized view errors. If FE fails to start due to the metadata exception caused by materialized view errors, you can set this parameter to `true` to allow FE to ignore the exception. This parameter is supported from v2.5.10 onwards.
	ignore_materialized_view_error: bool | *false

	// Whether non-leader FEs ignore the metadata gap from the leader FE. If the value is TRUE, non-leader FEs ignore the metadata gap from the leader FE and continue providing data reading services. This parameter ensures continuous data reading services even when you stop the leader FE for a long period of time. If the value is FALSE, non-leader FEs do not ignore the metadata gap from the leader FE and stop providing data reading services.
	ignore_meta_check: bool | *false

	// The maximum duration by which the metadata on the follower and observer FEs can lag behind that on the leader FE. Unit: seconds. If this duration is exceeded, the non-leader FEs stops providing services.
	meta_delay_toleration_second: int | *300

	// Whether to delete a BE after the BE is decommissioned. `TRUE` indicates that the BE is deleted immediately after it is decommissioned. `FALSE` indicates that the BE is not deleted after it is decommissioned.
	drop_backend_after_decommission: bool | *true

	// Whether to collect the profile of a query. If this parameter is set to `TRUE`, the system collects the profile of the query. If this parameter is set to `FALSE`, the system does not collect the profile of the query.
	enable_collect_query_detail_info: bool | *false

	// Whether to enable the periodic Hive metadata cache refresh. After it is enabled, StarRocks polls the metastore (Hive Metastore or AWS Glue) of your Hive cluster, and refreshes the cached metadata of the frequently accessed Hive catalogs to perceive data changes. `true` indicates to enable the Hive metadata cache refresh, and `false` indicates to disable it. This parameter is supported from v2.5.5 onwards.
	enable_background_refresh_connector_metadata: bool | *true

	// The interval between two consecutive Hive metadata cache refreshes. This parameter is supported from v2.5.5 onwards.
	background_refresh_metadata_interval_millis: int | *600000

	// The expiration time of a Hive metadata cache refresh task. For the Hive catalog that has been accessed, if it has not been accessed for more than the specified time, StarRocks stops refreshing its cached metadata. For the Hive catalog that has not been accessed, StarRocks will not refresh its cached metadata. This parameter is supported from v2.5.5 onwards.
	background_refresh_metadata_time_secs_since_last_access_secs: int | *86400

	// Whether to generate profiles for statistics queries. You can set this item to `true` to allow StarRocks to generate query profiles for queries on system statistics. This parameter is supported from v3.1.5 onwards.
	enable_statistics_collect_profile: bool | *false

	// The maximum number of elements allowed for the IN predicate in a DELETE statement.
	max_allowed_in_element_num_of_delete: int | *10000

	// Whether to enable the creation of materialized views.
	enable_materialized_view: bool | *true

	// Whether to support the DECIMAL V3 data type.
	enable_decimal_v3: bool | *true

	// Whether to enable blacklist check for SQL queries. When this feature is enabled, queries in the blacklist cannot be executed.
	enable_sql_blacklist: bool | *false

	// The interval at which new data is checked. If new data is detected, StarRocks automatically creates partitions for the data.
	dynamic_partition_check_interval_seconds: int | *600

	// Whether to enable the dynamic partitioning feature. When this feature is enabled, StarRocks dynamically creates partitions for new data and automatically deletes expired partitions to ensure the freshness of data.
	dynamic_partition_enable: bool | *true

	// If the response time for an HTTP request exceeds the value specified by this parameter, a log is generated to track this request. - Introduced in: 2.5.15，3.1.5
	http_slow_request_threshold_ms: int | *5000

	// The maximum number of partitions that can be created when you bulk create partitions.
	max_partitions_in_one_batch: int | *4096

	// The maximum number of query retries on an FE.
	max_query_retry_time: int | *2

	// The maximum timeout duration for creating a table.
	max_create_table_timeout_second: int | *600

	// The maximum number of replicas to create serially. If actual replica count exceeds this, replicas will be created concurrently. Try to reduce this config if table creation is taking a long time to complete.
	create_table_max_serial_replicas: int | *128

	// The maximum number of rollup jobs can run in parallel for a table.
	max_running_rollup_job_num_per_table: int | *1

	// The maximum number of times that the optimizer can rewrite a scalar operator.
	max_planner_scalar_rewrite_num: int | *100000

	// Whether to collect statistics for the CBO. This feature is enabled by default.
	enable_statistic_collect: bool | *true

	// Whether to enable automatic full statistics collection. This feature is enabled by default.
	enable_collect_full_statistic: bool | *true

	// The threshold for determining whether the statistics for automatic collection are healthy. If statistics health is below this threshold, automatic collection is triggered.
	statistic_auto_collect_ratio: float & >=0.0 & <=1.0 | *0.8

	// The size, in bytes, of the largest partition for the automatic collection of statistics. If a partition exceeds this value, then sampled collection is performed instead of full.
	statistic_max_full_collect_data_size: int | *107374182400

	// The maximum number of rows to query for a single analyze task. An analyze task will be split into multiple queries if this value is exceeded.
	statistic_collect_max_row_count_per_query: int | *5000000000

	// The interval for checking data updates during automatic collection.
	statistic_collect_interval_sec: int | *300

	// The start time of automatic collection. Value range: `00:00:00` - `23:59:59`.
	statistic_auto_analyze_start_time: string | *"00:00:00"

	// The end time of automatic collection. Value range: `00:00:00` - `23:59:59`.
	statistic_auto_analyze_end_time: string | *"23:59:59"

	// The minimum number of rows to collect for sampled collection. If the parameter value exceeds the actual number of rows in your table, full collection is performed.
	statistic_sample_collect_rows: int | *200000

	// The default bucket number for a histogram.
	histogram_buckets_size: int | *64

	// The number of most common values (MCV) for a histogram.
	histogram_mcv_size: int | *100

	// The sampling ratio for a histogram.
	histogram_sample_ratio: float | *0.1

	// The maximum number of rows to collect for a histogram.
	histogram_max_sample_row_count: int | *10000000

	// The interval at which metadata is scheduled. The system performs the following operations based on this interval:   - Create tables for storing statistics.   - Delete statistics that have been deleted.   - Delete expired statistics.
	statistics_manager_sleep_time_sec: int | *60

	// The interval at which the cache of statistical information is updated. Unit: seconds.
	statistic_update_interval_sec: int | *(24 * 60 * 60)

	// The duration to retain the history of collection tasks. The default value is 3 days.
	statistic_analyze_status_keep_second: int | *259200

	// The maximum number of manual collection tasks that can run in parallel. The value defaults to 3, which means you can run a maximum of three manual collection tasks in parallel. If the value is exceeded, incoming tasks will be in the PENDING state, waiting to be scheduled.
	statistic_collect_concurrency: int | *3

	// Threshold to determine whether a table in an external data source (Hive, Iceberg, Hudi) is a small table during automatic collection. If the table has rows less than this value, the table is considered a small table. - Introduced in: v3.2
	statistic_auto_collect_small_table_rows: int | *10000000

	// Whether to select local replicas for queries. Local replicas reduce the network transmission cost. If this parameter is set to TRUE, the CBO preferentially selects tablet replicas on BEs that have the same IP address as the current FE. If this parameter is set to `FALSE`, both local replicas and non-local replicas can be selected. The default value is FALSE.
	enable_local_replica_selection: bool | *false

	// The maximum recursion depth allowed by the partition pruner. Increasing the recursion depth can prune more elements but also increases CPU consumption.
	max_distribution_pruner_recursion_depth: int | *100

	// Whether to enable UDF.
	enable_udf: bool | *false

	// The maximum number of concurrent Broker Load jobs allowed within the StarRocks cluster. This parameter is valid only for Broker Load. The value of this parameter must be less than the value of `max_running_txn_num_per_db`. From v2.5 onwards, the default value is changed from `10` to `5`. The alias of this parameter is `async_load_task_pool_size`.
	max_broker_load_job_concurrency: int | *5

	// The maximum loading lag that can be tolerated by a BE replica. If this value is exceeded, cloning is performed to clone data from other replicas. Unit: seconds.
	load_straggler_wait_second: int | *300

	// The maximum number of pending jobs in an FE. The number refers to all jobs, such as table creation, loading, and schema change jobs. If the number of pending jobs in an FE reaches this value, the FE will reject new load requests. This parameter takes effect only for asynchronous loading. From v2.5 onwards, the default value is changed from 100 to 1024.
	desired_max_waiting_jobs: int | *1024

	// The maximum timeout duration allowed for a load job. The load job fails if this limit is exceeded. This limit applies to all types of load jobs.
	max_load_timeout_second: int | *259200

	// The minimum timeout duration allowed for a load job. This limit applies to all types of load jobs. Unit: seconds.
	min_load_timeout_second: int | *1

	// The maximum number of load transactions allowed to be running for each database within a StarRocks cluster. The default value is `100`. When the actual number of load transactions running for a database exceeds the value of this parameter, new load requests will not be processed. New requests for synchronous load jobs will be denied, and new requests for asynchronous load jobs will be placed in queue. We do not recommend you increase the value of this parameter because this will increase system load.
	max_running_txn_num_per_db: int | *100

	// The maximum number of concurrent loading instances for each load job on a BE.
	load_parallel_instance_num: int | *1

	// Whether to disable loading when the cluster encounters an error. This prevents any loss caused by cluster errors. The default value is `FALSE`, indicating that loading is not disabled.
	disable_load_job: bool | *false

	// The maximum duration a historical job can be retained, such as schema change jobs, in seconds.
	history_job_keep_max_second: int | *604800

	// The maximum number of load jobs that can be retained within a period of time. If this number is exceeded, the information of historical jobs will be deleted.
	label_keep_max_num: int | *1000

	// The maximum duration in seconds to keep the labels of load jobs that have been completed and are in the FINISHED or CANCELLED state. The default value is 3 days. After this duration expires, the labels will be deleted. This parameter applies to all types of load jobs. A value too large consumes a lot of memory.
	label_keep_max_second: int | *259200

	// The maximum number of Routine Load jobs in a StarRocks cluster. This parameter is deprecated since v3.1.0.
	max_routine_load_job_num: int | *100

	// The maximum number of concurrent tasks for each Routine Load job.
	max_routine_load_task_concurrent_num: int | *5

	// The maximum number of concurrent Routine Load tasks on each BE. Since v3.1.0, the default value for this parameter is increased to 16 from 5, and no longer needs to be less than or equal to the value of BE static parameter `routine_load_thread_pool_size` (deprecated).
	max_routine_load_task_num_per_be: int | *16

	// The maximum amount of data that can be loaded by a Routine Load task, in bytes.
	max_routine_load_batch_size: int | *4294967296

	// The maximum time for each Routine Load task within the cluster to consume data. Since v3.1.0, Routine Load job supports a new parameter `task_consume_second` in [job_properties](../sql-reference/sql-statements/data-manipulation/CREATE_ROUTINE_LOAD.md#job_properties). This parameter applies to individual load tasks within a Routine Load job, which is more flexible.
	routine_load_task_consume_second: int | *15

	// The timeout duration for each Routine Load task within the cluster. Since v3.1.0, Routine Load job supports a new parameter `task_timeout_second` in [job_properties](../sql-reference/sql-statements/data-manipulation/CREATE_ROUTINE_LOAD.md#job_properties). This parameter applies to individual load tasks within a Routine Load job, which is more flexible.
	routine_load_task_timeout_second: int | *60

	// The maximum number of faulty BE nodes allowed. If this number is exceeded, Routine Load jobs cannot be automatically recovered.
	max_tolerable_backend_down_num: int | *0

	// The interval at which Routine Load jobs are automatically recovered.
	period_of_auto_resume_min: int | *5

	// The timeout duration for each Spark Load job, in seconds.
	spark_load_default_timeout_second: int | *86400

	// The root directory of a Spark client.
	spark_home_default_dir: string | *"/opt/starrocks/fe/lib/spark2x"

	// The default timeout duration for each Stream Load job, in seconds.
	stream_load_default_timeout_second: int | *600

	// The maximum allowed timeout duration for a Stream Load job, in seconds.
	max_stream_load_timeout_second: int | *259200

	// The timeout duration for the INSERT INTO statement that is used to load data, in seconds.
	insert_load_default_timeout_second: int | *3600

	// The timeout duration for a Broker Load job, in seconds.
	broker_load_default_timeout_second: int | *14400

	// The minimum allowed amount of data that can be processed by a Broker Load instance, in bytes.
	min_bytes_per_broker_scanner: int | *67108864

	// The maximum number of concurrent instances for a Broker Load task. This parameter is deprecated from v3.1 onwards.
	max_broker_concurrency: int | *100

	// The maximum amount of data that can be exported from a single BE by a single data unload task, in bytes.
	export_max_bytes_per_be_per_task: int | *268435456

	// The maximum number of data exporting tasks that can run in parallel.
	export_running_job_num_limit: int | *5

	// The timeout duration for a data exporting task, in seconds.
	export_task_default_timeout_second: int | *7200

	// Whether to return an error message "all partitions have no load data" if no data is loaded. Values:
	// - TRUE: If no data is loaded, the system displays a failure message and returns an error "all partitions have no load data".
	// - FALSE: If no data is loaded, the system displays a success message and returns OK, instead of an error.
	empty_load_as_error: bool | *true

	// The timeout duration for committing (publishing) a write transaction to a StarRocks external table. The default value `10000` indicates a 10-second timeout duration.
	external_table_commit_timeout_ms: int | *10000

	// Whether to synchronously execute the apply task at the publish phase of a load transaction. This parameter is applicable only to Primary Key tables. Valid values:
	// - `TRUE` (default): The apply task is synchronously executed at the publish phase of a load transaction. It means that the load transaction is reported as successful only after the apply task is completed, and the loaded data can truly be queried. When a task loads a large volume of data at a time or loads data frequently, setting this parameter to `true` can improve query performance and stability, but may increase load latency.
	// - `FALSE`: The apply task is asynchronously executed at the publish phase of a load transaction. It means that the load transaction is reported as successful after the apply task is submitted, but the loaded data cannot be immediately queried. In this case, concurrent queries need to wait for the apply task to complete or time out before they can continue. When a task loads a large volume of data at a time or loads data frequently, setting this parameter to `false` may affect query performance and stability.
	enable_sync_publish: bool | *true

	// `default_replication_num` sets the default number of replicas for each data partition when creating a table in StarRocks. This setting can be overridden when creating a table by specifying `replication_num=x` in the CREATE TABLE DDL.
	default_replication_num: int | *3

	// Whether the FE strictly checks the storage medium of BEs when users create tables. If this parameter is set to `TRUE`, the FE checks the storage medium of BEs when users create tables and returns an error if the storage medium of the BE is different from the `storage_medium` parameter specified in the CREATE TABLE statement. For example, the storage medium specified in the CREATE TABLE statement is SSD but the actual storage medium of BEs is HDD. As a result, the table creation fails. If this parameter is `FALSE`, the FE does not check the storage medium of BEs when users create a table.
	enable_strict_storage_medium_check: bool | *false

	// Whether to automatically set the number of buckets.
	// - If this parameter is set to `TRUE`, you don't need to specify the number of buckets when you create a table or add a partition. StarRocks automatically determines the number of buckets.
	// - If this parameter is set to `FALSE`, you need to manually specify the number of buckets when you create a table or add a partition. If you do not specify the bucket count when adding a new partition to a table, the new partition inherits the bucket count set at the creation of the table. However, you can also manually specify the number of buckets for the new partition. Starting from version 2.5.7, StarRocks supports setting this parameter.
	enable_auto_tablet_distribution: bool | *true

	// If the storage usage (in percentage) of the BE storage directory exceeds this value and the remaining storage space is less than `storage_usage_soft_limit_reserve_bytes`, tablets cannot be cloned into this directory.
	storage_usage_soft_limit_percent: int | *90

	// If the remaining storage space in the BE storage directory is less than this value and the storage usage (in percentage) exceeds `storage_usage_soft_limit_percent`, tablets cannot be cloned into this directory.
	storage_usage_soft_limit_reserve_bytes: int | *(200 * 1024 * 1024 * 1024)

	// The longest duration the metadata can be retained after a table or database is deleted. If this duration expires, the data will be deleted and cannot be recovered. Unit: seconds.
	catalog_trash_expire_second: int | *86400

	// The timeout duration for the schema change operation (ALTER TABLE). Unit: seconds.
	alter_table_timeout_second: int | *86400

	// Whether to enable fast schema evolution for all tables within the StarRocks cluster. Valid values are `TRUE` and `FALSE` (default). Enabling fast schema evolution can increase the speed of schema changes and reduce resource usage when columns are added or dropped.
	// > **NOTE**
	// > - StarRocks shared-data clusters do not support this parameter.
	// > - If you need to configure the fast schema evolution for a specific table, such as disabling fast schema evolution for a specific table, you can set the table property [`fast_schema_evolution`](../sql-reference/sql-statements/data-definition/CREATE_TABLE.md#set-fast-schema-evolution) at table creation.
	enable_fast_schema_evolution: bool | *false

	// Whether to replace a lost or corrupted tablet replica with an empty one. If a tablet replica is lost or corrupted, data queries on this tablet or other healthy tablets may fail. Replacing the lost or corrupted tablet replica with an empty tablet ensures that the query can still be executed. However, the result may be incorrect because data is lost. The default value is `FALSE`, which means lost or corrupted tablet replicas are not replaced with empty ones, and the query fails.
	recover_with_empty_tablet: bool | *false

	// The timeout duration for creating a tablet, in seconds.
	tablet_create_timeout_second: int | *10

	// The timeout duration for deleting a tablet, in seconds.
	tablet_delete_timeout_second: int | *2

	// The timeout duration for a replica consistency check. You can set this parameter based on the size of your tablet.
	check_consistency_default_timeout_second: int | *600

	// The maximum number of tablet-related tasks that can run concurrently in a BE storage directory. The alias is `schedule_slot_num_per_path`. From v2.5 onwards, the default value of this parameter is changed from `4` to `8`.
	tablet_sched_slot_num_per_path: int | *8

	// The maximum number of tablets that can be scheduled at the same time. If the value is exceeded, tablet balancing and repair checks will be skipped.
	tablet_sched_max_scheduling_tablets: int | *10000

	// Whether to disable tablet balancing. `TRUE` indicates that tablet balancing is disabled. `FALSE` indicates that tablet balancing is enabled. The alias is `disable_balance`.
	tablet_sched_disable_balance: bool | *false

	// Whether to disable replica balancing for Colocate Table. `TRUE` indicates replica balancing is disabled. `FALSE` indicates replica balancing is enabled. The alias is `disable_colocate_balance`.
	tablet_sched_disable_colocate_balance: bool | *false

	// The maximum number of tablets that can be balanced at the same time. If this value is exceeded, tablet re-balancing will be skipped. The alias is `max_balancing_tablets`.
	tablet_sched_max_balancing_tablets: int | *500

	// The threshold for determining whether the BE disk usage is balanced. This parameter takes effect only when `tablet_sched_balancer_strategy` is set to `disk_and_tablet`. If the disk usage of all BEs is lower than 50%, disk usage is considered balanced. For the `disk_and_tablet` policy, if the difference between the highest and lowest BE disk usage is greater than 10%, disk usage is considered unbalanced and tablet re-balancing is triggered. The alias is `balance_load_disk_safe_threshold`.
	tablet_sched_balance_load_disk_safe_threshold: float | *0.5

	// The threshold for determining whether the BE load is balanced. This parameter takes effect only when `tablet_sched_balancer_strategy` is set to `be_load_score`. A BE whose load is 10% lower than the average load is in a low load state, and a BE whose load is 10% higher than the average load is in a high load state. The alias is `balance_load_score_threshold`.
	tablet_sched_balance_load_score_threshold: float | *0.1

	// The interval at which replicas are repaired, in seconds. The alias is `tablet_repair_delay_factor_second`.
	tablet_sched_repair_delay_factor_second: int | *60

	// The minimum timeout duration for cloning a tablet, in seconds.
	tablet_sched_min_clone_task_timeout_sec: int | *180

	// The maximum timeout duration for cloning a tablet, in seconds. The alias is `max_clone_task_timeout_sec`.
	tablet_sched_max_clone_task_timeout_sec: int | *7200

	// When the tablet clone tasks are being scheduled, if a tablet has not been scheduled for the specified time in this parameter, StarRocks gives it a higher priority to schedule it as soon as possible.
	tablet_sched_max_not_being_scheduled_interval_ms: int | *90000

	// The Compaction Score threshold that triggers Compaction operations. When the Compaction Score of a partition is greater than or equal to this value, the system performs Compaction on that partition. - **Introduced in**: v3.1.0  The Compaction Score indicates whether a partition needs Compaction and is scored based on the number of files in the partition. Excessive number of files can impact query performance, so the system periodically performs Compaction to merge small files and reduce the file count. You can check the Compaction Score for a partition based on the `MaxCS` column in the result returned by running [SHOW PARTITIONS](../sql-reference/sql-statements/data-manipulation/SHOW_PARTITIONS.md).
	lake_compaction_score_selector_min_score: float | *10.0

	// The maximum number of concurrent Compaction tasks allowed. - **Introduced in**: v3.1.0  The system calculates the number of Compaction tasks based on the number of tablets in a partition. For example, if a partition has 10 tablets, performing one Compaction on that partition creates 10 Compaction tasks. If the number of concurrently executing Compaction tasks exceeds this threshold, the system will not create new Compaction tasks. Setting this item to `0` disables Compaction, and setting it to `-1` allows the system to automatically calculate this value based on an adaptive strategy.
	lake_compaction_max_tasks: int | *-1

	// The number of recent successful Compaction task records to keep in the memory of the Leader FE node. You can view recent successful Compaction task records using the `SHOW PROC '/compactions'` command. Note that the Compaction history is stored in the FE process memory, and it will be lost if the FE process is restarted. - **Introduced in**: v3.1.0
	lake_compaction_history_size: int | *12

	// The number of recent failed Compaction task records to keep in the memory of the Leader FE node. You can view recent failed Compaction task records using the `SHOW PROC '/compactions'` command. Note that the Compaction history is stored in the FE process memory, and it will be lost if the FE process is restarted. - **Introduced in**: v3.1.0
	lake_compaction_fail_history_size: int | *12

	// The maximum number of threads for Version Publish tasks. - **Introduced in**: v3.2.0
	lake_publish_version_max_threads: int | *512

	// The maximum number of partitions that can undergo AutoVacuum simultaneously. AutoVaccum is the Garbage Collection after Compactions. - **Introduced in**: v3.1.0
	lake_autovacuum_parallel_partitions: int | *8

	// The minimum interval between AutoVacuum operations on the same partition. - **Introduced in**: v3.1.0
	lake_autovacuum_partition_naptime_seconds: int | *180

	// The time range for retaining historical data versions. Historical data versions within this time range are not automatically cleaned via AutoVacuum after Compactions. You need to set this value greater than the maximum query time to avoid that the data accessed by running queries get deleted before the queries finish. - **Introduced in**: v3.1.0
	lake_autovacuum_grace_period_minutes: int | *5

	// If a partition has no updates (loading, DELETE, or Compactions) within this time range, the system will not perform AutoVacuum on this partition. - **Introduced in**: v3.1.0
	lake_autovacuum_stale_partition_threshold: int | *12

	// Whether to enable Data Ingestion Slowdown. When Data Ingestion Slowdown is enabled, if the Compaction Score of a partition exceeds `lake_ingest_slowdown_threshold`, loading tasks on that partition will be throttled down. - **Introduced in**: v3.2.0
	lake_enable_ingest_slowdown: bool | *false

	// The Compaction Score threshold that triggers Data Ingestion Slowdown. This configuration only takes effect when `lake_enable_ingest_slowdown` is set to `true`. - **Introduced in**: v3.2.0
	lake_ingest_slowdown_threshold: int | *100

	// The ratio of the loading rate slowdown when Data Ingestion Slowdown is triggered. - **Introduced in**: v3.2.0
	lake_ingest_slowdown_ratio: float | *0.1

	// The upper limit of the Compaction Score for a partition. `0` indicates no upper limit. This item only takes effect when `lake_enable_ingest_slowdown` is set to `true`. When the Compaction Score of a partition reaches or exceeds this upper limit, all loading tasks on that partition will be indefinitely delayed until the Compaction Score drops below this value or the task times out. - **Introduced in**: v3.2.0
	lake_compaction_score_upper_bound: int | *0

	// Whether plugins can be installed on FEs. Plugins can be installed or uninstalled only on the Leader FE.
	plugin_enable: bool | *true

	// The maximum number of small files that can be stored on an FE directory.
	max_small_file_number: int | *100

	// The maximum size of a small file, in bytes.
	max_small_file_size_bytes: int | *1048576

	// The duration the FE must wait before it can resend an agent task. An agent task can be resent only when the gap between the task creation time and the current time exceeds the value of this parameter. This parameter is used to prevent repetitive sending of agent tasks. Unit: ms.
	agent_task_resend_wait_time_ms: int | *5000

	// The timeout duration of a backup job. If this value is exceeded, the backup job fails.
	backup_job_default_timeout_ms: int | *86400000

	// The maximum number of jobs that can wait in a report queue. The report is about disk, task, and tablet information of BEs. If too many report jobs are piling up in a queue, OOM will occur.
	report_queue_size: int | *100

	// Whether to enable the asynchronous materialized view feature. TRUE indicates this feature is enabled. From v2.5.2 onwards, this feature is enabled by default. For versions earlier than v2.5.2, this feature is disabled by default.
	enable_experimental_mv: bool | *true

	// The base DN, which is the point from which the LDAP server starts to search for users' authentication information.
	authentication_ldap_simple_bind_base_dn: string | *""

	// The administrator DN used to search for users' authentication information.
	authentication_ldap_simple_bind_root_dn: string | *""

	// The password of the administrator used to search for users' authentication information.
	authentication_ldap_simple_bind_root_pwd: string | *""

	// The host on which the LDAP server runs.
	authentication_ldap_simple_server_host: string | *""

	// The port of the LDAP server.
	authentication_ldap_simple_server_port: int | *389

	// The name of the attribute that identifies users in LDAP objects.
	authentication_ldap_simple_user_search_attr: string | *"uid"

	// In each BACKUP operation, the maximum number of upload tasks StarRocks assigned to a BE node. When this item is set to less than or equal to 0, no limit is imposed on the task number. This item is supported from v3.1.0 onwards.
	max_upload_task_per_be: int | *0

	// In each RESTORE operation, the maximum number of download tasks StarRocks assigned to a BE node. When this item is set to less than or equal to 0, no limit is imposed on the task number. This item is supported from v3.1.0 onwards.
	max_download_task_per_be: int | *0

	// Whether to allow users to create columns whose names are initiated with `__op` and `__row`. To enable this feaure, set this parameter to `TRUE`. Please note that these name formats are reserved for special purposes in StarRocks and creating such columns may result in undefined behavior. Therefore this feature is disabled by default. This item is supported from v3.2.0 onwards.
	allow_system_reserved_names: bool | *false

	// Whehter to enable the BACKUP and RESTORE of asynchronous materialized views when backing up or restoring a specific database. If this item is set to `false`, StarRocks will skip backing up asynchronized materialized views. This item is supported from v3.2.0 onwards.
	enable_backup_materialized_view: bool | *true

	// Whether to support colocating the synchronous materialized view index with the base table when creating a synchronous materialized view. If this item is set to `true`, tablet sink will speed up the write performance of synchronous materialized views. This item is supported from v3.2.0 onwards.
	enable_colocate_mv_index: bool | *true

	// Whether to enable the system to automatically check and re-activate the asynchronous materialized views that are set inactive because their base tables (views) had undergone Schema Change or had been dropped and re-created. Please note that this feature will not re-activate the materialized views that are manually set inactive by users. This item is supported from v3.1.6 onwards.
	enable_mv_automatic_active_check: bool | *true

	// STATIC parameters

	// The size per log file. Unit: MB. The default value `1024` specifies the size per log file as 1 GB.
	log_roll_size_mb: int | *1024

	// The directory that stores system log files.
	sys_log_dir: string | *"/opt/starrocks/fe/log"

	// The severity levels into which system log entries are classified. Valid values: `INFO`, `WARN`, `ERROR`, and `FATAL`.
	sys_log_level: *"INFO" | "WARN" | "ERROR" | "FATAL"

	// The modules for which StarRocks generates system logs. If this parameter is set to `org.apache.starrocks.catalog`, StarRocks generates system logs only for the catalog module.
	sys_log_verbose_modules: string | *""

	// The time interval at which StarRocks rotates system log entries. Valid values: `DAY` and `HOUR`.
	sys_log_roll_interval: *"DAY" | "HOUR"

	// The retention period of system log files. The default value `7d` specifies that each system log file can be retained for 7 days. StarRocks checks each system log file and deletes those that were generated 7 days ago.
	sys_log_delete_age: string | *"7d"

	// The maximum number of system log files that can be retained within each retention period specified by the `sys_log_roll_interval` parameter.
	sys_log_roll_num: int | *10

	// The directory that stores audit log files.
	audit_log_dir: string | *"/opt/starrocks/fe/log"

	// The maximum number of audit log files that can be retained within each retention period specified by the `audit_log_roll_interval` parameter.
	audit_log_roll_num: int | *90

	// The modules for which StarRocks generates audit log entries. By default, StarRocks generates audit logs for the slow_query module and the query module. Separate the module names with a comma (,) and a space.
	audit_log_modules: string | *"slow_query, query"

	// The time interval at which StarRocks rotates audit log entries. Valid values: `DAY` and `HOUR`.
	audit_log_roll_interval: *"DAY" | "HOUR"

	// The retention period of audit log files. The default value `30d` specifies that each audit log file can be retained for 30 days. StarRocks checks each audit log file and deletes those that were generated 30 days ago.
	audit_log_delete_age: string | *"30d"

	// The directory that stores dump log files.
	dump_log_dir: string | *"/opt/starrocks/fe/log"

	// The modules for which StarRocks generates dump log entries. By default, StarRocks generates dump logs for the query module. Separate the module names with a comma (,) and a space.
	dump_log_modules: string | *"query"

	// The time interval at which StarRocks rotates dump log entries. Valid values: `DAY` and `HOUR`.
	dump_log_roll_interval: *"DAY" | "HOUR"

	// The maximum number of dump log files that can be retained within each retention period specified by the `dump_log_roll_interval` parameter.
	dump_log_roll_num: int | *10

	// The retention period of dump log files. The default value `7d` specifies that each dump log file can be retained for 7 days. StarRocks checks each dump log file and deletes those that were generated 7 days ago.
	dump_log_delete_age: string | *"7d"

	// The IP address of the FE node.
	frontend_address: string | *"0.0.0.0"

	// Declares a selection strategy for servers that have multiple IP addresses. Note that at most one IP address must match the list specified by this parameter. The value of this parameter is a list that consists of entries, which are separated with semicolons (;) in CIDR notation, such as 10.10.10.0/24. If no IP address matches the entries in this list, an IP address will be randomly selected.
	priority_networks: string | *""

	// A boolean value to control whether to use IPv6 addresses preferentially when priority_networks is not specified. true indicates to allow the system to use an IPv6 address preferentially when the server that hosts the node has both IPv4 and IPv6 addresses and priority_networks is not specified.
	net_use_ipv6_when_priority_networks_empty: bool | *false

	// The port on which the HTTP server in the FE node listens.
	http_port: int | *8030

	// The length of the backlog queue held by the HTTP server in the FE node.
	http_backlog_num: int | *1024

	// The name of the StarRocks cluster to which the FE belongs. The cluster name is displayed for `Title` on the web page.
	cluster_name: string | *"StarRocks Cluster"

	// The port on which the Thrift server in the FE node listens.
	rpc_port: int | *9020

	// The length of the backlog queue held by the Thrift server in the FE node.
	thrift_backlog_num: int | *1024

	// The maximum number of worker threads that are supported by the Thrift server in the FE node.
	thrift_server_max_worker_threads: int | *4096

	// The length of time after which idle client connections time out. Unit: ms.
	thrift_client_timeout_ms: int | *5000

	// The length of queue where requests are pending. If the number of threads that are being processed in the thrift server exceeds the value specified in `thrift_server_max_worker_threads`, new requests are added to the pending queue.
	thrift_server_queue_size: int | *4096

	// The maximum length of time for which bRPC clients wait as in the idle state. Unit: ms.
	brpc_idle_wait_max_time: int | *10000

	// The port on which the MySQL server in the FE node listens.
	query_port: int | *9030

	// Specifies whether asynchronous I/O is enabled for the FE node.
	mysql_service_nio_enabled: bool | *true

	// The maximum number of threads that can be run by the MySQL server in the FE node to process I/O events.
	mysql_service_io_threads_num: int | *4

	// The length of the backlog queue held by the MySQL server in the FE node.
	mysql_nio_backlog_num: int | *1024

	// The maximum number of threads that can be run by the MySQL server in the FE node to process tasks.
	max_mysql_service_task_threads_num: int | *4096

	// The MySQL server version returned to the client. Modifying this parameter will affect the version information in the following situations:   1. `select version();`   2. Handshake packet version   3. Value of the global variable `version` (`show variables like 'version';`)
	mysql_server_version: string | *"5.1.0"

	// The maximum number of threads that are supported by the connection scheduler.
	max_connection_scheduler_threads_num: int | *4096

	// The maximum number of connections that can be established by all users to the FE node.
	qe_max_connection: int | *1024

	// Specifies whether to check version compatibility between the executed and compiled Java programs. If the versions are incompatible, StarRocks reports errors and aborts the startup of Java programs.
	check_java_version: bool | *true

	// The directory that stores metadata.
	meta_dir: string | *"/opt/starrocks/fe/meta"

	// The number of threads that can be run by the Heartbeat Manager to run heartbeat tasks.
	heartbeat_mgr_threads_num: int | *8

	// The size of the blocking queue that stores heartbeat tasks run by the Heartbeat Manager.
	heartbeat_mgr_blocking_queue_size: int | *1024

	// Specifies whether to forcibly reset the metadata of the FE. Exercise caution when you set this parameter.
	metadata_failure_recovery: bool | *false

	// The port that is used for communication among the leader, follower, and observer FEs in the StarRocks cluster.
	edit_log_port: int | *9010

	// The type of edit log that can be generated. Set the value to `BDB`.
	edit_log_type: string | *"BDB"

	// The amount of time after which the heartbeats among the leader, follower, and observer FEs in the StarRocks cluster time out. Unit: second.
	bdbje_heartbeat_timeout_second: int | *30

	// The amount of time after which a lock in the BDB JE-based FE times out. Unit: second.
	bdbje_lock_timeout_second: int | *1

	// The maximum clock offset that is allowed between the leader FE and the follower or observer FEs in the StarRocks cluster. Unit: ms.
	max_bdbje_clock_delta_ms: int | *5000

	// The maximum number of transactions that can be rolled back.
	txn_rollback_limit: int | *100

	// The maximum amount of time for which the leader FE can wait for ACK messages from a specified number of follower FEs when metadata is written from the leader FE to the follower FEs. Unit: second. If a large amount of metadata is being written, the follower FEs require a long time before they can return ACK messages to the leader FE, causing ACK timeout. In this situation, metadata writes fail, and the FE process exits. We recommend that you increase the value of this parameter to prevent this situation.
	bdbje_replica_ack_timeout_second: int | *10

	// The policy based on which the leader FE flushes logs to disk. This parameter is valid only when the current FE is a leader FE. Valid values:   - `SYNC`: When a transaction is committed, a log entry is generated and flushed to disk simultaneously.   - `NO_SYNC`: The generation and flushing of a log entry do not occur at the same time when a transaction is committed.   - `WRITE_NO_SYNC`: When a transaction is commited, a log entry is generated simultaneously but is not flushed to disk. If you have deployed only one follower FE, we recommend that you set this parameter to `SYNC`. If you have deployed three or more follower FEs, we recommend that you set this parameter and the `replica_sync_policy` both to `WRITE_NO_SYNC`.
	master_sync_policy: string | *"SYNC"

	// The policy based on which the follower FE flushes logs to disk. This parameter is valid only when the current FE is a follower FE. Valid values:   - `SYNC`: When a transaction is committed, a log entry is generated and flushed to disk simultaneously.   - `NO_SYNC`: The generation and flushing of a log entry do not occur at the same time when a transaction is committed.   - `WRITE_NO_SYNC`: When a transaction is committed, a log entry is generated simultaneously but is not flushed to disk.
	replica_sync_policy: string | *"SYNC"

	// The policy based on which a log entry is considered valid. The default value `SIMPLE_MAJORITY` specifies that a log entry is considered valid if a majority of follower FEs return ACK messages.
	replica_ack_policy: string | *"SIMPLE_MAJORITY"

	// The ID of the StarRocks cluster to which the FE belongs. FEs or BEs that have the same cluster ID belong to the same StarRocks cluster. Valid values: any positive integer. The default value `-1` specifies that StarRocks will generate a random cluster ID for the StarRocks cluster at the time when the leader FE of the cluster is started for the first time.
	cluster_id: int | *-1

	// The time interval at which release validation tasks are issued. Unit: ms.
	publish_version_interval_ms: int | *10

	// The number of rows that can be cached for the statistics table.
	statistic_cache_columns: int | *100000

	// The size of the thread-pool which will be used to refresh statistic caches.
	statistic_cache_thread_pool_size: int | *10

	// The time interval at which load jobs are processed on a rolling basis. Unit: second.
	load_checker_interval_second: int | *5

	// The time interval at which finished transactions are cleaned up. Unit: second. We recommend that you specify a short time interval to ensure that finished transactions can be cleaned up in a timely manner.
	transaction_clean_interval_second: int | *30

	// The time interval at which labels are cleaned up. Unit: second. We recommend that you specify a short time interval to ensure that historical labels can be cleaned up in a timely manner.
	label_clean_interval_second: int | *14400

	// The version of Spark Dynamic Partition Pruning (DPP) used.
	spark_dpp_version: string | *"1.0.0"

	// The root directory of the Spark dependency package.
	spark_resource_path: string | *""

	// The directory that stores Spark log files.
	spark_launcher_log_dir: string | *"sys_log_dir + \"/spark_launcher_log\""

	// The root directory of the Yarn client package.
	yarn_client_path: string | *"/opt/starrocks/fe/lib/yarn-client/hadoop/bin/yarn"

	// The directory that stores the Yarn configuration file.
	yarn_config_dir: string | *"/opt/starrocks/fe/lib/yarn-config"

	// The time interval at which load jobs are scheduled.
	export_checker_interval_second: int | *5

	// The size of the unload task thread pool.
	export_task_pool_size: int | *5

	// The default storage media that is used for a table or partition at the time of table or partition creation if no storage media is specified. Valid values: `HDD` and `SSD`. When you create a table or partition, the default storage media specified by this parameter is used if you do not specify a storage media type for the table or partition.
	default_storage_medium: string | *"HDD"

	// The policy based on which load balancing is implemented among tablets. The alias of this parameter is `tablet_balancer_strategy`. Valid values: `disk_and_tablet` and `be_load_score`.
	tablet_sched_balancer_strategy: string | *"disk_and_tablet"

	// The latency of automatic cooling starting from the time of table creation. The alias of this parameter is `storage_cooldown_second`. Unit: second. The default value `-1` specifies that automatic cooling is disabled. If you want to enable automatic cooling, set this parameter to a value greater than `-1`.
	tablet_sched_storage_cooldown_second: int | *-1

	// The time interval at which the FE retrieves tablet statistics from each BE. Unit: second.
	tablet_stat_update_interval_second: int | *300

	// The running mode of the StarRocks cluster. Valid values: shared_data and shared_nothing (Default).    - shared_data indicates running StarRocks in shared-data mode.   - shared_nothing indicates running StarRocks in shared-nothing mode. CAUTION You cannot adopt the shared_data and shared_nothing modes simultaneously for a StarRocks cluster. Mixed deployment is not supported. DO NOT change run_mode after the cluster is deployed. Otherwise, the cluster fails to restart. The transformation from a shared-nothing cluster to a shared-data cluster or vice versa is not supported.
	run_mode: string | *"shared_nothing"

	// The cloud-native meta service RPC port.
	cloud_native_meta_port: int | *6090

	// The type of object storage you use. In shared-data mode, StarRocks supports storing data in Azure Blob (supported from v3.1.1 onwards), and object storages that are compatible with the S3 protocol (such as AWS S3, Google GCP, and MinIO). Valid value: S3 (Default) and AZBLOB. If you specify this parameter as S3, you must add the parameters prefixed by aws_s3. If you specify this parameter as AZBLOB, you must add the parameters prefixed by azure_blob.
	cloud_native_storage_type: string | *"S3"

	// The S3 path used to store data. It consists of the name of your S3 bucket and the sub-path (if any) under it, for example, `testbucket/subpath`.
	aws_s3_path: string

	// The endpoint used to access your S3 bucket, for example, `https://s3.us-west-2.amazonaws.com`.
	aws_s3_endpoint: string

	// The region in which your S3 bucket resides, for example, `us-west-2`.
	aws_s3_region: string

	// Whether to use the default authentication credential of AWS SDK. Valid values: true and false (Default).
	aws_s3_use_aws_sdk_default_behavior: bool | *false

	// Whether to use Instance Profile and Assumed Role as credential methods for accessing S3. Valid values: true and false (Default).
	aws_s3_use_instance_profile: bool | *false

	// The Access Key ID used to access your S3 bucket.
	aws_s3_access_key: string

	// The Secret Access Key used to access your S3 bucket.
	aws_s3_secret_key: string

	// The ARN of the IAM role that has privileges on your S3 bucket in which your data files are stored.
	aws_s3_iam_role_arn: string

	// The external ID of the AWS account that is used for cross-account access to your S3 bucket.
	aws_s3_external_id: string

	// The Azure Blob Storage path used to store data. It consists of the name of the container within your storage account and the sub-path (if any) under the container, for example, testcontainer/subpath.
	azure_blob_path: string

	// The endpoint of your Azure Blob Storage Account, for example, `https://test.blob.core.windows.net`.
	azure_blob_endpoint: string

	// The Shared Key used to authorize requests for your Azure Blob Storage.
	azure_blob_shared_key: string

	// The shared access signatures (SAS) used to authorize requests for your Azure Blob Storage.
	azure_blob_sas_token: string

	// The directory that stores plugin installation packages.
	plugin_dir: string | *"STARROCKS_HOME_DIR/plugins"

	// The root directory of small files.
	small_file_dir: string | *"/opt/starrocks/fe/small_files"

	// The maximum number of threads that are allowed in the agent task thread pool.
	max_agent_task_threads_num: int | *4096

	// The token that is used for identity authentication within the StarRocks cluster to which the FE belongs. If this parameter is left unspecified, StarRocks generates a random token for the cluster at the time when the leader FE of the cluster is started for the first time.
	auth_token: string

	// The directory that stores temporary files such as files generated during backup and restore procedures. After these procedures finish, the generated temporary files are deleted.
	tmp_dir: string | *"/opt/starrocks/fe/temp_dir"

	// The character set that is used by the FE.
	locale: string | *"zh_CN.UTF-8"

	// The maximum number of concurrent threads that are supported for Hive metadata.
	hive_meta_load_concurrency: int | *4

	// The time interval at which the cached metadata of Hive external tables is updated. Unit: second.
	hive_meta_cache_refresh_interval_s: int | *7200

	// The amount of time after which the cached metadata of Hive external tables expires. Unit: second.
	hive_meta_cache_ttl_s: int | *86400

	// The amount of time after which a connection to a Hive metastore times out. Unit: second.
	hive_meta_store_timeout_s: int | *10

	// The time interval at which the FE obtains Elasticsearch indexes and synchronizes the metadata of StarRocks external tables. Unit: second.
	es_state_sync_interval_second: int | *10

	// Specifies whether to enable the authentication check feature. Valid values: `TRUE` and `FALSE`. `TRUE` specifies to enable this feature, and `FALSE` specifies to disable this feature.
	enable_auth_check: bool | *true

	// Specifies whether to enable the feature that is used to periodically collect metrics. Valid values: `TRUE` and `FALSE`. `TRUE` specifies to enable this feature, and `FALSE` specifies to disable this feature.
	enable_metric_calculator: bool | *true

  // Set this to false if you do not want default storage created in the object storage using the details provided above.
	enable_load_volume_from_conf: bool | *false

	LOG_DIR: string | *"${STARROCKS_HOME}/log"
	DATE: string | *"$(date +%Y%m%d-%H%M%S)"
	JAVA_OPTS: string | *"-Dlog4j2.formatMsgNoLookups=true -Xmx8192m -XX:+UseMembar -XX:SurvivorRatio=8 -XX:MaxTenuringThreshold=7 -XX:+PrintGCDateStamps -XX:+PrintGCDetails -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSClassUnloadingEnabled -XX:-CMSParallelRemarkEnabled -XX:CMSInitiatingOccupancyFraction=80 -XX:SoftRefLRUPolicyMSPerMB=0 -Xloggc:${LOG_DIR}/fe.gc.log.$DATE"
	JAVA_OPTS_FOR_JDK_9: string | *"-Dlog4j2.formatMsgNoLookups=true -Xmx8192m -XX:SurvivorRatio=8 -XX:MaxTenuringThreshold=7 -XX:+CMSClassUnloadingEnabled -XX:-CMSParallelRemarkEnabled -XX:CMSInitiatingOccupancyFraction=80 -XX:SoftRefLRUPolicyMSPerMB=0 -Xlog:gc*:${LOG_DIR}/fe.gc.log.$DATE:time"
}

configuration: #FEParameter & {
}
