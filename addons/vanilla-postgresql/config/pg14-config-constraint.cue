// PostgreSQL parameters: https://postgresqlco.nf/doc/en/param/
#PGParameter: {
	// Allows tablespaces directly inside pg_tblspc, for testing.
	allow_in_place_tablespaces?: bool & true | false | *false

	// Allows modifications of the structure of system tables.
	allow_system_table_mods?: bool & true | false | *false

	// Sets the application name to be reported in statistics and logs.
	application_name?: string

	// Sets the shell command that will be executed at every restart point.
	archive_cleanup_command?: string

	// Sets the shell command that will be called to archive a WAL file.
	archive_command?: string

	// Allows archiving of WAL files using "archive_command".
	archive_mode?: string & "always" | "on" | "off" | *"off"

	// Forces a switch to the next WAL file if a new file has not been started within N seconds.
	archive_timeout?: int & >= 0 & <= 1073741823 | *0 @timeDurationResource(1s)

	// Enable input of NULL elements in arrays.
	array_nulls?: bool & true | false | *true

	// Sets the maximum allowed time to complete client authentication.
	authentication_timeout?: int & >= 1 & <= 600 | *60 @timeDurationResource(1s)

	// Starts the autovacuum subprocess.
	autovacuum?: bool & true | false | *true

	// Number of tuple inserts, updates or deletes prior to analyze as a fraction of reltuples.
	autovacuum_analyze_scale_factor?: float & >= 0 & <= 100 | *0.1

	// Minimum number of tuple inserts, updates or deletes prior to analyze.
	autovacuum_analyze_threshold?: int & >= 0 & <= 2147483647 | *50

	// Age at which to autovacuum a table to prevent transaction ID wraparound.
	autovacuum_freeze_max_age?: int & >= 100000 & <= 2000000000 | *200000000

	// Sets the maximum number of simultaneously running autovacuum worker processes.
	autovacuum_max_workers?: int & >= 1 & <= 262143 | *3

	// Multixact age at which to autovacuum a table to prevent multixact wraparound.
	autovacuum_multixact_freeze_max_age?: int & >= 10000 & <= 2000000000 | *400000000

	// Time to sleep between autovacuum runs.
	autovacuum_naptime?: int & >= 1 & <= 2147483 | *60 @timeDurationResource(1s)

	// Vacuum cost delay in milliseconds, for autovacuum.
	autovacuum_vacuum_cost_delay?: float & >= -1 & <= 100 | *2

	// Vacuum cost amount available before napping, for autovacuum.
	autovacuum_vacuum_cost_limit?: int & >= -1 & <= 10000 | *-1

	// Number of tuple inserts prior to vacuum as a fraction of reltuples.
	autovacuum_vacuum_insert_scale_factor?: float & >= 0 & <= 100 | *0.2

	// Minimum number of tuple inserts prior to vacuum, or -1 to disable insert vacuums.
	autovacuum_vacuum_insert_threshold?: int & >= -1 & <= 2147483647 | *1000

	// Number of tuple updates or deletes prior to vacuum as a fraction of reltuples.
	autovacuum_vacuum_scale_factor?: float & >= 0 & <= 100 | *0.2

	// Minimum number of tuple updates or deletes prior to vacuum.
	autovacuum_vacuum_threshold?: int & >= 0 & <= 2147483647 | *50

	// Sets the maximum memory to be used by each autovacuum worker process.
	autovacuum_work_mem?: int & >= -1 & <= 2147483647 | *-1 @storeResource(1KB)

	// Number of pages after which previously performed writes are flushed to disk.
	backend_flush_after?: int & >= 0 & <= 256 | *0 @storeResource(8KB)

	// Sets whether "\'" is allowed in string literals.
	backslash_quote?: string & "safe_encoding" | "on" | "off" | *"safe_encoding"

	// Log backtrace for errors in these functions.
	backtrace_functions?: string

	// Background writer sleep time between rounds.
	bgwriter_delay?: int & >= 10 & <= 10000 | *200 @timeDurationResource()

	// Number of pages after which previously performed writes are flushed to disk.
	bgwriter_flush_after?: int & >= 0 & <= 256 | *64 @storeResource(8KB)

	// Background writer maximum number of LRU pages to flush per round.
	bgwriter_lru_maxpages?: int & >= 0 & <= 1073741823 | *100

	// Multiple of the average buffer usage to free per round.
	bgwriter_lru_multiplier?: float & >= 0 & <= 10 | *2

	// Enables advertising the server via Bonjour.
	bonjour?: bool & true | false | *false

	// Sets the Bonjour service name.
	bonjour_name?: string

	// Sets the output format for bytea.
	bytea_output?: string & "escape" | "hex" | *"hex"

	// Check function bodies during CREATE FUNCTION.
	check_function_bodies?: bool & true | false | *true

	// Time spent flushing dirty buffers during checkpoint, as fraction of checkpoint interval.
	checkpoint_completion_target?: float & >= 0 & <= 1 | *0.9

	// Number of pages after which previously performed writes are flushed to disk.
	checkpoint_flush_after?: int & >= 0 & <= 256 | *32 @storeResource(8KB)

	// Sets the maximum time between automatic WAL checkpoints.
	checkpoint_timeout?: int & >= 30 & <= 86400 | *300 @timeDurationResource(1s)

	// Enables warnings if checkpoint segments are filled more frequently than this.
	checkpoint_warning?: int & >= 0 & <= 2147483647 | *30 @timeDurationResource(1s)

	// Sets the time interval between checks for disconnection while running queries.
	client_connection_check_interval?: int & >= 0 & <= 2147483647 | *0 @timeDurationResource()

	// Sets the client's character set encoding.
	client_encoding?: string | *"SQL_ASCII"

	// Sets the message levels that are sent to the client.
	client_min_messages?: string & "debug5" | "debug4" | "debug3" | "debug2" | "debug1" | "log" | "notice" | "warning" | "error" | *"notice"

	// Sets the name of the cluster, which is included in the process title.
	cluster_name?: string

	// Sets the delay in microseconds between transaction commit and flushing WAL to disk.
	commit_delay?: int & >= 0 & <= 100000 | *0

	// Sets the minimum concurrent open transactions before performing commit_delay.
	commit_siblings?: int & >= 0 & <= 1000 | *5

	// Compute query identifiers.
	compute_query_id?: string & "auto" | "regress" | "on" | "off" | *"auto"

	// Sets the server's main configuration file.
	config_file?: string

	// Enables the planner to use constraints to optimize queries.
	constraint_exclusion?: string & "partition" | "on" | "off" | *"partition"

	// Sets the planner's estimate of the cost of processing each index entry during an index scan.
	cpu_index_tuple_cost?: float & >= 0 & <= 1.79769e+308 | *0.005

	// Sets the planner's estimate of the cost of processing each operator or function call.
	cpu_operator_cost?: float & >= 0 & <= 1.79769e+308 | *0.0025

	// Sets the planner's estimate of the cost of processing each tuple (row).
	cpu_tuple_cost?: float & >= 0 & <= 1.79769e+308 | *0.01

	// Sets the planner's estimate of the fraction of a cursor's rows that will be retrieved.
	cursor_tuple_fraction?: float & >= 0 & <= 1 | *0.1

	// Sets the server's data directory.
	data_directory?: string

	// Whether to continue running after a failure to sync data files.
	data_sync_retry?: bool & true | false | *false

	// Sets the display format for date and time values.
	DateStyle?: string | *"ISO, MDY"

	// Enables per-database user names.
	db_user_namespace?: bool & true | false | *false

	// Sets the time to wait on a lock before checking for deadlock.
	deadlock_timeout?: int & >= 1 & <= 2147483647 | *1000 @timeDurationResource()

	// Aggressively flush system caches for debugging purposes.
	debug_discard_caches?: int & >= 0 & <= 0 | *0

	// Indents parse and plan tree displays.
	debug_pretty_print?: bool & true | false | *true

	// Logs each query's parse tree.
	debug_print_parse?: bool & true | false | *false

	// Logs each query's execution plan.
	debug_print_plan?: bool & true | false | *false

	// Logs each query's rewritten parse tree.
	debug_print_rewritten?: bool & true | false | *false

	// Sets the default statistics target.
	default_statistics_target?: int & >= 1 & <= 10000 | *100

	// Sets the default table access method for new tables.
	default_table_access_method?: string | *"heap"

	// Sets the default tablespace to create tables and indexes in.
	default_tablespace?: string

	// Sets default text search configuration.
	default_text_search_config?: string | *"pg_catalog.simple"

	// Sets the default compression method for compressible values.
	default_toast_compression?: string & "pglz" | "lz4" | *"pglz"

	// Sets the default deferrable status of new transactions.
	default_transaction_deferrable?: bool & true | false | *false

	// Sets the transaction isolation level of each new transaction.
	default_transaction_isolation?: string & "serializable" | "repeatable read" | "read committed" | "read uncommitted" | *"read committed"

	// Sets the default read-only status of new transactions.
	default_transaction_read_only?: bool & true | false | *false

	// Sets the path for dynamically loadable modules.
	dynamic_library_path?: string | *"$libdir"

	// Selects the dynamic shared memory implementation used.
	dynamic_shared_memory_type?: string & "posix" | "sysv" | "mmap" | *"posix"

	// Sets the planner's assumption about the size of the data cache.
	effective_cache_size?: int & >= 1 & <= 2147483647 | *524288 @storeResource(8KB)

	// Number of simultaneous requests that can be handled efficiently by the disk subsystem.
	effective_io_concurrency?: int & >= 0 & <= 1000 | *1

	// Enables the planner's use of async append plans.
	enable_async_append?: bool & true | false | *true

	// Enables the planner's use of bitmap-scan plans.
	enable_bitmapscan?: bool & true | false | *true

	// Enables the planner's use of gather merge plans.
	enable_gathermerge?: bool & true | false | *true

	// Enables the planner's use of hashed aggregation plans.
	enable_hashagg?: bool & true | false | *true

	// Enables the planner's use of hash join plans.
	enable_hashjoin?: bool & true | false | *true

	// Enables the planner's use of incremental sort steps.
	enable_incremental_sort?: bool & true | false | *true

	// Enables the planner's use of index-only-scan plans.
	enable_indexonlyscan?: bool & true | false | *true

	// Enables the planner's use of index-scan plans.
	enable_indexscan?: bool & true | false | *true

	// Enables the planner's use of materialization.
	enable_material?: bool & true | false | *true

	// Enables the planner's use of memoization.
	enable_memoize?: bool & true | false | *true

	// Enables the planner's use of merge join plans.
	enable_mergejoin?: bool & true | false | *true

	// Enables the planner's use of nested-loop join plans.
	enable_nestloop?: bool & true | false | *true

	// Enables the planner's use of parallel append plans.
	enable_parallel_append?: bool & true | false | *true

	// Enables the planner's use of parallel hash plans.
	enable_parallel_hash?: bool & true | false | *true

	// Enable plan-time and run-time partition pruning.
	enable_partition_pruning?: bool & true | false | *true

	// Enables partitionwise aggregation and grouping.
	enable_partitionwise_aggregate?: bool & true | false | *false

	// Enables partitionwise join.
	enable_partitionwise_join?: bool & true | false | *false

	// Enables the planner's use of sequential-scan plans.
	enable_seqscan?: bool & true | false | *true

	// Enables the planner's use of explicit sort steps.
	enable_sort?: bool & true | false | *true

	// Enables the planner's use of TID scan plans.
	enable_tidscan?: bool & true | false | *true

	// Warn about backslash escapes in ordinary string literals.
	escape_string_warning?: bool & true | false | *true

	// Sets the application name used to identify PostgreSQL messages in the event log.
	event_source?: string | *"PostgreSQL"

	// Terminate session on any error.
	exit_on_error?: bool & true | false | *false

	// Writes the postmaster PID to the specified file.
	external_pid_file?: string

	// Sets the number of digits displayed for floating-point values.
	extra_float_digits?: int & >= -15 & <= 3 | *1

	// Forces use of parallel query facilities.
	force_parallel_mode?: string & "off" | "on" | "regress" | *"off"

	// Sets the FROM-list size beyond which subqueries are not collapsed.
	from_collapse_limit?: int & >= 1 & <= 2147483647 | *8

	// Forces synchronization of updates to disk.
	fsync?: bool & true | false | *true

	// Writes full pages to WAL when first modified after a checkpoint.
	full_page_writes?: bool & true | false | *true

	// Enables genetic query optimization.
	geqo?: bool & true | false | *true

	// GEQO: effort is used to set the default for other GEQO parameters.
	geqo_effort?: int & >= 1 & <= 10 | *5

	// GEQO: number of iterations of the algorithm.
	geqo_generations?: int & >= 0 & <= 2147483647 | *0

	// GEQO: number of individuals in the population.
	geqo_pool_size?: int & >= 0 & <= 2147483647 | *0

	// GEQO: seed for random path selection.
	geqo_seed?: float & >= 0 & <= 1 | *0

	// GEQO: selective pressure within the population.
	geqo_selection_bias?: float & >= 1.5 & <= 2 | *2

	// Sets the threshold of FROM items beyond which GEQO is used.
	geqo_threshold?: int & >= 2 & <= 2147483647 | *12

	// Sets the maximum allowed result for exact search by GIN.
	gin_fuzzy_search_limit?: int & >= 0 & <= 2147483647 | *0

	// Sets the maximum size of the pending list for GIN index.
	gin_pending_list_limit?: int & >= 64 & <= 2147483647 | *4096 @storeResource(1KB)

	// Multiple of "work_mem" to use for hash tables.
	hash_mem_multiplier?: float & >= 1 & <= 1000 | *1

	// Sets the server's "hba" configuration file.
	hba_file?: string

	// Allows connections and queries during recovery.
	hot_standby?: bool & true | false | *true

	// Allows feedback from a hot standby to the primary that will avoid query conflicts.
	hot_standby_feedback?: bool & true | false | *false

	// Use of huge pages on Linux.
	huge_pages?: string & "off" | "on" | "try" | *"try"

	// The size of huge page that should be requested.
	huge_page_size?: int & >= 0 & <= 2147483647 | *0 @storeResource(1KB)

	// Sets the server's "ident" configuration file.
	ident_file?: string

	// Sets the maximum allowed duration of any idling transaction.
	idle_in_transaction_session_timeout?: int & >= 0 & <= 2147483647 | *0 @timeDurationResource()

	// Sets the maximum allowed idle time between queries, when not in a transaction.
	idle_session_timeout?: int & >= 0 & <= 2147483647 | *0 @timeDurationResource()

	// Continues processing after a checksum failure.
	ignore_checksum_failure?: bool & true | false | *false

	// Continues recovery after an invalid pages failure.
	ignore_invalid_pages?: bool & true | false | *false

	// Disables reading from system indexes.
	ignore_system_indexes?: bool & true | false | *false

	// Sets the display format for interval values.
	IntervalStyle?: string & "postgres" | "postgres_verbose" | "sql_standard" | "iso_8601" | *"postgres"

	// Allow JIT compilation.
	jit?: bool & true | false | *true

	// Perform JIT compilation if query is more expensive.
	jit_above_cost?: float & >= -1 & <= 1.79769e+308 | *100000

	// Register JIT-compiled functions with debugger.
	jit_debugging_support?: bool & true | false | *false

	// Write out LLVM bitcode to facilitate JIT debugging.
	jit_dump_bitcode?: bool & true | false | *false

	// Allow JIT compilation of expressions.
	jit_expressions?: bool & true | false | *true

	// Perform JIT inlining if query is more expensive.
	jit_inline_above_cost?: float & >= -1 & <= 1.79769e+308 | *500000

	// Optimize JIT-compiled functions if query is more expensive.
	jit_optimize_above_cost?: float & >= -1 & <= 1.79769e+308 | *500000

	// Register JIT-compiled functions with perf profiler.
	jit_profiling_support?: bool & true | false | *false

	// JIT provider to use.
	jit_provider?: string | *"llvmjit"

	// Allow JIT compilation of tuple deforming.
	jit_tuple_deforming?: bool & true | false | *true

	// Sets the FROM-list size beyond which JOIN constructs are not flattened.
	join_collapse_limit?: int & >= 1 & <= 2147483647 | *8

	// Sets whether Kerberos and GSSAPI user names should be treated as case-insensitive.
	krb_caseins_users?: bool & true | false | *false

	// Sets the location of the Kerberos server key file.
	krb_server_keyfile?: string | *"FILE:/etc/postgresql-common/krb5.keytab"

	// Sets the language in which messages are displayed.
	lc_messages?: string

	// Sets the locale for formatting monetary amounts.
	lc_monetary?: string | *"C"

	// Sets the locale for formatting numbers.
	lc_numeric?: string | *"C"

	// Sets the locale for formatting date and time values.
	lc_time?: string | *"C"

	// Sets the host name or IP address(es) to listen to.
	listen_addresses?: string | *"localhost"

	// Lists shared libraries to preload into each backend.
	local_preload_libraries?: string

	// Sets the maximum allowed duration of any wait for a lock.
	lock_timeout?: int & >= 0 & <= 2147483647 | *0 @timeDurationResource()

	// Enables backward compatibility mode for privilege checks on large objects.
	lo_compat_privileges?: bool & true | false | *false

	// Sets the minimum execution time above which autovacuum actions will be logged.
	log_autovacuum_min_duration?: int & >= -1 & <= 2147483647 | *-1 @timeDurationResource()

	// Logs each checkpoint.
	log_checkpoints?: bool & true | false | *false

	// Logs each successful connection.
	log_connections?: bool & true | false | *false

	// Sets the destination for server log output.
	log_destination?: string | *"stderr"

	// Sets the destination directory for log files.
	log_directory?: string | *"log"

	// Logs end of a session, including duration.
	log_disconnections?: bool & true | false | *false

	// Logs the duration of each completed SQL statement.
	log_duration?: bool & true | false | *false

	// Sets the verbosity of logged messages.
	log_error_verbosity?: string & "terse" | "default" | "verbose" | *"default"

	// Writes executor performance statistics to the server log.
	log_executor_stats?: bool & true | false | *false

	// Sets the file permissions for log files.
	log_file_mode?: int & >= 0 & <= 511 | *384

	// Sets the file name pattern for log files.
	log_filename?: string | *"postgresql-%Y-%m-%d_%H%M%S.log"

	// Start a subprocess to capture stderr output and/or csvlogs into log files.
	logging_collector?: bool & true | false | *false

	// Logs the host name in the connection logs.
	log_hostname?: bool & true | false | *false

	// Sets the maximum memory to be used for logical decoding.
	logical_decoding_work_mem?: int & >= 64 & <= 2147483647 | *65536 @storeResource(1KB)

	// Controls information prefixed to each log line.
	log_line_prefix?: string | *"%m [%p]"

	// Logs long lock waits.
	log_lock_waits?: bool & true | false | *false

	// Sets the minimum execution time above which a sample of statements will be logged. Sampling is determined by log_statement_sample_rate.
	log_min_duration_sample?: int & >= -1 & <= 2147483647 | *-1 @timeDurationResource()

	// Sets the minimum execution time above which all statements will be logged.
	log_min_duration_statement?: int & >= -1 & <= 2147483647 | *-1 @timeDurationResource()

	// Causes all statements generating error at or above this level to be logged.
	log_min_error_statement?: string & "debug5" | "debug4" | "debug3" | "debug2" | "debug1" | "info" | "notice" | "warning" | "error" | "log" | "fatal" | "panic" | *"error"

	// Sets the message levels that are logged.
	log_min_messages?: string & "debug5" | "debug4" | "debug3" | "debug2" | "debug1" | "info" | "notice" | "warning" | "error" | "log" | "fatal" | "panic" | *"warning"

	// Sets the maximum length in bytes of data logged for bind parameter values when logging statements.
	log_parameter_max_length?: int & >= -1 & <= 1073741823 | *-1 @storeResource(B)

	// Sets the maximum length in bytes of data logged for bind parameter values when logging statements, on error.
	log_parameter_max_length_on_error?: int & >= -1 & <= 1073741823 | *0 @storeResource(B)

	// Writes parser performance statistics to the server log.
	log_parser_stats?: bool & true | false | *false

	// Writes planner performance statistics to the server log.
	log_planner_stats?: bool & true | false | *false

	// Logs standby recovery conflict waits.
	log_recovery_conflict_waits?: bool & true | false | *false

	// Logs each replication command.
	log_replication_commands?: bool & true | false | *false

	// Automatic log file rotation will occur after N minutes.
	log_rotation_age?: int & >= 0 & <= 35791394 | *1440 @timeDurationResource(1min)

	// Automatic log file rotation will occur after N kilobytes.
	log_rotation_size?: int & >= 0 & <= 2097151 | *10240 @storeResource(1KB)

	// Sets the type of statements logged.
	log_statement?: string & "none" | "ddl" | "mod" | "all" | *"none"

	// Fraction of statements exceeding "log_min_duration_sample" to be logged.
	log_statement_sample_rate?: float & >= 0 & <= 1 | *1

	// Writes cumulative performance statistics to the server log.
	log_statement_stats?: bool & true | false | *false

	// Log the use of temporary files larger than this number of kilobytes.
	log_temp_files?: int & >= -1 & <= 2147483647 | *-1 @storeResource(1KB)

	// Sets the time zone to use in log messages.
	log_timezone?: string | *"GMT"

	// Sets the fraction of transactions from which to log all statements.
	log_transaction_sample_rate?: float & >= 0 & <= 1 | *0

	// Truncate existing log files of same name during log rotation.
	log_truncate_on_rotation?: bool & true | false | *false

	// A variant of "effective_io_concurrency" that is used for maintenance work.
	maintenance_io_concurrency?: int & >= 0 & <= 1000 | *10

	// Sets the maximum memory to be used for maintenance operations.
	maintenance_work_mem?: int & >= 1024 & <= 2147483647 | *65536 @storeResource(1KB)

	// Sets the maximum number of concurrent connections.
	max_connections?: int & >= 1 & <= 262143 | *100

	// Sets the maximum number of simultaneously open files for each server process.
	max_files_per_process?: int & >= 64 & <= 2147483647 | *1000

	// Sets the maximum number of locks per transaction.
	max_locks_per_transaction?: int & >= 10 & <= 2147483647 | *64

	// Maximum number of logical replication worker processes.
	max_logical_replication_workers?: int & >= 0 & <= 262143 | *4

	// Sets the maximum number of parallel processes per maintenance operation.
	max_parallel_maintenance_workers?: int & >= 0 & <= 1024 | *2

	// Sets the maximum number of parallel workers that can be active at one time.
	max_parallel_workers?: int & >= 0 & <= 1024 | *8

	// Sets the maximum number of parallel processes per executor node.
	max_parallel_workers_per_gather?: int & >= 0 & <= 1024 | *2

	// Sets the maximum number of predicate-locked tuples per page.
	max_pred_locks_per_page?: int & >= 0 & <= 2147483647 | *2

	// Sets the maximum number of predicate-locked pages and tuples per relation.
	max_pred_locks_per_relation?: int & >= -2147483648 & <= 2147483647 | *-2

	// Sets the maximum number of predicate locks per transaction.
	max_pred_locks_per_transaction?: int & >= 10 & <= 2147483647 | *64

	// Sets the maximum number of simultaneously prepared transactions.
	max_prepared_transactions?: int & >= 0 & <= 262143 | *0

	// Sets the maximum number of simultaneously defined replication slots.
	max_replication_slots?: int & >= 0 & <= 262143 | *10

	// Sets the maximum WAL size that can be reserved by replication slots.
	max_slot_wal_keep_size?: int & >= -1 & <= 2147483647 | *-1 @storeResource(1MB)

	// Sets the maximum stack depth, in kilobytes.
	max_stack_depth?: int & >= 100 & <= 2147483647 | *100 @storeResource(1KB)

	// Sets the maximum delay before canceling queries when a hot standby server is processing archived WAL data.
	max_standby_archive_delay?: int & >= -1 & <= 2147483647 | *30000 @timeDurationResource()

	// Sets the maximum delay before canceling queries when a hot standby server is processing streamed WAL data.
	max_standby_streaming_delay?: int & >= -1 & <= 2147483647 | *30000 @timeDurationResource()

	// Maximum number of table synchronization workers per subscription.
	max_sync_workers_per_subscription?: int & >= 0 & <= 262143 | *2

	// Sets the maximum number of simultaneously running WAL sender processes.
	max_wal_senders?: int & >= 0 & <= 262143 | *10

	// Sets the WAL size that triggers a checkpoint.
	max_wal_size?: int & >= 2 & <= 2147483647 | *1024 @storeResource(1MB)

	// Maximum number of concurrent worker processes.
	max_worker_processes?: int & >= 0 & <= 262143 | *8

	// Amount of dynamic shared memory reserved at startup.
	min_dynamic_shared_memory?: int & >= 0 & <= 2147483647 | *0 @storeResource(1MB)

	// Sets the minimum amount of index data for a parallel scan.
	min_parallel_index_scan_size?: int & >= 0 & <= 715827882 | *64 @storeResource(8KB)

	// Sets the minimum amount of table data for a parallel scan.
	min_parallel_table_scan_size?: int & >= 0 & <= 715827882 | *1024 @storeResource(8KB)

	// Sets the minimum size to shrink the WAL to.
	min_wal_size?: int & >= 2 & <= 2147483647 | *80 @storeResource(1MB)

	// Time before a snapshot is too old to read pages changed after the snapshot was taken.
	old_snapshot_threshold?: int & >= -1 & <= 86400 | *-1 @timeDurationResource(1min)

	// Controls whether Gather and Gather Merge also run subplans.
	parallel_leader_participation?: bool & true | false | *true

	// Sets the planner's estimate of the cost of starting up worker processes for parallel query.
	parallel_setup_cost?: float & >= 0 & <= 1.79769e+308 | *1000

	// Sets the planner's estimate of the cost of passing each tuple (row) from worker to leader backend.
	parallel_tuple_cost?: float & >= 0 & <= 1.79769e+308 | *0.1

	// Chooses the algorithm for encrypting passwords.
	password_encryption?: string & "md5" | "scram-sha-256" | *"scram-sha-256"

	// Controls the planner's selection of custom or generic plan.
	plan_cache_mode?: string & "auto" | "force_generic_plan" | "force_custom_plan" | *"auto"

	// Sets the TCP port the server listens on.
	port?: int & >= 1 & <= 65535 | *5432

	// Sets the amount of time to wait after authentication on connection startup.
	post_auth_delay?: int & >= 0 & <= 2147 | *0 @timeDurationResource(1s)

	// Sets the amount of time to wait before authentication on connection startup.
	pre_auth_delay?: int & >= 0 & <= 60 | *0 @timeDurationResource(1s)

	// Sets the connection string to be used to connect to the sending server.
	primary_conninfo?: string

	// Sets the name of the replication slot to use on the sending server.
	primary_slot_name?: string

	// Specifies a file name whose presence ends recovery in the standby.
	promote_trigger_file?: string

	// When generating SQL fragments, quote all identifiers.
	quote_all_identifiers?: bool & true | false | *false

	// Sets the planner's estimate of the cost of a nonsequentially fetched disk page.
	random_page_cost?: float & >= 0 & <= 1.79769e+308 | *4

	// Sets the shell command that will be executed once at the end of recovery.
	recovery_end_command?: string

	// Sets the method for synchronizing the data directory before crash recovery.
	recovery_init_sync_method?: string & "fsync" | "syncfs" | *"fsync"

	// Sets the minimum delay for applying changes during recovery.
	recovery_min_apply_delay?: int & >= 0 & <= 2147483647 | *0 @timeDurationResource()

	// Set to "immediate" to end recovery as soon as a consistent state is reached.
	recovery_target?: string

	// Sets the action to perform upon reaching the recovery target.
	recovery_target_action?: string & "pause" | "promote" | "shutdown" | *"pause"

	// Sets whether to include or exclude transaction with recovery target.
	recovery_target_inclusive?: bool & true | false | *true

	// Sets the LSN of the write-ahead log location up to which recovery will proceed.
	recovery_target_lsn?: string

	// Sets the named restore point up to which recovery will proceed.
	recovery_target_name?: string

	// Sets the time stamp up to which recovery will proceed.
	recovery_target_time?: string

	// Specifies the timeline to recover into.
	recovery_target_timeline?: string | *"latest"

	// Sets the transaction ID up to which recovery will proceed.
	recovery_target_xid?: string

	// Remove temporary files after backend crash.
	remove_temp_files_after_crash?: bool & true | false | *true

	// Reinitialize server after backend crash.
	restart_after_crash?: bool & true | false | *true

	// Sets the shell command that will be called to retrieve an archived WAL file.
	restore_command?: string

	// Prohibits access to non-system relations of specified kinds.
	restrict_nonsystem_relation_kind?: string

	// Enable row security.
	row_security?: bool & true | false | *true

	// Sets the schema search order for names that are not schema-qualified.
	search_path?: search_path?: string | *'"$user", public'

	// Sets the planner's estimate of the cost of a sequentially fetched disk page.
	seq_page_cost?: float & >= 0 & <= 1.79769e+308 | *1

	// Lists shared libraries to preload into each backend.
	session_preload_libraries?: string

	// Sets the session's behavior for triggers and rewrite rules.
	session_replication_role?: string & "origin" | "replica" | "local" | *"origin"

	// Sets the number of shared memory buffers used by the server.
	shared_buffers?: int & >= 16 & <= 1073741823 | *1024 @storeResource(8KB)

	// Selects the shared memory implementation used for the main shared memory region.
	shared_memory_type?: string & "sysv" | "mmap" | *"mmap"

	// Lists shared libraries to preload into server.
	shared_preload_libraries?: string

	// Enables SSL connections.
	ssl?: bool & true | false | *false

	// Location of the SSL certificate authority file.
	ssl_ca_file?: string

	// Location of the SSL server certificate file.
	ssl_cert_file?: string | *"server.crt"

	// Sets the list of allowed SSL ciphers.
	ssl_ciphers?: string | *"HIGH:MEDIUM:+3DES:!aNULL"

	// Location of the SSL certificate revocation list directory.
	ssl_crl_dir?: string

	// Location of the SSL certificate revocation list file.
	ssl_crl_file?: string

	// Location of the SSL DH parameters file.
	ssl_dh_params_file?: string

	// Sets the curve to use for ECDH.
	ssl_ecdh_curve?: string | *"prime256v1"

	// Location of the SSL server private key file.
	ssl_key_file?: string | *"server.key"

	// Sets the maximum SSL/TLS protocol version to use.
	ssl_max_protocol_version?: string & "" | "TLSv1" | "TLSv1.1" | "TLSv1.2" | "TLSv1.3"

	// Sets the minimum SSL/TLS protocol version to use.
	ssl_min_protocol_version?: string & "TLSv1" | "TLSv1.1" | "TLSv1.2" | "TLSv1.3" | *"TLSv1.2"

	// Command to obtain passphrases for SSL.
	ssl_passphrase_command?: string

	// Also use ssl_passphrase_command during server reload.
	ssl_passphrase_command_supports_reload?: bool & true | false | *false

	// Give priority to server ciphersuite order.
	ssl_prefer_server_ciphers?: bool & true | false | *true

	// Causes '...' strings to treat backslashes literally.
	standard_conforming_strings?: bool & true | false | *true

	// Sets the maximum allowed duration of any statement.
	statement_timeout?: int & >= 0 & <= 2147483647 | *0 @timeDurationResource()

	// Writes temporary statistics files to the specified directory.
	stats_temp_directory?: string | *"pg_stat_tmp"

	// Sets the number of connection slots reserved for superusers.
	superuser_reserved_connections?: int & >= 0 & <= 262143 | *3

	// Enable synchronized sequential scans.
	synchronize_seqscans?: bool & true | false | *true

	// Sets the current transaction's synchronization level.
	synchronous_commit?: string & "local" | "remote_write" | "remote_apply" | "on" | "off" | *"on"

	// List of names of potential synchronous standbys.
	synchronous_standby_names?: string

	// Sets the syslog "facility" to be used when syslog enabled.
	syslog_facility?: string & "local0" | "local1" | "local2" | "local3" | "local4" | "local5" | "local6" | "local7" | *"local0"

	// Sets the program name used to identify PostgreSQL messages in syslog.
	syslog_ident?: string | *"postgres"

	// Add sequence number to syslog messages to avoid duplicate suppression.
	syslog_sequence_numbers?: bool & true | false | *true

	// Split messages sent to syslog by lines and to fit into 1024 bytes.
	syslog_split_messages?: bool & true | false | *true

	// Maximum number of TCP keepalive retransmits.
	tcp_keepalives_count?: int & >= 0 & <= 2147483647 | *0

	// Time between issuing TCP keepalives.
	tcp_keepalives_idle?: int & >= 0 & <= 2147483647 | *0 @timeDurationResource(1s)

	// Time between TCP keepalive retransmits.
	tcp_keepalives_interval?: int & >= 0 & <= 2147483647 | *0 @timeDurationResource(1s)

	// TCP user timeout.
	tcp_user_timeout?: int & >= 0 & <= 2147483647 | *0 @timeDurationResource()

	// Sets the maximum number of temporary buffers used by each session.
	temp_buffers?: int & >= 100 & <= 1073741823 | *1024 @storeResource(8KB)

	// Limits the total size of all temporary files used by each process.
	temp_file_limit?: int & >= -1 & <= 2147483647 | *-1 @storeResource(1KB)

	// Sets the tablespace(s) to use for temporary tables and sort files.
	temp_tablespaces?: string

	// Sets the time zone for displaying and interpreting time stamps.
	TimeZone?: string | *"GMT"

	// Selects a file of time zone abbreviations.
	timezone_abbreviations?: string

	// Generates debugging output for LISTEN and NOTIFY.
	trace_notify?: bool & true | false | *false

	// Enables logging of recovery-related debugging information.
	trace_recovery_messages?: string & "debug5" | "debug4" | "debug3" | "debug2" | "debug1" | "log" | "notice" | "warning" | "error" | *"log"

	// Emit information about resource usage in sorting.
	trace_sort?: bool & true | false | *false

	// Collects information about executing commands.
	track_activities?: bool & true | false | *true

	// Sets the size reserved for pg_stat_activity.current_query, in bytes.
	track_activity_query_size?: int & >= 100 & <= 1048576 | *1024 @storeResource(B)

	// Collects transaction commit time.
	track_commit_timestamp?: bool & true | false | *false

	// Collects statistics on database activity.
	track_counts?: bool & true | false | *true

	// Collects function-level statistics on database activity.
	track_functions?: string & "none" | "pl" | "all" | *"none"

	// Collects timing statistics for database I/O activity.
	track_io_timing?: bool & true | false | *false

	// Collects timing statistics for WAL I/O activity.
	track_wal_io_timing?: bool & true | false | *false

	// Whether to defer a read-only serializable transaction until it can be executed with no possible serialization failures.
	transaction_deferrable?: bool & true | false | *false

	// Sets the current transaction's isolation level.
	transaction_isolation?: string & "serializable" | "repeatable read" | "read committed" | "read uncommitted" | *"read committed"

	// Sets the current transaction's read-only status.
	transaction_read_only?: bool & true | false | *false

	// Treats "expr=NULL" as "expr IS NULL".
	transform_null_equals?: bool & true | false | *false

	// Sets the directories where Unix-domain sockets will be created.
	unix_socket_directories?: string | *"/var/run/postgresql"

	// Sets the owning group of the Unix-domain socket.
	unix_socket_group?: string

	// Sets the access permissions of the Unix-domain socket.
	unix_socket_permissions?: int & >= 0 & <= 511 | *511

	// Updates the process title to show the active SQL command.
	update_process_title?: bool & true | false | *true

	// Vacuum cost delay in milliseconds.
	vacuum_cost_delay?: float & >= 0 & <= 100 | *0

	// Vacuum cost amount available before napping.
	vacuum_cost_limit?: int & >= 1 & <= 10000 | *200

	// Vacuum cost for a page dirtied by vacuum.
	vacuum_cost_page_dirty?: int & >= 0 & <= 10000 | *20

	// Vacuum cost for a page found in the buffer cache.
	vacuum_cost_page_hit?: int & >= 0 & <= 10000 | *1

	// Vacuum cost for a page not found in the buffer cache.
	vacuum_cost_page_miss?: int & >= 0 & <= 10000 | *2

	// Number of transactions by which VACUUM and HOT cleanup should be deferred, if any.
	vacuum_defer_cleanup_age?: int & >= 0 & <= 1000000 | *0

	// Age at which VACUUM should trigger failsafe to avoid a wraparound outage.
	vacuum_failsafe_age?: int & >= 0 & <= 2100000000 | *1600000000

	// Minimum age at which VACUUM should freeze a table row.
	vacuum_freeze_min_age?: int & >= 0 & <= 1000000000 | *50000000

	// Age at which VACUUM should scan whole table to freeze tuples.
	vacuum_freeze_table_age?: int & >= 0 & <= 2000000000 | *150000000

	// Multixact age at which VACUUM should trigger failsafe to avoid a wraparound outage.
	vacuum_multixact_failsafe_age?: int & >= 0 & <= 2100000000 | *1600000000

	// Minimum age at which VACUUM should freeze a MultiXactId in a table row.
	vacuum_multixact_freeze_min_age?: int & >= 0 & <= 1000000000 | *5000000

	// Multixact age at which VACUUM should scan whole table to freeze tuples.
	vacuum_multixact_freeze_table_age?: int & >= 0 & <= 2000000000 | *150000000

	// Sets the number of disk-page buffers in shared memory for WAL.
	wal_buffers?: int & >= -1 & <= 262143 | *-1 @storeResource(8KB)

	// Compresses full-page writes written in WAL file.
	wal_compression?: bool & true | false | *false

	// Sets the WAL resource managers for which WAL consistency checks are done.
	wal_consistency_checking?: string

	// Writes zeroes to new WAL files before first use.
	wal_init_zero?: bool & true | false | *true

	// Sets the size of WAL files held for standby servers.
	wal_keep_size?: int & >= 0 & <= 2147483647 | *0 @storeResource(1MB)

	// Sets the level of information written to the WAL.
	wal_level?: string & "minimal" | "replica" | "logical" | *"replica"

	// Writes full pages to WAL when first modified after a checkpoint, even for a non-critical modification.
	wal_log_hints?: bool & true | false | *false

	// Sets whether a WAL receiver should create a temporary replication slot if no permanent slot is configured.
	wal_receiver_create_temp_slot?: bool & true | false | *false

	// Sets the maximum interval between WAL receiver status reports to the primary.
	wal_receiver_status_interval?: int & >= 0 & <= 2147483 | *10 @timeDurationResource(1s)

	// Sets the maximum wait time to receive data from the primary.
	wal_receiver_timeout?: int & >= 0 & <= 2147483647 | *60000 @timeDurationResource()

	// Recycles WAL files by renaming them.
	wal_recycle?: bool & true | false | *true

	// Sets the time to wait before retrying to retrieve WAL after a failed attempt.
	wal_retrieve_retry_interval?: int & >= 1 & <= 2147483647 | *5000 @timeDurationResource()

	// Sets the maximum time to wait for WAL replication.
	wal_sender_timeout?: int & >= 0 & <= 2147483647 | *60000 @timeDurationResource()

	// Minimum size of new file to fsync instead of writing WAL.
	wal_skip_threshold?: int & >= 0 & <= 2147483647 | *2048 @storeResource(1KB)

	// Selects the method used for forcing WAL updates to disk.
	wal_sync_method?: string & "fsync" | "fdatasync" | "open_sync" | "open_datasync" | *"fdatasync"

	// Time between WAL flushes performed in the WAL writer.
	wal_writer_delay?: int & >= 1 & <= 10000 | *200 @timeDurationResource()

	// Amount of WAL written out by WAL writer that triggers a flush.
	wal_writer_flush_after?: int & >= 0 & <= 2147483647 | *128 @storeResource(8KB)

	// Sets the maximum memory to be used for query workspaces.
	work_mem?: int & >= 64 & <= 2147483647 | *4096 @storeResource(1KB)

	// Sets how binary values are to be encoded in XML.
	xmlbinary?: string & "base64" | "hex" | *"base64"

	// Sets whether XML data in implicit parsing and serialization operations is to be considered as documents or content fragments.
	xmloption?: string & "content" | "document" | *"content"

	// Continues processing past damaged page headers.
	zero_damaged_pages?: bool & true | false | *false

	...
}

configuration: #PGParameter & {
}
