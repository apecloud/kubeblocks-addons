//Copyright (C) 2022-2023 ApeCloud Co., Ltd
//
//This file is part of KubeBlocks project
//
//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU Affero General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//
//This program is distributed in the hope that it will be useful
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU Affero General Public License for more details.
//
//You should have received a copy of the GNU Affero General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.

// PostgreSQL parameters: https://postgresqlco.nf/doc/en/param/
#PGParameter: {
	// use data in another directory
	data_directory?: string

	// host-based authentication file
	hba_file?: string

	// ident configuration file
	ident_file?: string

	// If external_pid_file is not explicitly set, no extra PID file is written.
	external_pid_file?: string

	// what IP address(es) to listen on;
	// comma-separated list of addresses;
	// defaults to 'localhost'; use '*' for all
	// (change requires restart)
	listen_addresses?: string

	local_bind_address?: string

	// (change requires restart)
	port?: int & >=1 & <=65535

	// (change requires restart)
	max_connections: int & >=0 & <=10000

	// Note: Increasing max_connections costs ~400 bytes of shared memory per
	// connection slot, plus lock space (see max_locks_per_transaction).
	// (change requires restart)
	sysadmin_reserved_connections?: int & >=0

	// (change requires restart)
	unix_socket_directory?: string

	// (change requires restart)
	unix_socket_group?: string

	// begin with 0 to use octal notation
	// (change requires restart)
	unix_socket_permissions?: int & >=0 & <=4095

	// 1s-600s
	authentication_timeout: int & >=1 & <=600 @timeDurationResource(1s)

	// allowed duration of any unused session, 0s-86400s (1 day), 0 is disabled
	session_timeout: int & >=0 & <=86400 @timeDurationResource(1s)

	// (change requires restart)
	ssl?: bool

	// allowed SSL ciphers
	// (change requires restart)
	ssl_ciphers?: string

	// 7-180 days
	ssl_cert_notify_time: int & >=7 & <=180

	// amount of data between renegotiations, no longer supported
	// (change requires restart)
	ssl_renegotiation_limit?: int

	// (change requires restart)
	ssl_cert_file?: string

	// (change requires restart)
	ssl_key_file?: string

	// (change requires restart)
	ssl_ca_file?: string

	// (change requires restart)
	ssl_crl_file?: string

	// Kerberos and GSSAPI
	// (change requires restart)
	krb_server_keyfile?: string

	// (Kerberos only)
	krb_srvname?: string

	// krb_caseins_users = off
	krb_caseins_users?: bool

	// Whether to change the initial password of the initial user
	modify_initial_password?: bool

	// Whether password complexity checks
	password_policy?: int & >=0 & <=1

	// Whether the new password can be reused in password_reuse_time days
	password_reuse_time?: int & >=0

	// Whether the new password can be reused
	password_reuse_max?: int & >=0

	// The account will be unlocked automatically after a specified period of time
	password_lock_time?: int & >=0

	// Enter the wrong password reached failed_login_attempts times, the current account will be locked
	failed_login_attempts?: int & >=0

	// Password storage type, 0 is md5 for PG, 1 is sha256 + md5, 2 is sha256 only
	password_encryption_type?: int & >=0 & <=2

	// The minimal password length(6-999)
	password_min_length?: int & >=6 & <=999

	// The maximal password length(6-999)
	password_max_length?: int & >=6 & <=999

	// The minimal upper character number in password(0-999)
	password_min_uppercase?: int & >=0 & <=999

	// The minimal lower character number in password(0-999)
	password_min_lowercase?: int & >=0 & <=999

	// The minimal digital character number in password(0-999)
	password_min_digital?: int & >=0 & <=999

	// The minimal special character number in password(0-999)
	password_min_special?: int & >=0 & <=999

	// The password effect time(0-999)
	password_effect_time?: int & >=0 & <=999

	// The password notify time(0-999)
	password_notify_time?: int & >=0 & <=999

	// TCP_KEEPIDLE, in seconds; 0 selects the system default
	tcp_keepalives_idle?: int & >=0

	// TCP_KEEPINTVL, in seconds; 0 selects the system default
	tcp_keepalives_interval?: int & >=0

	// TCP_KEEPCNT; 0 selects the system default
	tcp_keepalives_count?: int & >=0


	// memorypool_enable = false
	memorypool_enable?: bool

	// memorypool_size = 512MB
	memorypool_size?: string

	// enable_memory_limit = true
	enable_memory_limit?: bool

	// max_process_memory = 12GB
	max_process_memory?: string

	// UDFWorkerMemHardLimit = 1GB
	UDFWorkerMemHardLimit?: string

	// min 128kB
	// (change requires restart)
	shared_buffers: string

	// for bulkload, max shared_buffers
	bulk_write_ring_size?: string

	// control shared buffers use in standby, 0.1-1.0
	standby_shared_buffers_fraction?: float

	// min 800kB
	temp_buffers?: string

	// zero disables the feature
	// (change requires restart)
	max_prepared_transactions: int & >=0

	// min 64kB
	work_mem?: string

	// min 1MB
	maintenance_work_mem?: string

	// min 100kB
	max_stack_depth?: string

	// min 16MB
	cstore_buffers?: string

	// limits per-session temp file space in kB, or -1 for no limit
	temp_file_limit?: int

	// limits for single SQL used space on single DN in kB, or -1 for no limit
	sql_use_spacelimit?: int

	// min 25
	max_files_per_process?: int

	// (change requires restart)
	shared_preload_libraries?: string

	// 0-100 milliseconds
	vacuum_cost_delay?: int @timeDurationResource(1ms)

	// 0-10000 credits
	vacuum_cost_page_hit?: int & >=0 & <=10000

	// 0-10000 credits
	vacuum_cost_page_miss?: int & >=0 & <=10000

	// 0-10000 credits
	vacuum_cost_page_dirty?: int & >=0 & <=10000

	// 1-10000 credits
	vacuum_cost_limit?: int & >=1 & <=10000

	// 10-10000ms between rounds
	bgwriter_delay?: int @timeDurationResource(1ms)

	// 0-1000 max buffers written/round
	bgwriter_lru_maxpages?: int & >=0 & <=1000

	// 0-10.0 multipler on buffers scanned/round
	bgwriter_lru_multiplier?: float & >=0 & <=10.0

	// minimal, archive, hot_standby or logical
	// (change requires restart)
	wal_level?: string

	// turns forced synchronization on or off
	fsync?: bool

	// synchronization level;
	// off, local, remote_receive, remote_write, or on
	// It's global control for all transactions
	// It could not be modified by gs_ctl reload, unless use setsyncmode.
	synchronous_commit?: string

	// Selects the method used for forcing WAL updates to disk.
	wal_sync_method?: string & "fsync" | "fdatasync" | "open_sync" | "open_datasync" | "fsync_writethrough"

	// recover from partial page writes
	full_page_writes?: bool

	// min 32kB
	// (change requires restart)
	wal_buffers?: string

	// 1-10000 milliseconds
	wal_writer_delay?: int @timeDurationResource(1ms)

	// range 0-100000, in microseconds
	commit_delay?: int @timeDurationResource(1us)

	// range 1-1000
	commit_siblings?: int & >=1 & <=1000

	// in logfile segments, min 1, 16MB each
	checkpoint_segments?: int & >=1

	// range 30s-1h
	checkpoint_timeout?: int @timeDurationResource(1s)

	// checkpoint target duration, 0.0 - 1.0
	checkpoint_completion_target?: float & >=0.0 & <=1.0

	// 0 disables
	checkpoint_warning?: int @timeDurationResource(1s)

	// maximum time wait checkpointer to start
	checkpoint_wait_timeout?: int @timeDurationResource(1s)

	// enable incremental checkpoint
	enable_incremental_checkpoint?: bool

	// range 1s-1h
	incremental_checkpoint_timeout?: int & >=1 & <=3600 @timeDurationResource(1s)

	// dirty page writer sleep time, 0ms - 1h
	pagewriter_sleep?: int & >=1 & <=360000 @timeDurationResource(1ms)

	archive_mode?: string

	archive_command?: string

	archive_timeout?: int @timeDurationResource(1s)

	// path to use to archive a logfile segment
	archive_dest?: string


	//------------------------------------------------
	//  REPLICATION
	//-------------------------------------------------
	// The heartbeat interval of the standby nodes.
	// The value is best configured less than half of
	// the wal_receiver_timeout and wal_sender_timeout.
	datanode_heartbeat_interval?: string @timeDurationResource(1s)

	// max number of walsender processes
	// (change requires restart)
	max_wal_senders?: int

	// in logfile segments, 16MB each; 0 disables
	wal_keep_segments?: int & >=0

	// in milliseconds; 0 disables
	wal_sender_timeout?: int @timeDurationResource(1ms)

	enable_slot_log?: bool

	// max number of replication slots.
	// The value belongs to [1,7].
	// (change requires restart)
	max_replication_slots?: int & >=1 & <=7

	max_changes_in_memory?: int

	max_cached_tuplebufs?: int

	// replication connection information used to connect primary on standby, or standby on primary,
	// or connect primary or standby on secondary
	// The heartbeat thread will not start if not set localheartbeatport and remoteheartbeatport.
	// e.g. 'localhost=10.145.130.2 localport=12211 localheartbeatport=12214 remotehost=10.145.130.3 remoteport=12212 remoteheartbeatport=12215, localhost=10.145.133.2 localport=12213 remotehost=10.145.133.3 remoteport=12214'
	replconninfo1?: string

	// replication connection information used to connect secondary on primary or standby,
	// or connect primary or standby on secondary
	// e.g. 'localhost=10.145.130.2 localport=12311 localheartbeatport=12214 remotehost=10.145.130.4 remoteport=12312 remoteheartbeatport=12215, localhost=10.145.133.2 localport=12313 remotehost=10.145.133.4 remoteport=12314'
	replconninfo2?: string

	// replication connection information used to connect primary on standby, or standby on primary,
	// e.g. 'localhost=10.145.130.2 localport=12311 localheartbeatport=12214 remotehost=10.145.130.5 remoteport=12312 remoteheartbeatport=12215, localhost=10.145.133.2 localport=12313 remotehost=10.145.133.5 remoteport=12314'
	replconninfo3?: string

	// replication connection information used to connect primary on standby, or standby on primary,
	// e.g. 'localhost=10.145.130.2 localport=12311 localheartbeatport=12214 remotehost=10.145.130.6 remoteport=12312 remoteheartbeatport=12215, localhost=10.145.133.2 localport=12313 remotehost=10.145.133.6 remoteport=12314'
	replconninfo4?: string

	// replication connection information used to connect primary on standby, or standby on primary,
	// e.g. 'localhost=10.145.130.2 localport=12311 localheartbeatport=12214 remotehost=10.145.130.7 remoteport=12312 remoteheartbeatport=12215, localhost=10.145.133.2 localport=12313 remotehost=10.145.133.7 remoteport=12314'
	replconninfo5?: string

	// replication connection information used to connect primary on standby, or standby on primary,
	// e.g. 'localhost=10.145.130.2 localport=12311 localheartbeatport=12214 remotehost=10.145.130.8 remoteport=12312 remoteheartbeatport=12215, localhost=10.145.133.2 localport=12313 remotehost=10.145.133.8 remoteport=12314'
	replconninfo6?: string

	// replication connection information used to connect primary on standby, or standby on primary,
	// e.g. 'localhost=10.145.130.2 localport=12311 localheartbeatport=12214 remotehost=10.145.130.9 remoteport=12312 remoteheartbeatport=12215, localhost=10.145.133.2 localport=12313 remotehost=10.145.133.9 remoteport=12314'
	replconninfo7?: string

	// replication connection information used to connect primary on primary cluster, or standby on standby cluster,
	// e.g. 'localhost=10.145.133.2 localport=12313 remotehost=10.145.133.9 remoteport=12314'
	cross_cluster_replconninfo1?: string

	// replication connection information used to connect primary on primary cluster, or standby on standby cluster,
	// e.g. 'localhost=10.145.133.2 localport=12313 remotehost=10.145.133.9 remoteport=12314'
	cross_cluster_replconninfo2?: string

  // replication connection information used to connect primary on primary cluster, or standby on standby cluster,
	// e.g. 'localhost=10.145.133.2 localport=12313 remotehost=10.145.133.9 remoteport=12314'
	cross_cluster_replconninfo3?: string

	// replication connection information used to connect primary on primary cluster, or standby on standby cluster,
	// e.g. 'localhost=10.145.133.2 localport=12313 remotehost=10.145.133.9 remoteport=12314'
	cross_cluster_replconninfo4?: string

	//  Master Server
	// standby servers that provide sync rep
	// comma-separated list of application_name
	// from standby(s); '*' = all
	// These settings are ignored on a standby server.
	synchronous_standby_names?: string

	// Whether master is allowed to continue
	// as standbalone after sync standby failure
	// It's global control for all transactions
	most_available_sync?: bool

	// number of xacts by which cleanup is delayed
	vacuum_defer_cleanup_age?: int

	// data replication buffer size
	data_replicate_buffer_size?: string

	// Size of walsender max send size
	walsender_max_send_size?: string

	enable_data_replicate?: bool

	///  Standby Server
	// "on" allows queries during recovery
	// (change requires restart)
	// These settings are ignored on a master server.
	hot_standby?: bool

	// max delay before canceling queries
	// when reading WAL from archive;
	// -1 allows indefinite delay
	max_standby_archive_delay?: string

	// max delay before canceling queries
	// when reading streaming WAL;
	// -1 allows indefinite delay
	max_standby_streaming_delay?: string

	// send replies at least this often
	// 0 disables
	wal_receiver_status_interval?: string

	// send info from standby to prevent
	// query conflicts
	hot_standby_feedback?: bool

	// time that receiver waits for
	// communication from master
	// in milliseconds; 0 disables
	wal_receiver_timeout?: string

	// timeout that receiver connect master
	// in seconds; 0 disables
	wal_receiver_connect_timeout?: string

	// max retries that receiver connect master
	wal_receiver_connect_retries?: int

	// wal receiver buffer size
	wal_receiver_buffer_size?: string

	// xlog keep for all standbys even through they are not connecting and donnot created replslot.
	enable_xlog_prune?: bool

	// xlog keep for the wal size less than max_xlog_size when the enable_xlog_prune is on
	max_size_for_xlog_prune?: int

	// Maximum number of logical replication worker processes.
	max_logical_replication_workers?: int
	// These settings are ignored on a master server.

	enable_bitmapscan?: bool
  enable_hashagg?: bool
  enable_hashjoin?: bool
  enable_indexscan?: bool
  enable_indexonlyscan?: bool
  enable_material?: bool
  enable_mergejoin?: bool
  enable_nestloop?: bool
  enable_seqscan?: bool
  enable_sort?: bool
  enable_tidscan?: bool

  enable_kill_query?: bool
  // optional: [on, off], default: off

  // Planner Cost Constants

  seq_page_cost?: float
  // measured on an arbitrary scale

  random_page_cost?: float
  // same scale as above

  cpu_tuple_cost?: float
  // same scale as above

  cpu_index_tuple_cost?: float
  // same scale as above

  cpu_operator_cost?: float
  // same scale as above

  effective_cache_size?: string

  geqo?: bool

  geqo_threshold?: int

  geqo_effort?: int
  // range 1-10

  geqo_pool_size?: int
  // selects default based on effort

  geqo_generations?: int
  // selects default based on effort

  geqo_selection_bias?: float
  // range 1.5-2.0

  geqo_seed?: float
  // range 0.0-1.0

  default_statistics_target?: int
  // range 1-10000

  constraint_exclusion?: string
  // on, off, or partition

  cursor_tuple_fraction?: float
  // range 0.0-1.0

  from_collapse_limit?: int

  join_collapse_limit?: int
  // 1 disables collapsing of explicit JOIN clauses

  plan_mode_seed?: int
  // range -1-0x7fffffff

  check_implicit_conversions?: string
  // off

  // Valid values are combinations of stderr, csvlog, syslog, and eventlog,
  // depending on platform. csvlog requires logging_collector to be on.
  log_destination?: string

  logging_collector?: bool
  // Enable capturing of stderr and csvlog into log files. Required to be on for csvlogs.
  // (change requires restart)

  // directory where log files are written,
  // can be absolute or relative to PGDATA
  log_directory?: string

  // log file name pattern, can include strftime() escapes
  log_filename?: string

  // creation mode for log files, begin with 0 to use octal notation
  log_file_mode?: int

  // If on, an existing log file with the same name as the new log file will be
  // truncated rather than appended to. But such truncation only occurs on
  // time-driven rotation, not on restarts or size-driven rotation. Default is
  // off, meaning append to existing files in all cases.
  // log_truncate_on_rotation?: string

  // Automatic rotation of logfiles will happen after that time. 0 disables.
  // log_rotation_age?: string

  // Automatic rotation of logfiles will happen after that much log output.
  // 0 disables.
  log_rotation_size?: string

  syslog_facility?: string
  syslog_ident?: string

	event_source?: string

	log_min_messages?: string & "debug5" | "debug4" | "debug3" | "debug2" | "debug1" | "info" | "notice" | "warning" | "error" | "log" | "fatal" | "panic"
	log_min_error_statement?: string & "debug5" | "debug4" | "debug3" | "debug2" | "debug1" | "info" | "notice" | "warning" | "error" | "log" | "fatal" | "panic"

	log_min_duration_statement?: int @timeDurationResource(1min)

	debug_print_parse?: bool & true | false
  debug_print_rewritten?: bool & true | false
  debug_print_plan?: bool & true | false
  debug_pretty_print?: bool & true | false
  log_checkpoints?: bool & true | false
  log_pagewriter?: bool & true | false
  log_connections?: bool & true | false
  log_disconnections?: bool & true | false
  log_duration?: bool & true | false

	log_hostname?: bool & false | true
	log_line_prefix?: string

	log_lock_waits?: bool & false | true

	log_statement?: string & "none" | "ddl" | "mod" | "all"
	log_temp_files?: int & >=-1 & <=2147483647 @storeResource(1KB)


	// Sets the time zone to use in log messages.
	log_timezone?: string

	enable_alarm?: bool

	connection_alarm_rate?: number

	alarm_report_interval?: number

	alarm_component?: string

	track_activities?: bool
	track_counts?: bool
	track_io_timing?: bool
	track_functions?: string & "none"| "pl"| all
	track_activity_query_size?: int
	update_process_title?: bool
	stats_temp_directory?: string
	track_thread_wait_status_interval?: string
	track_sql_count?: bool
	enbale_instr_track_wait?: bool

	// Query Execution Statistics
	log_parser_stats?: string
	log_planner_stats?: string
	log_executor_stats?: string
	log_statement_stats?: string

	use_workload_manager?: string


	enable_security_policy?: bool
	use_elastic_search?: bool
	elastic_search_ip_addr?: string // what elastic search ip is, change https to http when elastic search is non-ssl mode

	cpu_collect_timer?: int

	autovacuum?: bool

	// (ms) Sets the minimum execution time above which autovacuum actions will be logged.
	log_autovacuum_min_duration: int & >=-1 & <=2147483647 | *10000 @timeDurationResource()

	// Sets the maximum number of simultaneously running autovacuum worker processes.
	autovacuum_max_workers?: int & >=1 & <=8388607

	// (s) Time to sleep between autovacuum runs.
	autovacuum_naptime: int & >=1 & <=2147483 | *15 @timeDurationResource(1s)
	// Minimum number of tuple updates or deletes prior to vacuum.
	autovacuum_vacuum_threshold?: int & >=0 & <=2147483647
	// Minimum number of tuple inserts, updates or deletes prior to analyze.
	autovacuum_analyze_threshold?: int & >=0 & <=2147483647

	// Number of tuple updates or deletes prior to vacuum as a fraction of reltuples.
	autovacuum_vacuum_scale_factor: float & >=0 & <=100 | *0.1

	// Number of tuple inserts, updates or deletes prior to analyze as a fraction of reltuples.
	autovacuum_analyze_scale_factor: float & >=0 & <=100 | *0.05

	// Age at which to autovacuum a table to prevent transaction ID wraparound.
	autovacuum_freeze_max_age?: int & >=100000 & <=2000000000

	// (ms) Vacuum cost delay in milliseconds, for autovacuum.
	autovacuum_vacuum_cost_delay?: int & >=-1 & <=100 @timeDurationResource()

	// Vacuum cost amount available before napping, for autovacuum.
	autovacuum_vacuum_cost_limit?: int & >=-1 & <=10000

	// Sets the message levels that are sent to the client.
	client_min_messages?: string & "debug5" | "debug4" | "debug3" | "debug2" | "debug1" | "log" | "notice" | "warning" | "error"

	// Sets the schema search order for names that are not schema-qualified.
	search_path?: string

	// Sets the default tablespace to create tables and indexes in.
	default_tablespace?: string

	// Sets the tablespace(s) to use for temporary tables and sort files.
	temp_tablespaces?: string

	// Check function bodies during CREATE FUNCTION.
	check_function_bodies?: bool & false | true

	// Sets the transaction isolation level of each new transaction.
	default_transaction_isolation?: string & "serializable" | "repeatable read" | "read committed" | "read uncommitted"
	// Sets the default read-only status of new transactions.
	default_transaction_read_only?: bool & false | true


	// Sets the default deferrable status of new transactions.
	default_transaction_deferrable?: bool & false | true


	// Sets the sessions behavior for triggers and rewrite rules.
	session_replication_role?: string & "origin" | "replica" | "local"

	// (ms) Sets the maximum allowed duration of any statement.
	statement_timeout?: int & >=0 & <=2147483647 @timeDurationResource()

	vacuum_freeze_min_age?: int & >=0 & <=1000000000

	vacuum_freeze_table_age?: int & >=0 & <=2000000000

	bytea_output?: string & "escape" | "hex"

	xmlbinary?: string & "base64" | "hex"

	xmloption?: string & "content" | "document"

	max_compile_functions?: int

	gin_pending_list_limit?: int & >=64 & <=2147483647 @storeResource(1KB)

	// Sets the display format for date and time values.
	datestyle?: string
	// Sets the display format for interval values.
	intervalstyle?: string & "postgres" | "postgres_verbose" | "sql_standard" | "iso_8601"

	// Sets the time zone for displaying and interpreting time stamps.
	timezone?: string

	timezone_abbreviations ?: string

	// Sets the number of digits displayed for floating-point values.
	extra_float_digits?: int & >=-15 & <=3

	// Sets the clients character set encoding.
	client_encoding?: string

	// Sets the language in which messages are displayed.
	lc_messages?: string
	// Sets the locale for formatting monetary amounts.
	lc_monetary?: string

	// Sets the locale for formatting numbers.
	lc_numeric?: string

	// Sets the locale for formatting date and time values.
	lc_time?: string

	default_text_search_config?: string

	dynamic_library_path?: string

	local_preload_libraries?: string
	// (ms) Sets the time to wait on a lock before checking for deadlock.
	deadlock_timeout?: int & >=1 & <=2147483647 @timeDurationResource()

	lockwait_timeout?: string @timeDurationResource(1s) // Max of lockwait_timeout and deadlock_timeout + 1s
	// Sets the maximum number of locks per transaction.
	max_locks_per_transaction: int & >=10 & <=2147483647 | *64

	// Sets the maximum number of predicate locks per transaction.
	max_pred_locks_per_transaction?: int & >=10 & <=2147483647
	// Enable input of NULL elements in arrays.
	array_nulls?: bool

	// Sets whether "\" is allowed in string literals.
	backslash_quote?: string & "safe_encoding" | "on" | "off"

	default_with_oids?: bool

	// Warn about backslash escapes in ordinary string literals.
	escape_string_warning?: bool & false | true

	// Enables backward compatibility mode for privilege checks on large objects.
	lo_compat_privileges: bool & false | true | *false

	// Causes ... strings to treat backslashes literally.
	standard_conforming_strings?: bool & false | true

	// Enable synchronized sequential scans.
	synchronize_seqscans?: bool & false | true

	// Treats expr=NULL as expr IS NULL.
	transform_null_equals?: bool & false | true


	// Terminate session on any error.
	exit_on_error?: bool & false | true

	// Reinitialize server after backend crash.
	restart_after_crash?: bool & false | true

	omit_encoding_error?: bool & false | true

	data_sync_retry?: bool & false | true

	cache_connection?: bool & false | true

	pgxc_node_name?: string

	enforce_two_phase_commit?: bool & false | true

	audit_enabled?: bool
	audit_directory?: string
	audit_data_format?: string
	audit_rotation_interval?: string  @timeDurationResource(1d)
	audit_rotation_size?: int  @storeResource(1MB)
	audit_space_limit?: int  @storeResource(1MB)
	audit_file_remain_threshold?: int & >=0 & <=2147483647
	audit_login_logout?: int & >=0
	audit_database_process?: int & >=0
	audit_user_locked?: int & >=0
	audit_user_violation?: int & >=0
	audit_grant_revoke?: int & >=0
	audit_system_object?: int & >=0
	audit_dml_state?: int & >=0
	audit_dml_state_select?: int & >=0
	audit_function_exec?: int & >=0
	audit_copy_exec?: int & >=0
	audit_set_parameter?: int & >=0
	audit_xid_info?: int & >=0
	audit_thread_num?: int & >=0

	enableSeparationOfDuty?: bool

	enable_fast_allocate?: bool
	prefetch_quantity?: int  @storeResource(1MB)
	backwrite_quantity?: int  @storeResource(1MB)
	cstore_prefetch_quantity?: int & >=0
	cstore_backwrite_quantity?: int & >=0
	cstore_backwrite_max_threshold?: int & >=0
	fast_extend_file_size?: int & >=0

	enable_codegen?: bool
	enable_codegen_print?: bool
	codegen_cost_threshold?: int


	job_queue_processes?: int & >=0 & <=1000

	enable_dcf?: bool
	plsql_show_all_error?: bool

	...
}

configuration: #PGParameter & {
}
